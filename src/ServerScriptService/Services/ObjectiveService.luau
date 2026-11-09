--!strict
-- ObjectiveService.luau
-- Authoritative objective mechanics, physical entity spawning, and interaction routing

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local GameTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"):WaitForChild("GameTypes"))
local ObjectiveConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ObjectiveConfig"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Signal"))
local log = Logger.new("ObjectiveService")

local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local InteractionService = require(script.Parent:WaitForChild("InteractionService"))

local activeMission: GameTypes.MissionState? = nil
local objectiveUpdatedRemote: RemoteEvent? = nil
local notificationRemote: RemoteEvent? = nil

-- Runtime objective entity tracking
local spawnedEntities: { Instance } = {}
local carryingCargo: { [number]: Instance } = {}

local ObjectiveService = {
	OnMissionCompleted = Signal.new(),
}

local function createPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function ObjectiveService.Init()
	log:Info("Initializing ObjectiveService...")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	objectiveUpdatedRemote = remotes:WaitForChild("ObjectiveUpdated") :: RemoteEvent
	notificationRemote = remotes:WaitForChild("Notification") :: RemoteEvent

	ObjectiveService.BindInteractions()
end

function ObjectiveService.BindInteractions()
	InteractionService.OnPromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		local promptName = prompt.Name
		local targetPart = prompt.Parent :: BasePart?
		if not targetPart then return end

		-- 1. FUSE PICKUP INTERACTION
		if promptName == "PickUpFusePrompt" then
			InventoryService.AddMissionItem(player, "Fuse", 1)
			targetPart:Destroy()
			log:Info("Player collected fuse", { Player = player.Name })
			if notificationRemote then
				notificationRemote:FireClient(player, {
					MessageKey = "FUSE_ACQUIRED",
					MessageText = "Industrial Fuse acquired! Install in Maintenance Breakers.",
					Severity = "Info",
					Duration = 4,
				})
			end

		-- 2. FUSE SOCKET INSTALLATION
		elseif promptName == "InstallFusePrompt" then
			if not activeMission or activeMission.Type ~= "RestorePower" then return end
			if not InventoryService.HasMissionItem(player, "Fuse") then
				if notificationRemote then
					notificationRemote:FireClient(player, {
						MessageKey = "NO_FUSE",
						MessageText = "You need an Industrial Fuse to activate this breaker!",
						Severity = "Warning",
						Duration = 3,
					})
				end
				return
			end

			InventoryService.ConsumeMissionItem(player, "Fuse")
			prompt.Enabled = false

			-- Visual change: Indicator turns green
			local indicator = targetPart:FindFirstChild("IndicatorLight") :: BasePart?
			if indicator then
				indicator.Color = Color3.fromRGB(50, 240, 80)
			end

			ObjectiveService.AddProgress(1)

		-- 3. CARGO CRATE PICKUP
		elseif promptName == "PickUpCargoPrompt" then
			if not activeMission or activeMission.Type ~= "RecoverCargo" then return end
			if carryingCargo[player.UserId] then
				if notificationRemote then
					notificationRemote:FireClient(player, {
						MessageKey = "ALREADY_CARRYING",
						MessageText = "You are already carrying a cargo container!",
						Severity = "Warning",
						Duration = 3,
					})
				end
				return
			end

			-- Attach visual crate to player's torso
			local character = player.Character
			if character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) then
				local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart
				local carriedBox = createPart(character, "CarriedCargo", Vector3.new(2, 2, 2), torso.CFrame, Color3.fromRGB(220, 180, 50), Enum.Material.Wood)
				carriedBox.CanCollide = false
				carriedBox.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = torso
				weld.Part1 = carriedBox
				weld.Parent = carriedBox
				carriedBox.CFrame = torso.CFrame * CFrame.new(0, 0, 1.2)
				carryingCargo[player.UserId] = carriedBox
			end

			InventoryService.AddMissionItem(player, "CargoContainer", 1)
			targetPart:Destroy()

			if notificationRemote then
				notificationRemote:FireClient(player, {
					MessageKey = "CARGO_SECURED",
					MessageText = "Cargo secured! Deliver it to the train platform pallet.",
					Severity = "Info",
					Duration = 4,
				})
			end

		-- 4. CARGO DROP-OFF ON PLATFORM
		elseif promptName == "DeliverCargoPrompt" then
			if not activeMission or activeMission.Type ~= "RecoverCargo" then return end
			if not InventoryService.HasMissionItem(player, "CargoContainer") then
				if notificationRemote then
					notificationRemote:FireClient(player, {
						MessageKey = "NO_CARGO",
						MessageText = "You must be carrying a cargo container to deliver here!",
						Severity = "Warning",
						Duration = 3,
					})
				end
				return
			end

			InventoryService.ConsumeMissionItem(player, "CargoContainer")
			if carryingCargo[player.UserId] then
				carryingCargo[player.UserId]:Destroy()
				carryingCargo[player.UserId] = nil
			end

			-- Place secured crate visually on pallet
			local deliveredCrate = createPart(
				targetPart,
				"DeliveredCrate",
				Vector3.new(2.4, 2.4, 2.4),
				targetPart.CFrame * CFrame.new(0, 1.5, 0),
				Color3.fromRGB(220, 180, 50),
				Enum.Material.Wood
			)
			table.insert(spawnedEntities, deliveredCrate)

			ObjectiveService.AddProgress(1)

		-- 5. SIGNAL RELAY TERMINAL REBOOT
		elseif promptName == "RebootSignalPrompt" then
			if not activeMission or activeMission.Type ~= "RepairSignal" then return end
			prompt.Enabled = false

			-- Visual change: Screen turns green
			local monitor = targetPart:FindFirstChild("MonitorScreen") :: BasePart?
			if monitor then
				monitor.Color = Color3.fromRGB(50, 220, 80)
				local gui = monitor:FindFirstChildOfClass("SurfaceGui")
				if gui then
					local label = gui:FindFirstChild("TerminalStatus") :: TextLabel?
					if label then
						label.TextColor3 = Color3.fromRGB(80, 255, 120)
						label.Text = "[RELAY ONLINE]\nSIGNAL SYNCD\nALL CLEAR"
					end
				end
			end

			ObjectiveService.AddProgress(1)

		-- 6. OPTIONAL SCRAP CACHE
		elseif promptName == "ScrapCachePrompt" then
			prompt.Enabled = false
			targetPart:Destroy()
			local amount = math.random(15, 25)
			local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
			PlayerDataService.AddScrap(player, amount)

			if notificationRemote then
				notificationRemote:FireClient(player, {
					MessageKey = "SCRAP_SALVAGED",
					MessageText = string.format("Salvaged +%d Scrap from emergency cache!", amount),
					Severity = "Success",
					Duration = 3,
				})
			end
		end
	end)
