--!strict
-- PurchaseService.luau
-- Authoritative server receipt validation, idempotent developer product processing, and game pass entitlement orchestration

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonetizationConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MonetizationConfig"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("PurchaseService")

local notificationRemote: RemoteEvent? = nil

-- In-memory idempotency cache for processed receipts during server lifetime
local processedReceipts: { [string]: boolean } = {}
local inFlightReceipts: { [string]: boolean } = {}
local inFlightPlayers: { [number]: string } = {}

local PurchaseService = {}

export type ReceiptInfo = {
	PurchaseId: string,
	PlayerId: number,
	ProductId: number,
	CurrencySpent: number,
	CurrencyType: Enum.CurrencyType,
	PlaceIdWherePurchased: number,
}

-- Server receipt processor callback required by MarketplaceService
function PurchaseService.ProcessReceipt(receiptInfo: ReceiptInfo): Enum.ProductPurchaseDecision
	local purchaseId = receiptInfo.PurchaseId
	local playerId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId

	-- 1. Idempotency fast-path cache: if already marked processed in server session, grant immediately
	if processedReceipts[purchaseId] then
		log:Info("Receipt already processed in session cache; returning PurchaseGranted immediately", {
			PurchaseId = purchaseId,
			PlayerId = playerId,
		})
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- 2. Concurrency guard: if this exact receipt is already in flight, wait or defer to prevent duplicate grant
	if inFlightReceipts[purchaseId] then
		log:Warn("Concurrent ProcessReceipt callback already in flight for receipt; waiting/deferring", {
			PurchaseId = purchaseId,
			PlayerId = playerId,
		})
		local waited = 0
		while inFlightReceipts[purchaseId] and waited < 2.0 do
			task.wait(0.1)
			waited += 0.1
		end
		if processedReceipts[purchaseId] then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 3. Per-player receipt serialization: serialize processing if player has another receipt active
	while inFlightPlayers[playerId] and inFlightPlayers[playerId] ~= purchaseId do
		task.wait(0.1)
		if processedReceipts[purchaseId] then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	-- Check fast-path cache again in case another thread processed it while waiting
	if processedReceipts[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Acquire in-flight locks
	inFlightReceipts[purchaseId] = true
	inFlightPlayers[playerId] = purchaseId

	local function executeGrant(): Enum.ProductPurchaseDecision
		-- 4. Verify player is currently active in the server
		local player = Players:GetPlayerByUserId(playerId)
		if not player then
			log:Warn("Player not found in server during receipt processing; will retry when connected", {
				PlayerId = playerId,
				PurchaseId = purchaseId,
			})
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- 5. Verify player profile is writable (must hold valid active session lock)
		if not PlayerDataService.IsProfileWritable(player) then
			log:Warn("Player profile is not writable (session lock pending/failed); deferring receipt grant", {
				PlayerId = playerId,
				PurchaseId = purchaseId,
			})
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local profile = PlayerDataService.GetProfile(player)
		if not profile then
			log:Warn("Player profile missing in cache; deferring receipt grant", {
				PlayerId = playerId,
				PurchaseId = purchaseId,
			})
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- 6. Durable receipt check: if already persisted in profile.ProcessedReceipts, return PurchaseGranted
		if profile.ProcessedReceipts and profile.ProcessedReceipts[purchaseId] then
			processedReceipts[purchaseId] = true
			log:Info("Receipt already persisted in player profile; returning PurchaseGranted (durable idempotency)", {
				PurchaseId = purchaseId,
				PlayerId = playerId,
			})
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		-- 7. Validate product against server-owned DeveloperProducts catalog
		local productDef = MonetizationConfig.DeveloperProducts[productId]
		if not productDef then
			log:Error("Unknown developer product ID in receipt; rejecting grant without recording", {
				ProductId = productId,
				PurchaseId = purchaseId,
			})
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- 8. Prepare snapshot for atomic rollback in case durable persistence fails
		local previousScrap = profile.Scrap
		local previousOwnedCosmetic = profile.OwnedCosmetics[productDef.GrantValue]

		if not profile.ProcessedReceipts then
			profile.ProcessedReceipts = {}
		end

		-- Apply entitlement grant
		local grantOk = false
		if productDef.GrantType == "Scrap" then
			grantOk = PlayerDataService.AddScrap(player, productDef.GrantValue)
		elseif productDef.GrantType == "Cosmetic" then
			grantOk = PlayerDataService.AddCosmetic(player, productDef.GrantValue)
		end

		if not grantOk then
			log:Error("Failed to apply entitlement grant in memory; deferring receipt", {
				Player = player.Name,
				Product = productDef.Name,
				PurchaseId = purchaseId,
			})
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- Atomically record receipt ID in profile data
		profile.ProcessedReceipts[purchaseId] = true

		-- 9. Durably persist both entitlement and receipt marker before acknowledging purchase
		local saveSuccess = PlayerDataService.SaveProfile(player)
		if not saveSuccess then
			-- Rollback in-memory changes so local cache reflects durable storage state
			if productDef.GrantType == "Scrap" then
				profile.Scrap = previousScrap
			elseif productDef.GrantType == "Cosmetic" then
				profile.OwnedCosmetics[productDef.GrantValue] = previousOwnedCosmetic
			end
			profile.ProcessedReceipts[purchaseId] = nil
			PlayerDataService.Sync(player, profile)

			log:Warn("Failed to durably persist receipt and entitlement; rolled back in-memory state and deferred receipt", {
				Player = player.Name,
				Product = productDef.Name,
				PurchaseId = purchaseId,
			})
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- 10. Durable save succeeded; record in fast-path cache and notify client
		processedReceipts[purchaseId] = true

		log:Info("Developer product purchase successfully granted, persisted, and acknowledged", {
			Player = player.Name,
			Product = productDef.Name,
			PurchaseId = purchaseId,
			GrantValue = productDef.GrantValue,
		})

		-- Telemetry logging
		AnalyticsService.TrackEvent("DeveloperProductPurchased", player, {
			PurchaseId = purchaseId,
			ProductId = productId,
			ProductName = productDef.Name,
			GrantType = productDef.GrantType,
			GrantValue = productDef.GrantValue,
		})

		-- Player feedback
		if notificationRemote then
			notificationRemote:FireClient(player, {
				MessageKey = "PURCHASE_SUCCESS",
				MessageText = string.format("Purchase successful: %s added to inventory!", productDef.Name),
				Severity = "Success",
				Duration = 4,
			})
		end

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local ok, result = pcall(executeGrant)

	-- Release in-flight locks unconditionally on all paths
	inFlightReceipts[purchaseId] = nil
	if inFlightPlayers[playerId] == purchaseId then
		inFlightPlayers[playerId] = nil
	end

	if not ok then
		log:Error("Unexpected error during receipt execution; releasing locks and deferring", {
			PurchaseId = purchaseId,
			Error = tostring(result),
		})
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return result
end

-- Checks and applies game pass ownership for a player
function PurchaseService.CheckGamePassEntitlements(player: Player)
	if not PlayerDataService.IsProfileWritable(player) then return end

	for passId, passDef in pairs(MonetizationConfig.GamePasses) do
		local ownsPass = false
		local ok, err = pcall(function()
			ownsPass = MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)

		if ok and ownsPass then
			if passDef.GrantType == "Cosmetic" then
				PlayerDataService.AddCosmetic(player, passDef.GrantValue)
			end
			log:Info("Verified game pass entitlement for player", {
				Player = player.Name,
				GamePass = passDef.Name,
			})
		elseif not ok then
			log:Warn("Failed to check game pass ownership; will retry later", {
				Player = player.Name,
				GamePassId = passId,
				Error = tostring(err),
			})
		end
	end
end

function PurchaseService.IsReceiptProcessed(purchaseId: string, player: Player?): boolean
	if processedReceipts[purchaseId] == true then
		return true
	end
	if player then
		local profile = PlayerDataService.GetProfile(player)
		if profile and profile.ProcessedReceipts and profile.ProcessedReceipts[purchaseId] == true then
			return true
		end
	end
	return false
end

function PurchaseService.IsReceiptInFlight(purchaseId: string): boolean
	return inFlightReceipts[purchaseId] == true
end

function PurchaseService.SimulateReceipt(player: Player, productId: number, purchaseId: string?): (boolean, string?)
	local pid = purchaseId or ("SimReceipt_" .. tostring(os.clock()))
	local receipt: ReceiptInfo = {
		PurchaseId = pid,
		PlayerId = player.UserId,
		ProductId = productId,
		CurrencySpent = 0,
		CurrencyType = Enum.CurrencyType.Robux,
		PlaceIdWherePurchased = game.PlaceId,
	}

	local result = PurchaseService.ProcessReceipt(receipt)
	if result == Enum.ProductPurchaseDecision.PurchaseGranted then
		return true, nil
	else
		return false, "Receipt processing failed or deferred"
	end
end

function PurchaseService.Init()
	log:Info("Initializing authoritative PurchaseService...")

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	notificationRemote = remotes:FindFirstChild("Notification") :: RemoteEvent?

	-- Bind authoritative ProcessReceipt callback to MarketplaceService
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return PurchaseService.ProcessReceipt(receiptInfo :: any)
	end

	-- Check game pass entitlements when player joins
	Players.PlayerAdded:Connect(function(player)
		task.delay(1.0, function()
			PurchaseService.CheckGamePassEntitlements(player)
		end)
	end)

	-- Handle game pass purchase prompts completed in-game
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, wasPurchased: boolean)
		if not wasPurchased then return end

		local passDef = MonetizationConfig.GamePasses[gamePassId]
		if not passDef then
			log:Warn("Unrecognized game pass ID purchased", { GamePassId = gamePassId })
			return
		end

		if not PlayerDataService.IsProfileWritable(player) then
			log:Warn("Cannot grant game pass: profile is currently read-only", { Player = player.Name })
			return
		end

		if passDef.GrantType == "Cosmetic" then
			PlayerDataService.AddCosmetic(player, passDef.GrantValue)
		end

		AnalyticsService.TrackEvent("GamePassPurchased", player, {
			GamePassId = gamePassId,
			GamePassName = passDef.Name,
		})

		if notificationRemote then
			notificationRemote:FireClient(player, {
				MessageKey = "GAMEPASS_GRANTED",
				MessageText = string.format("Unlocked: %s!", passDef.Name),
				Severity = "Success",
				Duration = 5,
			})
		end

		PlayerDataService.SaveProfile(player)
	end)

	log:Info("PurchaseService initialization complete. MarketplaceService.ProcessReceipt active.")
end

return PurchaseService
