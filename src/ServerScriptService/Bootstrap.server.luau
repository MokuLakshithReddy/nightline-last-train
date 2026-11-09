--!strict
-- Bootstrap.server.luau
-- Authoritative server entry point and service orchestrator for NIGHTLINE: LAST TRAIN

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Ensure Remotes folder and documented RemoteEvents exist
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

local REQUIRED_REMOTES = {
	"RoundStateChanged",
	"ObjectiveUpdated",
	"PlayerStatusUpdated",
	"InventoryUpdated",
	"Notification",
	"RequestEquipment",
	"RequestDestinationVote",
	"RequestPurchaseUpgrade",
	"ProfileUpdated",
	"ToggleFlashlight",
	"ThrowFlare",
	"RequestSprint",
}

for _, remoteName in ipairs(REQUIRED_REMOTES) do
	if not remotesFolder:FindFirstChild(remoteName) then
		local remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = remotesFolder
	end
end

local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local log = Logger.new("ServerBootstrap")

log:Info("==================================================")
log:Info("  NIGHTLINE: LAST TRAIN — SERVER INITIALIZING     ")
log:Info("==================================================")

-- Load services in strict dependency order
local servicesFolder = ServerScriptService:WaitForChild("Services")

local SecurityService = require(servicesFolder:WaitForChild("SecurityService"))
local AnalyticsService = require(servicesFolder:WaitForChild("AnalyticsService"))
local PlayerDataService = require(servicesFolder:WaitForChild("PlayerDataService"))
local InventoryService = require(servicesFolder:WaitForChild("InventoryService"))
local EquipmentService = require(servicesFolder:WaitForChild("EquipmentService"))
local MovementService = require(servicesFolder:WaitForChild("MovementService"))
local InteractionService = require(servicesFolder:WaitForChild("InteractionService"))
local StationService = require(servicesFolder:WaitForChild("StationService"))
local ObjectiveService = require(servicesFolder:WaitForChild("ObjectiveService"))
local MonsterService = require(servicesFolder:WaitForChild("MonsterService"))
local RewardService = require(servicesFolder:WaitForChild("RewardService"))
local RoundService = require(servicesFolder:WaitForChild("RoundService"))
local HubBuilder = require(servicesFolder:WaitForChild("HubBuilder"))

-- Initialize services
SecurityService.Init()
AnalyticsService.Init()
PlayerDataService.Init()
InventoryService.Init()
EquipmentService.Init()
MovementService.Init()
InteractionService.Init()
StationService.Init()
ObjectiveService.Init()
MonsterService.Init()
RewardService.Init()
RoundService.Init()

-- Wire up client-to-server remotes with authoritative validation
local requestEquipmentRemote = remotesFolder:WaitForChild("RequestEquipment") :: RemoteEvent
requestEquipmentRemote.OnServerEvent:Connect(function(player: Player, slotIndex: any, itemId: any)
	if not SecurityService.CheckRateLimit(player, 1) then return end

	-- Reject non-integer, NaN, infinite, and out-of-range slot values at the remote boundary
	local validSlot, slot = SecurityService.ValidateInteger(slotIndex, 1, 2)
	if not validSlot or not slot then
		local notifRemote = remotesFolder:FindFirstChild("Notification") :: RemoteEvent?
		if notifRemote then
			notifRemote:FireClient(player, {
				MessageKey = "EQUIP_REJECTED",
				MessageText = "Invalid equipment slot specified (must be slot 1 or 2).",
				Severity = "Warning",
				Duration = 3,
			})
		end
		return
	end

	local validId, id = SecurityService.ValidateString(itemId, 32)

	-- Check Phase Restriction (Equipment loadouts restricted to Hub preparation)
	local currentPhase = RoundService.GetCurrentState()
	local allowedPhase = (currentPhase == "WAITING" or currentPhase == "INTERMISSION" or currentPhase == "BOARDING")
	if not allowedPhase then
		local notifRemote = remotesFolder:FindFirstChild("Notification") :: RemoteEvent?
		if notifRemote then
			notifRemote:FireClient(player, {
				MessageKey = "EQUIP_RESTRICTED",
				MessageText = "Equipment loadouts can only be changed in the Hub before departure!",
				Severity = "Warning",
				Duration = 3,
			})
		end
		return
	end

	-- Authoritative inventory equipment change with ownership validation
	local success, reason = InventoryService.SetSlotItem(player, slot, validId and id or nil)
	if not success and reason then
		local notifRemote = remotesFolder:FindFirstChild("Notification") :: RemoteEvent?
		if notifRemote then
			notifRemote:FireClient(player, {
				MessageKey = "EQUIP_REJECTED",
				MessageText = reason,
				Severity = "Warning",
				Duration = 3,
			})
		end
	end
end)