end

function ObjectiveService.StartMission(missionType: GameTypes.MissionType?): GameTypes.MissionState
	ObjectiveService.Reset()

	local selectedKey = (missionType :: string) or ObjectiveConfig.OrderList[1]
	local def = ObjectiveConfig.Objectives[selectedKey]

	activeMission = {
		Id = selectedKey,
		Type = def.Type :: GameTypes.MissionType,
		Title = def.Title,
		Description = def.Description,
		Progress = 0,
		TargetProgress = def.TargetCount,
		IsComplete = false,
	}

	log:Info("Initiating mission instance...", {
		Id = activeMission.Id,
		Type = activeMission.Type,
		Target = activeMission.TargetProgress,
	})

	ObjectiveService.SpawnObjectiveEntities(activeMission.Type)
	ObjectiveService.SpawnOptionalScrapCaches()

	ObjectiveService.Broadcast()
	return activeMission
end

function ObjectiveService.SpawnObjectiveEntities(missionType: GameTypes.MissionType)
	local offset = GameConfig.World.ActiveStationOffset
	local station = Workspace:WaitForChild("World"):WaitForChild("Runtime"):FindFirstChild("ActiveStation")
	if not station then return end

	local objectiveFolder = Instance.new("Folder")
	objectiveFolder.Name = "ObjectiveEntities"
	objectiveFolder.Parent = station
	table.insert(spawnedEntities, objectiveFolder)

	if missionType == "RestorePower" then
		-- Spawn 3 Fuse pickups
		local fuseLocations = {
			Vector3.new(45, 2, 10),
			Vector3.new(78, 2, 22),
			Vector3.new(38, 3, 52),
		}

		for i, loc in ipairs(fuseLocations) do
			local fusePart = createPart(
				objectiveFolder,
				"FuseItem_" .. tostring(i),
				Vector3.new(1.2, 0.6, 0.6),
				CFrame.new(offset + loc),
				Color3.fromRGB(70, 180, 255),
				Enum.Material.Neon
			)
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "PickUpFusePrompt"
			prompt.ActionText = "Collect Industrial Fuse"
			prompt.ObjectText = "Fuse (" .. tostring(i) .. "/3)"
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt.HoldDuration = 0.2
			prompt.Parent = fusePart
			table.insert(spawnedEntities, fusePart)
		end

	elseif missionType == "RecoverCargo" then
		-- Spawn 2 Cargo Containers in Cargo Storage
		local crateLocations = {
			Vector3.new(35, 2, 50),
			Vector3.new(48, 2, 62),
		}

		for i, loc in ipairs(crateLocations) do
			local crate = createPart(
				objectiveFolder,
				"CargoCrate_" .. tostring(i),
				Vector3.new(3.5, 3.5, 3.5),
				CFrame.new(offset + loc),
				Color3.fromRGB(210, 160, 50),
				Enum.Material.Wood
			)
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "PickUpCargoPrompt"
			prompt.ActionText = "Pick Up Cargo Crate"
			prompt.ObjectText = "Salvage Container (" .. tostring(i) .. "/2)"
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt.HoldDuration = 0.5
			prompt.Parent = crate
			table.insert(spawnedEntities, crate)
		end

	elseif missionType == "RepairSignal" then
		log:Info("RepairSignal consoles active in Control Room.")
	end
