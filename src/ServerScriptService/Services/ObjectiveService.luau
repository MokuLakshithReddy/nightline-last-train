--!strict
-- ObjectiveService.luau
-- Authoritative objective mechanics, physical entity spawning, artifact drops, unbanked scrap tracking, and strict state/phase validation

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local GameTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"):WaitForChild("GameTypes"))
local ObjectiveConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ObjectiveConfig"))
local RewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("RewardConfig"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Signal"))
local log = Logger.new("ObjectiveService")

local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local InteractionService = require(script.Parent:WaitForChild("InteractionService"))
local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))

local activeMission: GameTypes.MissionState? = nil
local objectiveUpdatedRemote: RemoteEvent? = nil
local notificationRemote: RemoteEvent? = nil

-- Runtime objective entity tracking
local spawnedEntities: { Instance } = {}
local carryingCargo: { [number]: Instance } = {}
local collectedArtifacts: { [number]: { string } } = {}
local unbankedScrap: { [number]: number } = {}

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
	log:Info("Initializing ObjectiveService with strict state and phase validation...")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	objectiveUpdatedRemote = remotes:WaitForChild("ObjectiveUpdated") :: RemoteEvent
	notificationRemote = remotes:WaitForChild("Notification") :: RemoteEvent

	ObjectiveService.BindInteractions()
end

function ObjectiveService.GetCollectedArtifacts(player: Player): { string }
	return collectedArtifacts[player.UserId] or {}
end

function ObjectiveService.GetUnbankedScrap(player: Player): number
	return unbankedScrap[player.UserId] or 0
end

function ObjectiveService.ClearUnbankedScrap(player: Player)
	unbankedScrap[player.UserId] = nil
end

