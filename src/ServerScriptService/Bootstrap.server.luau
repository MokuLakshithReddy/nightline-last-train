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
}

for _, remoteName in ipairs(REQUIRED_REMOTES) do
	if not remotesFolder:FindFirstChild(remoteName) then
		local remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = remotesFolder
	end
end

local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("ServerBootstrap")

log:Info("==================================================")
log:Info("  NIGHTLINE: LAST TRAIN — SERVER INITIALIZING    ")
log:Info("==================================================")

-- Load services in strict dependency order
local servicesFolder = ServerScriptService:WaitForChild("Services")

local SecurityService = require(servicesFolder:WaitForChild("SecurityService"))
local AnalyticsService = require(servicesFolder:WaitForChild("AnalyticsService"))
local PlayerDataService = require(servicesFolder:WaitForChild("PlayerDataService"))
local InventoryService = require(servicesFolder:WaitForChild("InventoryService"))
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

	local validSlot, slot = SecurityService.ValidateNumber(slotIndex, 1, 2)
	local validId, id = SecurityService.ValidateString(itemId, 32)
	if not validSlot or not slot or not validId then return end

	-- Authoritative inventory equipment change
	InventoryService.SetSlotItem(player, slot, id)
end)

local requestDestinationVoteRemote = remotesFolder:WaitForChild("RequestDestinationVote") :: RemoteEvent
requestDestinationVoteRemote.OnServerEvent:Connect(function(player: Player, stationId: any)
	if not SecurityService.CheckRateLimit(player, 1) then return end
	local valid, str = SecurityService.ValidateString(stationId, 32)
	if not valid or not str then return end

	log:Info("Player voted for destination", { Player = player.Name, Destination = str })
end)

-- Construct or verify Train Hub geometry in Workspace.World.Hub
HubBuilder.BuildHub()

-- Start the authoritative round loop
RoundService.StartGameLoop()

log:Info("Server initialization complete. Listening for connections.")