end

function ObjectiveService.SpawnOptionalScrapCaches()
	local offset = GameConfig.World.ActiveStationOffset
	local station = Workspace:WaitForChild("World"):WaitForChild("Runtime"):FindFirstChild("ActiveStation")
	if not station then return end

	local cacheFolder = Instance.new("Folder")
	cacheFolder.Name = "ScrapCaches"
	cacheFolder.Parent = station
	table.insert(spawnedEntities, cacheFolder)

	local cacheLocations = {
		Vector3.new(62, 1.5, -20),
		Vector3.new(55, 1.5, 68),
		Vector3.new(42, -2.5, -75),
		Vector3.new(98, 1.5, 28),
	}

	for i, loc in ipairs(cacheLocations) do
		local cachePart = createPart(
			cacheFolder,
			"ScrapCache_" .. tostring(i),
			Vector3.new(1.4, 1.4, 1.4),
			CFrame.new(offset + loc),
			Color3.fromRGB(130, 200, 140),
			Enum.Material.Metal
		)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ScrapCachePrompt"
		prompt.ActionText = "Scavenge Scrap"
		prompt.ObjectText = "Emergency Scrap Cache"
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0.3
		prompt.Parent = cachePart
		table.insert(spawnedEntities, cachePart)
	end
end

function ObjectiveService.GetActiveMission(): GameTypes.MissionState?
	return activeMission
end

function ObjectiveService.AddProgress(amount: number): boolean
	if not activeMission or activeMission.IsComplete then
		return false
	end

	activeMission.Progress = math.min(activeMission.TargetProgress, activeMission.Progress + amount)
	log:Info("Objective progress updated", {
		Progress = activeMission.Progress,
		Target = activeMission.TargetProgress,
	})

	if activeMission.Progress >= activeMission.TargetProgress then
		activeMission.IsComplete = true
		log:Info("Primary mission secured! Extraction authorized.", { Id = activeMission.Id })
		ObjectiveService.OnMissionCompleted:Fire(activeMission)

		if notificationRemote then
			notificationRemote:FireAllClients({
				MessageKey = "OBJECTIVE_COMPLETE",
				MessageText = "MISSION COMPLETE! Get to the extraction platform before departure!",
				Severity = "Success",
				Duration = 6,
			})
		end
	end

	ObjectiveService.Broadcast()
	return true
end

function ObjectiveService.Reset()
	activeMission = nil
	for _, entity in ipairs(spawnedEntities) do
		if entity and entity.Parent then
			entity:Destroy()
		end
	end
	table.clear(spawnedEntities)

	for userId, crate in pairs(carryingCargo) do
		if crate and crate.Parent then
			crate:Destroy()
		end
		carryingCargo[userId] = nil
	end

	if objectiveUpdatedRemote then
		objectiveUpdatedRemote:FireAllClients("", 0, 0, false)
	end
end

function ObjectiveService.Broadcast()
	if not activeMission or not objectiveUpdatedRemote then return end
	objectiveUpdatedRemote:FireAllClients(
		activeMission.Id,
		activeMission.Progress,
		activeMission.TargetProgress,
		activeMission.IsComplete
	)
end

return ObjectiveService
