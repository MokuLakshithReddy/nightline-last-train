--!strict
-- InventoryService.luau
-- Authoritative equipment slots, mission item tracking, and verified ownership/consumable deductions

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
	log:Info("Initializing InventoryService with authoritative ownership checks...")
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

-- Validates whether a player owns or is eligible to equip an item
function InventoryService.ValidateItemEligibility(player: Player, itemId: string): (boolean, string?)
	local itemDef = ItemConfig.Items[itemId]
	if not itemDef then
		return false, "Unknown item ID"
	end

	-- Starter equipment available to all crew members
	if itemId == "Flashlight" or itemId == "Battery" then
		return true, nil
	end

	-- Mission items cannot be equipped into standard equipment slots
	if itemDef.Type == "MissionItem" then
		return false, "Mission items are tracked automatically"
	end

	-- Upgraded/Consumable items require PlayerData check
	local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
	local profile = PlayerDataService.GetProfile(player)
	if not profile then
		return false, "Player profile not loaded"
	end

	if itemId == "Flare" then
		if not profile.TrainUpgrades["WorkbenchLocker"] and profile.Scrap < 10 then
			return false, "Requires Equipment Locker train upgrade or 10 Scrap to purchase"
		end
		return true, nil
	end

	return true, nil
end

function InventoryService.SetSlotItem(player: Player, slot: number, itemId: string?): (boolean, string?)
	local inv = inventories[player.UserId]
	if not inv then return false, "No inventory found" end

	if not itemId then
		if slot == 1 then inv.Slot1 = nil elseif slot == 2 then inv.Slot2 = nil end
		InventoryService.Sync(player)
		return true, nil
	end

	local eligible, reason = InventoryService.ValidateItemEligibility(player, itemId)
	if not eligible then
		log:Warn("Player attempted to equip ineligible item", {
			Player = player.Name,
			ItemId = itemId,
			Reason = reason,
		})
		return false, reason
	end

	local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
	local profile = PlayerDataService.GetProfile(player)

	-- If equipping a consumable Flare without the permanent WorkbenchLocker upgrade, deduct Scrap
	if itemId == "Flare" and profile and not profile.TrainUpgrades["WorkbenchLocker"] then
		local currentSlotItem = (slot == 1 and inv.Slot1) or (slot == 2 and inv.Slot2)
		if not (currentSlotItem and currentSlotItem.Id == "Flare") then
			local successDeduct = PlayerDataService.DeductScrap(player, 10)
			if not successDeduct then
				return false, "Insufficient Scrap balance (requires 10 Scrap)"
			end
			log:Info("Deducted 10 Scrap for consumable Flare purchase & equip", { Player = player.Name })
		end
	end

	local itemDef = ItemConfig.Items[itemId]
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
		return false, "Invalid slot index"
	end

	InventoryService.Sync(player)
	return true, nil
end

function InventoryService.HasEquippedItem(player: Player, itemId: string): boolean
	local inv = inventories[player.UserId]
	if not inv then return false end
	return (inv.Slot1 ~= nil and inv.Slot1.Id == itemId) or (inv.Slot2 ~= nil and inv.Slot2.Id == itemId)
end

function InventoryService.ConsumeEquippedItem(player: Player, itemId: string): boolean
	local inv = inventories[player.UserId]
	if not inv then return false end

	if inv.Slot1 and inv.Slot1.Id == itemId then
		if inv.Slot1.Quantity > 1 then
			inv.Slot1.Quantity -= 1
		else
			inv.Slot1 = nil
		end
		InventoryService.Sync(player)
		return true
	elseif inv.Slot2 and inv.Slot2.Id == itemId then
		if inv.Slot2.Quantity > 1 then
			inv.Slot2.Quantity -= 1
		else
			inv.Slot2 = nil
		end
		InventoryService.Sync(player)
		return true
	end

	return false
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