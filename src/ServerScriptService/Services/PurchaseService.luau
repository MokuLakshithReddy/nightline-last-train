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

	-- 1. Idempotency guard: if this receipt was already granted, return PurchaseGranted immediately
	if processedReceipts[purchaseId] then
		log:Info("Receipt already processed; returning PurchaseGranted immediately (idempotent)", {
			PurchaseId = purchaseId,
			PlayerId = playerId,
		})
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- 2. Verify player is currently active in the server
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		log:Warn("Player not found in server during receipt processing; will retry when connected", {
			PlayerId = playerId,
			PurchaseId = purchaseId,
		})
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 3. Verify player profile is writable (must hold valid active session lock)
	if not PlayerDataService.IsProfileWritable(player) then
		log:Warn("Player profile is not writable (session lock pending/failed); deferring receipt grant", {
			PlayerId = playerId,
			PurchaseId = purchaseId,
		})
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 4. Validate product against server-owned DeveloperProducts catalog
	local productDef = MonetizationConfig.DeveloperProducts[productId]
	if not productDef then
		log:Error("Unknown developer product ID in receipt; rejecting grant", {
			ProductId = productId,
			PurchaseId = purchaseId,
		})
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 5. Execute entitlement grant based on configured grant type
	local grantOk = false
	if productDef.GrantType == "Scrap" then
		grantOk = PlayerDataService.AddScrap(player, productDef.GrantValue)
	elseif productDef.GrantType == "Cosmetic" then
		grantOk = PlayerDataService.AddCosmetic(player, productDef.GrantValue)
	end

	if not grantOk then
		log:Error("Failed to apply entitlement grant to player profile; deferring receipt", {
			Player = player.Name,
			Product = productDef.Name,
			PurchaseId = purchaseId,
		})
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 6. Mark receipt as processed in idempotency registry
	processedReceipts[purchaseId] = true

	log:Info("Developer product purchase successfully granted and recorded", {
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

	-- Ensure profile is saved promptly
	PlayerDataService.SaveProfile(player)

	return Enum.ProductPurchaseDecision.PurchaseGranted
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

function PurchaseService.IsReceiptProcessed(purchaseId: string): boolean
	return processedReceipts[purchaseId] == true
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
