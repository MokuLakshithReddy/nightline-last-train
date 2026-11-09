--!strict
-- RoundService.luau
-- Authoritative round lifecycle and finite state machine for NIGHTLINE: LAST TRAIN

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local GameTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"):WaitForChild("GameTypes"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Signal"))
local log = Logger.new("RoundService")

local StationService = require(script.Parent:WaitForChild("StationService"))
local ObjectiveService = require(script.Parent:WaitForChild("ObjectiveService"))
local RewardService = require(script.Parent:WaitForChild("RewardService"))
local MonsterService = require(script.Parent:WaitForChild("MonsterService"))

-- Remotes
local roundStateRemote: RemoteEvent? = nil
local notificationRemote: RemoteEvent? = nil

local currentState: GameTypes.RoundState = "WAITING"
local phaseEndsAt: number = 0
local roundCounter: number = 0
local currentRoundId: string = ""
local currentStationId: string = GameConfig.Round.DefaultStationId

-- Crew roster for active expedition
local activeRoster: { [number]: Player } = {}
local extractedPlayers: { [number]: boolean } = {}
local eliminatedPlayers: { [number]: boolean } = {}

local isLoopRunning = false

local RoundService = {
	OnStateChanged = Signal.new(),
}

local function broadcastNotification(message: string, severity: "Info" | "Warning" | "Alert" | "Success")
	if notificationRemote then
		local payload: GameTypes.NotificationPayload = {
			MessageKey = "ROUND_ALERT",
			MessageText = message,
			Severity = severity,
			Duration = 4,
		}
		notificationRemote:FireAllClients(payload)
	end
end

local function broadcastState()
	local duration = math.max(0, math.floor(phaseEndsAt - os.clock()))
	log:Info("State transition", {
		State = currentState,
		EndsAt = math.floor(phaseEndsAt),
		Duration = duration,
	})

	if roundStateRemote then
		roundStateRemote:FireAllClients(
			currentState,
			os.clock(),
			phaseEndsAt,
			currentStationId
		)
	end

	RoundService.OnStateChanged:Fire(currentState, phaseEndsAt)
end

local function teleportPlayer(player: Player, destination: Vector3)
	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.CFrame = CFrame.new(destination)
		end
	end
end

