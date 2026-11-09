--!strict
-- InventoryService.luau
-- Authoritative equipment slots and mission item tracking per player

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"):WaitForChild("GameTypes"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ItemConfig"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("InventoryService")

local inventories: { [number]: GameTypes.PlayerInventory } = {}
local inventoryUpdatedRemote: RemoteEvent? = nil

local InventoryService = {}

function InventoryService.Init()
	log:Info("Initializing InventoryService...")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	inventoryUpdatedRemote = remotes:WaitForChild("InventoryUpdated") :: RemoteEvent

	Players.PlayerAdded:Connect(function(player)
		InventoryService.ResetInventory(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		inventories[player.UserId] = nil
	end)
end

function InventoryService.ResetInventory(player: Player)
	inventories[player.UserId] = {
		Slot1 = {
			Id = "Flashlight",
			Name = "Standard Flashlight",
			Type = "Equipment",
			Quantity = 1,
		},
		Slot2 = nil,
		MissionItems = {},
	}
	InventoryService.Sync(player)
end

function InventoryService.GetInventory(player: Player): GameTypes.PlayerInventory?
	return inventories[player.UserId]
end

function InventoryService.SetSlotItem(player: Player, slot: number, itemId: string?): boolean
	local inv = inventories[player.UserId]
	if not inv then return false end

	if not itemId then
		if slot == 1 then inv.Slot1 = nil elseif slot == 2 then inv.Slot2 = nil end
		InventoryService.Sync(player)
		return true
	end

	local itemDef = ItemConfig.Items[itemId]
	if not itemDef then return false end

	local newItem: GameTypes.InventoryItem = {
		Id = itemDef.Id,
		Name = itemDef.Name,
		Type = itemDef.Type,
		Quantity = 1,
	}

	if slot == 1 then
		inv.Slot1 = newItem
	elseif slot == 2 then
		inv.Slot2 = newItem
	else
		return false
	end

	InventoryService.Sync(player)
	return true
end

function InventoryService.AddMissionItem(player: Player, itemId: string, count: number)
	local inv = inventories[player.UserId]
	if not inv then return end

	local current = inv.MissionItems[itemId] or 0
	inv.MissionItems[itemId] = current + count
	log:Info("Added mission item", { UserId = player.UserId, ItemId = itemId, Total = inv.MissionItems[itemId] })
	InventoryService.Sync(player)
end

function InventoryService.HasMissionItem(player: Player, itemId: string): boolean
	local inv = inventories[player.UserId]
	if not inv then return false end
	return (inv.MissionItems[itemId] or 0) > 0
end

function InventoryService.ConsumeMissionItem(player: Player, itemId: string): boolean
	local inv = inventories[player.UserId]
	if not inv then return false end

	local current = inv.MissionItems[itemId] or 0
	if current <= 0 then return false end

	inv.MissionItems[itemId] = current - 1
	InventoryService.Sync(player)
	return true
end

function InventoryService.Sync(player: Player)
	local inv = inventories[player.UserId]
	if not inv or not inventoryUpdatedRemote then return end
	inventoryUpdatedRemote:FireClient(player, inv)
end

return InventoryService