function ObjectiveService.BindInteractions()
	InteractionService.OnPromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		local promptName = prompt.Name
		local targetPart = prompt.Parent :: BasePart?
		if not targetPart then return end

		-- Centralized Preconditions Check
		local character = player.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end

		-- Hub Prompts bypass station phase restrictions
		if promptName == "LockerPrompt" or promptName == "OpenUpgradeTerminalPrompt" then
			return
		end

		local RoundService = require(script.Parent:WaitForChild("RoundService"))
		local currentPhase = RoundService.GetCurrentState()
		local isStationPhase = (currentPhase == "EXPLORATION" or currentPhase == "EXTRACTION")

		-- All station objective interactions require active expedition phase and roster membership
		if not isStationPhase then
			log:Warn("Rejected objective interaction outside exploration/extraction phase", { Player = player.Name, Phase = currentPhase })
			return
		end

		if not RoundService.IsPlayerInRoster(player) then
			log:Warn("Rejected objective interaction from non-rostered player", { Player = player.Name })
			return
		end

		-- STRICT PHASE RESTRICTION (Issue 4):
		-- During EXTRACTION, station exploration and objective tasks are locked down.
		-- Only cargo container delivery to the train platform pallet is permitted.
		if currentPhase == "EXTRACTION" and promptName ~= "DeliverCargoPrompt" then
			log:Warn("Rejected station interaction during extraction phase", { Player = player.Name, Prompt = promptName })
			if notificationRemote then
				notificationRemote:FireClient(player, {
					MessageKey = "EXTRACTION_LOCKED",
					MessageText = "Station objectives locked! The train is preparing to depart — EXTRACT NOW!",
					Severity = "Warning",
					Duration = 3,
				})
			end
			return
		end

		-- 1. FUSE PICKUP INTERACTION (Strict mission type & phase check)
		if promptName == "PickUpFusePrompt" then
			if not activeMission or activeMission.Type ~= "RestorePower" or activeMission.IsComplete then
				return
			end

			-- Atomic consumption on server
			prompt.Enabled = false
			targetPart:Destroy()

			InventoryService.AddMissionItem(player, "Fuse", 1)
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
			if not activeMission or activeMission.Type ~= "RestorePower" or activeMission.IsComplete then
				return
			end

			if not InventoryService.HasMissionItem(player, "Fuse") then
				if notificationRemote then
					notificationRemote:FireClient(player, {
						MessageKey = "NO_FUSE",
						MessageText = "You need an Industrial Fuse in your inventory to activate this breaker!",
						Severity = "Warning",
						Duration = 3,
					})
				end
				return
			end

			-- Atomic consumption on server
			prompt.Enabled = false
			InventoryService.ConsumeMissionItem(player, "Fuse")

			local indicator = targetPart:FindFirstChild("IndicatorLight") :: BasePart?
			if indicator then
				indicator.Color = Color3.fromRGB(50, 240, 80)
			end

			ObjectiveService.AddProgress(1, player)

		-- 3. CARGO CRATE PICKUP
		elseif promptName == "PickUpCargoPrompt" then
			if not activeMission or activeMission.Type ~= "RecoverCargo" or activeMission.IsComplete then
				return
			end

			if carryingCargo[player.UserId] or InventoryService.HasMissionItem(player, "CargoContainer") then
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

			-- Atomic consumption on server
			prompt.Enabled = false
			targetPart:Destroy()

			local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
			if torso then
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

			if notificationRemote then
				notificationRemote:FireClient(player, {
					MessageKey = "CARGO_SECURED",
					MessageText = "Cargo secured! Deliver it to the train platform pallet.",
					Severity = "Info",
					Duration = 4,
				})
			end

		-- 4. CARGO DROP-OFF ON PLATFORM (Permitted in both Exploration and Extraction)
		elseif promptName == "DeliverCargoPrompt" then
			if not activeMission or activeMission.Type ~= "RecoverCargo" or activeMission.IsComplete then
				return
			end

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

			local deliveredCrate = createPart(
				targetPart,
				"DeliveredCrate",
				Vector3.new(2.4, 2.4, 2.4),
				targetPart.CFrame * CFrame.new(0, 1.5, 0),
				Color3.fromRGB(220, 180, 50),
				Enum.Material.Wood
			)
			table.insert(spawnedEntities, deliveredCrate)

			ObjectiveService.AddProgress(1, player)

		-- 5. SIGNAL RELAY TERMINAL REBOOT
		elseif promptName == "RebootSignalPrompt" then
			if not activeMission or activeMission.Type ~= "RepairSignal" or activeMission.IsComplete then
				return
			end

			-- Atomic consumption on server
			prompt.Enabled = false

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

			ObjectiveService.AddProgress(1, player)

		-- 6. OPTIONAL SCRAP CACHE (Transient Unbanked Scrap)
		elseif promptName == "ScrapCachePrompt" then
			prompt.Enabled = false
			targetPart:Destroy()

			local amount = math.random(15, 25)
			unbankedScrap[player.UserId] = (unbankedScrap[player.UserId] or 0) + amount

			log:Info("Player scavenged unbanked scrap", {
				Player = player.Name,
				ScrapFound = amount,
				TotalUnbanked = unbankedScrap[player.UserId],
			})

			if notificationRemote then
				notificationRemote:FireClient(player, {
					MessageKey = "SCRAP_SALVAGED",
					MessageText = string.format("Found +%d unbanked Scrap (Total: %d)! Extract on the train to secure it.", amount, unbankedScrap[player.UserId]),
					Severity = "Success",
					Duration = 4,
				})
			end

		-- 7. RARE ARTIFACT DISCOVERY
		elseif promptName == "PickUpArtifactPrompt" then
			local artifactId = prompt:GetAttribute("ArtifactId") :: string?
			if not artifactId then return end

			prompt.Enabled = false
			targetPart:Destroy()

			if not collectedArtifacts[player.UserId] then
				collectedArtifacts[player.UserId] = {}
			end
			table.insert(collectedArtifacts[player.UserId], artifactId)

			local artDef = RewardConfig.Artifacts[artifactId]
			local name = artDef and artDef.Name or artifactId

			if notificationRemote then
				notificationRemote:FireClient(player, {
					MessageKey = "ARTIFACT_FOUND",
					MessageText = string.format("FOUND ARTIFACT: %s! Extract safely to keep it.", name),
					Severity = "Success",
					Duration = 5,
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
		TargetProgress = def.TargetProgress,
		IsComplete = false,
	}

	log:Info("Initiating primary mission", {
		Id = activeMission.Id,
		Type = activeMission.Type,
		Target = activeMission.TargetProgress,
	})

	local station = Workspace:WaitForChild("World"):WaitForChild("Runtime"):FindFirstChild("ActiveStation")
	if station then
		ObjectiveService.SpawnObjectiveProps(station, activeMission.Type)
		ObjectiveService.SpawnOptionalScrapCaches()
		ObjectiveService.SpawnArtifacts()
	else
		log:Warn("Cannot spawn objective items: ActiveStation not found in Runtime.")
	end

	ObjectiveService.Broadcast()
	return activeMission
end

function ObjectiveService.SpawnObjectiveProps(station: Instance, missionType: GameTypes.MissionType)
	local offset = GameConfig.World.ActiveStationOffset
	local objectiveFolder = Instance.new("Folder")
	objectiveFolder.Name = "ObjectiveEntities"
	objectiveFolder.Parent = station
	table.insert(spawnedEntities, objectiveFolder)

	if missionType == "RestorePower" then
		local fuseLocations = {
			Vector3.new(45, 1.5, -45),
			Vector3.new(25, 1.5, 40),
			Vector3.new(85, 1.5, 10),
		}

		for i, loc in ipairs(fuseLocations) do
			local fuse = createPart(
				objectiveFolder,
				"IndustrialFuse_" .. tostring(i),
				Vector3.new(1.2, 0.6, 0.6),
				CFrame.new(offset + loc),
				Color3.fromRGB(80, 180, 255),
				Enum.Material.Neon
			)
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "PickUpFusePrompt"
			prompt.ActionText = "Pick Up Industrial Fuse"
			prompt.ObjectText = "Fuse (" .. tostring(i) .. "/3)"
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt.HoldDuration = 0.4
			prompt.Parent = fuse
			table.insert(spawnedEntities, fuse)
		end

	elseif missionType == "RecoverCargo" then
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

function ObjectiveService.SpawnArtifacts()
	local offset = GameConfig.World.ActiveStationOffset
	local station = Workspace:WaitForChild("World"):WaitForChild("Runtime"):FindFirstChild("ActiveStation")
	if not station then return end

	local artifactFolder = Instance.new("Folder")
	artifactFolder.Name = "Artifacts"
	artifactFolder.Parent = station
	table.insert(spawnedEntities, artifactFolder)

	local whistlePart = createPart(
		artifactFolder,
		"Artifact_SignalWhistle",
		Vector3.new(0.8, 0.4, 0.8),
		CFrame.new(offset + Vector3.new(42, -3.2, -80)),
		Color3.fromRGB(240, 240, 255),
		Enum.Material.Neon
	)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickUpArtifactPrompt"
	prompt:SetAttribute("ArtifactId", "SignalWhistle")
	prompt.ActionText = "Collect Silver Whistle"
	prompt.ObjectText = "Rare Relic: Silver Signal Whistle"
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0.5
	prompt.Parent = whistlePart
	table.insert(spawnedEntities, whistlePart)
end

function ObjectiveService.GetActiveMission(): GameTypes.MissionState?
	return activeMission
end

function ObjectiveService.AddProgress(amount: number, player: Player?): boolean
	if not activeMission or activeMission.IsComplete then
		return false
	end

	activeMission.Progress = math.min(activeMission.TargetProgress, activeMission.Progress + amount)
	log:Info("Objective progress updated", {
		Progress = activeMission.Progress,
		Target = activeMission.TargetProgress,
	})

	AnalyticsService.TrackObjectiveCompleted(player, activeMission.Type, activeMission.Progress, activeMission.TargetProgress)

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

	table.clear(collectedArtifacts)
	table.clear(unbankedScrap)

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