local function teleportToHub(player: Player)
	local hubSpawns = Workspace:FindFirstChild("World")
		and Workspace.World:FindFirstChild("Hub")
		and Workspace.World.Hub:FindFirstChild("Spawns")
	
	if hubSpawns and #hubSpawns:GetChildren() > 0 then
		local spawns = hubSpawns:GetChildren()
		local chosen = spawns[math.random(1, #spawns)] :: SpawnLocation
		teleportPlayer(player, chosen.Position + Vector3.new(0, 3, 0))
	else
		teleportPlayer(player, GameConfig.World.HubCenter + GameConfig.World.HubSpawnOffset)
	end
end

function RoundService.Init()
	log:Info("Initializing RoundService...")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	roundStateRemote = remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
	notificationRemote = remotes:WaitForChild("Notification") :: RemoteEvent

	Players.PlayerAdded:Connect(function(player)
		if roundStateRemote then
			roundStateRemote:FireClient(player, currentState, os.clock(), phaseEndsAt, currentStationId)
		end

		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			teleportToHub(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		activeRoster[player.UserId] = nil
		extractedPlayers[player.UserId] = nil
		eliminatedPlayers[player.UserId] = nil

		if (currentState == "EXPLORATION" or currentState == "EXTRACTION") and next(activeRoster) == nil then
			log:Warn("All active expedition players left; aborting round safely")
			RoundService.TransitionTo("RESULTS")
		end
	end)
end

function RoundService.GetCurrentState(): GameTypes.RoundState
	return currentState
end

function RoundService.GetTimeRemaining(): number
	return math.max(0, math.floor(phaseEndsAt - os.clock()))
end

function RoundService.GetActiveRoster(): { [number]: Player }
	return activeRoster
end

function RoundService.IsPlayerInRoster(player: Player): boolean
	return activeRoster[player.UserId] ~= nil
end

function RoundService.StartGameLoop()
	if isLoopRunning then return end
	isLoopRunning = true
	log:Info("Starting authoritative game loop...")

	task.spawn(function()
		while true do
			local playerCount = #Players:GetPlayers()

			if currentState == "WAITING" then
				if playerCount >= GameConfig.Server.MinPlayersToStart then
					RoundService.TransitionTo("INTERMISSION")
				else
					task.wait(2)
				end

			elseif currentState == "INTERMISSION" then
				RoundService.WaitForPhase()
				if #Players:GetPlayers() >= GameConfig.Server.MinPlayersToStart then
					RoundService.TransitionTo("BOARDING")
				else
					RoundService.TransitionTo("WAITING")
				end

			elseif currentState == "BOARDING" then
				RoundService.WaitForPhase()
				table.clear(activeRoster)
				table.clear(extractedPlayers)
				table.clear(eliminatedPlayers)
				for _, p in ipairs(Players:GetPlayers()) do
					activeRoster[p.UserId] = p
				end

				if next(activeRoster) ~= nil then
					RoundService.TransitionTo("TRAVEL")
				else
					RoundService.TransitionTo("WAITING")
				end

			elseif currentState == "TRAVEL" then
				RoundService.WaitForPhase()
				RoundService.TransitionTo("EXPLORATION")

			elseif currentState == "EXPLORATION" then
				RoundService.WaitForPhase()
				RoundService.TransitionTo("EXTRACTION")

			elseif currentState == "EXTRACTION" then
				RoundService.WaitForPhase()
				RoundService.TransitionTo("RETURN")

			elseif currentState == "RETURN" then
				RoundService.WaitForPhase()
				RoundService.TransitionTo("RESULTS")

			elseif currentState == "RESULTS" then
				RoundService.WaitForPhase()
				RoundService.CleanupRound()
				RoundService.TransitionTo("WAITING")
			end
		end
	end)
end

function RoundService.WaitForPhase()
	while os.clock() < phaseEndsAt do
		task.wait(0.5)
	end
end

function RoundService.TransitionTo(newState: GameTypes.RoundState)
	currentState = newState
	local duration = GameConfig.Round.Durations[newState] or 10
	phaseEndsAt = os.clock() + duration

	if newState == "WAITING" then
		broadcastNotification("Waiting for players to board the train...", "Info")

	elseif newState == "INTERMISSION" then
		broadcastNotification("Expedition countdown starting. Prepare to board!", "Info")

	elseif newState == "BOARDING" then
		roundCounter += 1
		currentRoundId = "Round_" .. tostring(os.time()) .. "_" .. tostring(roundCounter)
		broadcastNotification("BOARDING: Finalize equipment loadout inside the carriage.", "Warning")

	elseif newState == "TRAVEL" then
		broadcastNotification("Train departing from terminal! In transit to Station 001...", "Alert")

	elseif newState == "EXPLORATION" then
		-- 1. Load Station 001 level geometry
		StationService.LoadStation(currentStationId)

		-- 2. Select mission template from the 3 templates
		local missions: { GameTypes.MissionType } = { "RestorePower", "RecoverCargo", "RepairSignal" }
		local missionIndex = ((roundCounter - 1) % #missions) + 1
		local selectedMission = missions[missionIndex]
		local activeMission = ObjectiveService.StartMission(selectedMission)

		-- 3. Standby monster
		MonsterService.SpawnMonster()

		-- 4. Deploy players to station arrival platform
		local spawnPos = StationService.GetSpawnPosition()
		for _, player in pairs(activeRoster) do
			teleportPlayer(player, spawnPos)
		end

		broadcastNotification(string.format("Arrived at The Forgotten Terminal! Objective: %s", activeMission.Title), "Warning")

	elseif newState == "EXTRACTION" then
		broadcastNotification("WARNING: Last train departure in 60s! Get to the extraction gate!", "Alert")

	elseif newState == "RETURN" then
		MonsterService.DespawnMonster()
		-- Determine extraction status
		for userId, player in pairs(activeRoster) do
			if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
				local pos = (player.Character.HumanoidRootPart :: BasePart).Position
				if StationService.IsInsideExtractionZone(pos) then
					extractedPlayers[userId] = true
				end
			end
			teleportToHub(player)
		end
		broadcastNotification("Train departing station! Returning to safe haven...", "Success")

	elseif newState == "RESULTS" then
		local mission = ObjectiveService.GetActiveMission()
		local missionDone = mission ~= nil and mission.IsComplete

		for userId, player in pairs(activeRoster) do
			local didExtract = extractedPlayers[userId] == true
			RewardService.AwardExpeditionRewards(currentRoundId, player, missionDone, didExtract, 0)
		end

		if missionDone then
			broadcastNotification("EXPEDITION COMPLETE: Mission targets secured!", "Success")
		else
			broadcastNotification("EXPEDITION OVER: Survivors retrieved.", "Info")
		end
	end

	broadcastState()
end

function RoundService.CleanupRound()
	log:Info("Performing comprehensive round cleanup...")
	StationService.UnloadStation()
	ObjectiveService.Reset()
	table.clear(activeRoster)
	table.clear(extractedPlayers)
	table.clear(eliminatedPlayers)
	for _, player in ipairs(Players:GetPlayers()) do
		teleportToHub(player)
	end
end

return RoundService