local requestDestinationVoteRemote = remotesFolder:WaitForChild("RequestDestinationVote") :: RemoteEvent
requestDestinationVoteRemote.OnServerEvent:Connect(function(player: Player, stationId: any)
	if not SecurityService.CheckRateLimit(player, 1) then return end
	local valid, str = SecurityService.ValidateString(stationId, 32)
	if not valid or not str then return end

	log:Info("Player voted for destination", { Player = player.Name, Destination = str })
end)

local requestPurchaseUpgradeRemote = remotesFolder:WaitForChild("RequestPurchaseUpgrade") :: RemoteEvent
requestPurchaseUpgradeRemote.OnServerEvent:Connect(function(player: Player, upgradeId: any)
	if not SecurityService.CheckRateLimit(player, 2) then return end
	local valid, id = SecurityService.ValidateString(upgradeId, 32)
	if not valid or not id then return end

	-- 1. Validate character and alive state
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		local notifRemote = remotesFolder:FindFirstChild("Notification") :: RemoteEvent?
		if notifRemote then
			notifRemote:FireClient(player, {
				MessageKey = "UPGRADE_REJECTED",
				MessageText = "You must be alive to access the upgrade terminal.",
				Severity = "Warning",
				Duration = 3,
			})
		end
		return
	end

	-- 2. Phase restriction: purchases only permitted in Hub preparation phases
	local currentPhase = RoundService.GetCurrentState()
	local allowedPhase = (currentPhase == "WAITING" or currentPhase == "INTERMISSION" or currentPhase == "BOARDING")
	if not allowedPhase then
		local notifRemote = remotesFolder:FindFirstChild("Notification") :: RemoteEvent?
		if notifRemote then
			notifRemote:FireClient(player, {
				MessageKey = "UPGRADE_RESTRICTED",
				MessageText = "Upgrades can only be purchased in the Hub before departure!",
				Severity = "Warning",
				Duration = 3,
			})
		end
		return
	end

	-- 3. Proximity validation: must be within interaction range of the Train Workshop Terminal
	local terminalPart = HubBuilder.GetUpgradeTerminal()
	local terminalPosition = terminalPart and terminalPart.Position or HubBuilder.TerminalPosition
	local prompt = terminalPart and terminalPart:FindFirstChildWhichIsA("ProximityPrompt")
	local maxDistance = prompt and (prompt.MaxActivationDistance + 4) or GameConfig.Security.MaxInteractionDistance

	if not SecurityService.ValidateDistance(player, terminalPosition, maxDistance) then
		local notifRemote = remotesFolder:FindFirstChild("Notification") :: RemoteEvent?
		if notifRemote then
			notifRemote:FireClient(player, {
				MessageKey = "UPGRADE_TOO_FAR",
				MessageText = "You are too far from the Train Workshop Terminal.",
				Severity = "Warning",
				Duration = 3,
			})
		end
		return
	end

	local success, message = PlayerDataService.PurchaseUpgrade(player, id)
	local notifRemote = remotesFolder:FindFirstChild("Notification") :: RemoteEvent?
	if notifRemote then
		notifRemote:FireClient(player, {
			MessageKey = "UPGRADE_PURCHASE",
			MessageText = message,
			Severity = success and "Success" or "Warning",
			Duration = 4,
		})
	end
end)

-- Construct or verify Train Hub geometry in Workspace.World.Hub
HubBuilder.BuildHub()

-- Start the authoritative round loop
RoundService.StartGameLoop()

log:Info("Server initialization complete. Listening for connections.")