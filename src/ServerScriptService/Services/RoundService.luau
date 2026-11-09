--!strict
-- RoundService.luau
-- Authoritative round lifecycle and finite state machine for NIGHTLINE: LAST TRAIN

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local StationConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("StationConfig"))
local GameTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"):WaitForChild("GameTypes"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Signal"))
local log = Logger.new("RoundService")

local StationService = require(script.Parent:WaitForChild("StationService"))
local ObjectiveService = require(script.Parent:WaitForChild("ObjectiveService"))
local RewardService = require(script.Parent:WaitForChild("RewardService"))
local MonsterService = require(script.Parent:WaitForChild("MonsterService"))
local MovementService = require(script.Parent:WaitForChild("MovementService"))
local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))

-- Remotes
local roundStateRemote: RemoteEvent? = nil
local notificationRemote: RemoteEvent? = nil
local destinationVotesRemote: RemoteEvent? = nil

local currentState: GameTypes.RoundState = "WAITING"
local phaseEndsAt: number = 0
local roundCounter: number = 0
local currentRoundId: string = ""
local currentStationId: string = GameConfig.Round.DefaultStationId
local stateGeneration: number = 0

-- Destination voting state
local playerVotes: { [number]: string } = {}

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
			MovementService.RegisterTeleport(player, 2.5)
			root.CFrame = CFrame.new(destination)
			root.AssemblyLinearVelocity = Vector3.zero
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
	destinationVotesRemote = remotes:FindFirstChild("DestinationVotesUpdated") :: RemoteEvent?

	Players.PlayerAdded:Connect(function(player)
		if roundStateRemote then
			roundStateRemote:FireClient(player, currentState, os.clock(), phaseEndsAt, currentStationId)
		end

		if destinationVotesRemote then
			destinationVotesRemote:FireClient(player, RoundService.GetDestinationVotesSummary())
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

		if playerVotes[player.UserId] then
			playerVotes[player.UserId] = nil
			if RoundService.IsVotingOpen() and destinationVotesRemote then
				destinationVotesRemote:FireAllClients(RoundService.GetDestinationVotesSummary())
			end
		end

		if (currentState == "EXPLORATION" or currentState == "EXTRACTION") and next(activeRoster) == nil then
			log:Warn("All active expedition players left; aborting round safely")
			RoundService.TransitionTo("RESULTS")
		end
	end)
end

function RoundService.IsVotingOpen(): boolean
	return currentState == "WAITING" or currentState == "INTERMISSION" or currentState == "BOARDING"
end

function RoundService.GetDestinationVotesSummary(): { [string]: any }
	local tally: { [string]: number } = {}
	local stationOptions: { [string]: string } = {}

	for id, def in pairs(StationConfig.Stations) do
		tally[id] = 0
		stationOptions[id] = def.Name
	end

	local totalVotes = 0
	for userId, stationId in pairs(playerVotes) do
		if Players:GetPlayerByUserId(userId) and tally[stationId] ~= nil then
			tally[stationId] += 1
			totalVotes += 1
		end
	end

	local leadingStation = StationConfig.DefaultStation
	local maxVotes = -1
	for id, count in pairs(tally) do
		if count > maxVotes then
			maxVotes = count
			leadingStation = id
		end
	end

	return {
		Tally = tally,
		TotalVotes = totalVotes,
		LeadingStation = leadingStation,
		StationOptions = stationOptions,
		VotingOpen = RoundService.IsVotingOpen(),
	}
end

function RoundService.RecordDestinationVote(player: Player, stationId: string): (boolean, string?)
	if not RoundService.IsVotingOpen() then
		return false, "Destination voting is closed once train preparation ends"
	end

	if not StationConfig.Stations[stationId] then
		return false, "Invalid destination station ID"
	end

	playerVotes[player.UserId] = stationId
	log:Info("Player cast destination vote", {
		Player = player.Name,
		UserId = player.UserId,
		Destination = stationId,
	})

	if destinationVotesRemote then
		destinationVotesRemote:FireAllClients(RoundService.GetDestinationVotesSummary())
	end

	return true, nil
end

function RoundService.TallyDestinationVotes(): string
	local tally: { [string]: number } = {}
	local stationKeys: { string } = {}

	for id in pairs(StationConfig.Stations) do
		tally[id] = 0
		table.insert(stationKeys, id)
	end
	table.sort(stationKeys)

	local totalVotes = 0
	for userId, stationId in pairs(playerVotes) do
		if Players:GetPlayerByUserId(userId) and tally[stationId] ~= nil then
			tally[stationId] += 1
			totalVotes += 1
		end
	end

	local winner = StationConfig.DefaultStation
	local highestCount = 0

	if totalVotes == 0 then
		winner = StationConfig.DefaultStation
		log:Info("No destination votes cast; defaulting to standard line", { StationId = winner })
	else
		-- Deterministic tie-breaker:
		-- If default station is tied for highest count, prefer default station;
		-- Otherwise select lexicographically first station among tied leaders.
		for _, id in ipairs(stationKeys) do
			local count = tally[id]
			if count > highestCount then
				highestCount = count
				winner = id
			elseif count == highestCount and highestCount > 0 then
				if id == StationConfig.DefaultStation then
					winner = id
				end
			end
		end
		log:Info("Destination vote tallied", {
			Winner = winner,
			Votes = highestCount,
			TotalCast = totalVotes,
		})
	end

	currentStationId = winner

	local def = StationConfig.Stations[currentStationId]
	local stationName = def and def.Name or currentStationId
	if totalVotes > 0 then
		broadcastNotification("Destination confirmed by crew vote: " .. stationName .. " (" .. tostring(highestCount) .. " votes)!", "Success")
	else
		broadcastNotification("Standard destination scheduled: " .. stationName .. ".", "Info")
	end

	if destinationVotesRemote then
		destinationVotesRemote:FireAllClients(RoundService.GetDestinationVotesSummary())
	end

	return currentStationId
end

function RoundService.GetCurrentStationId(): string
	return currentStationId
end

function RoundService.GetCurrentRoundId(): string
	return currentRoundId
end

function RoundService.GetDestinationVotes(): { [number]: string }
	local copy = {}
	for k, v in pairs(playerVotes) do
		copy[k] = v
	end
	return copy
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
			local success, loopErr = pcall(function()
				local playerCount = #Players:GetPlayers()

				if currentState == "WAITING" then
					if playerCount >= GameConfig.Server.MinPlayersToStart then
						RoundService.TransitionTo("INTERMISSION")
					else
						task.wait(2)
					end

				elseif currentState == "INTERMISSION" then
					if not RoundService.WaitForPhase("INTERMISSION") then return end
					if #Players:GetPlayers() >= GameConfig.Server.MinPlayersToStart then
						RoundService.TransitionTo("BOARDING")
					else
						RoundService.TransitionTo("WAITING")
					end

				elseif currentState == "BOARDING" then
					if not RoundService.WaitForPhase("BOARDING") then return end
					table.clear(activeRoster)
					table.clear(extractedPlayers)
					table.clear(eliminatedPlayers)
					for _, p in ipairs(Players:GetPlayers()) do
						activeRoster[p.UserId] = p
					end

					if next(activeRoster) ~= nil then
						currentStationId = RoundService.TallyDestinationVotes()
						RoundService.TransitionTo("TRAVEL")
					else
						RoundService.TransitionTo("WAITING")
					end

				elseif currentState == "TRAVEL" then
					if not RoundService.WaitForPhase("TRAVEL") then return end
					RoundService.TransitionTo("EXPLORATION")

				elseif currentState == "EXPLORATION" then
					local stationOk, stationErr = pcall(function()
						StationService.LoadStation(currentStationId)
					end)
					if not stationOk then
						log:Error("Failed to load station in EXPLORATION: " .. tostring(stationErr))
					end

					local rosterCount = 0
					for _ in pairs(activeRoster) do rosterCount += 1 end
					AnalyticsService.TrackExpeditionStart(currentRoundId, currentStationId, rosterCount)

					local missions: { GameTypes.MissionType } = { "RestorePower", "RecoverCargo", "RepairSignal" }
					local missionIndex = ((roundCounter - 1) % #missions) + 1
					local selectedMission = missions[missionIndex]
					local activeMission = nil
					local missionOk, missionErr = pcall(function()
						activeMission = ObjectiveService.StartMission(selectedMission)
					end)
					if not missionOk then
						log:Error("Failed to start mission in EXPLORATION: " .. tostring(missionErr))
					end

					-- Protected monster spawn call to prevent NPC errors from breaking the round loop
					local monsterOk, monsterErr = pcall(function()
						MonsterService.SpawnMonster()
					end)
					if not monsterOk then
						log:Error("Failed to spawn monster in EXPLORATION: " .. tostring(monsterErr))
					end

					local spawnPos = StationService.GetSpawnPosition()
					for _, player in pairs(activeRoster) do
						pcall(function()
							teleportPlayer(player, spawnPos)
						end)
					end

					local missionTitle = if activeMission and activeMission.Title then activeMission.Title else "Expedition Active"
					broadcastNotification(string.format("Arrived at The Forgotten Terminal! Objective: %s", missionTitle), "Warning")
					if not RoundService.WaitForPhase("EXPLORATION") then return end
					RoundService.TransitionTo("EXTRACTION")

				elseif currentState == "EXTRACTION" then
					if not RoundService.WaitForPhase("EXTRACTION") then return end
					RoundService.TransitionTo("RETURN")

				elseif currentState == "RETURN" then
					local despawnOk, despawnErr = pcall(function()
						MonsterService.DespawnMonster()
					end)
					if not despawnOk then
						log:Error("Failed to despawn monster in RETURN: " .. tostring(despawnErr))
					end

					for userId, player in pairs(activeRoster) do
						pcall(function()
							if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
								local pos = (player.Character.HumanoidRootPart :: BasePart).Position
								if StationService.IsInsideExtractionZone(pos) then
									extractedPlayers[userId] = true
									local unbanked = ObjectiveService.GetUnbankedScrap(player)
									AnalyticsService.TrackPlayerExtraction(player, currentRoundId, unbanked)
								end
							end
							teleportToHub(player)
						end)
					end
					broadcastNotification("Train departing station! Returning to safe haven...", "Success")
					if not RoundService.WaitForPhase("RETURN") then return end
					RoundService.TransitionTo("RESULTS")

				elseif currentState == "RESULTS" then
					local mission = ObjectiveService.GetActiveMission()
					local missionDone = mission ~= nil and mission.IsComplete

					local survivedCount = 0
					for _ in pairs(extractedPlayers) do survivedCount += 1 end
					local totalRoster = 0
					for _ in pairs(activeRoster) do totalRoster += 1 end
					AnalyticsService.TrackExpeditionEnd(currentRoundId, currentStationId, survivedCount, totalRoster, 0)

					for userId, player in pairs(activeRoster) do
						pcall(function()
							local didExtract = extractedPlayers[userId] == true
							local artifacts = ObjectiveService.GetCollectedArtifacts(player)
							local unbanked = ObjectiveService.GetUnbankedScrap(player)

							RewardService.AwardExpeditionRewards(
								currentRoundId,
								player,
								missionDone,
								didExtract,
								unbanked,
								artifacts
							)
						end)
					end

					if missionDone then
						broadcastNotification("EXPEDITION COMPLETE: Mission targets secured!", "Success")
					else
						broadcastNotification("EXPEDITION OVER: Returning to Hub.", "Info")
					end

					if not RoundService.WaitForPhase("RESULTS") then return end
					RoundService.CleanupRound()
					RoundService.TransitionTo("WAITING")
				end
			end)

			if not success then
				log:Error("Critical error caught in round-loop coroutine (" .. tostring(currentState) .. "): " .. tostring(loopErr))
				task.wait(1)
			end
		end
	end)
end

function RoundService.WaitForPhase(expectedPhase: GameTypes.RoundState?): boolean
	local targetPhase = expectedPhase or currentState
	local targetGen = stateGeneration

	while os.clock() < phaseEndsAt do
		if currentState ~= targetPhase or stateGeneration ~= targetGen then
			log:Info("Phase wait interrupted: state changed from " .. tostring(targetPhase) .. " to " .. tostring(currentState))
			return false
		end
		task.wait(0.2)
	end

	-- Final validation after wait interval expires
	if currentState ~= targetPhase or stateGeneration ~= targetGen then
		log:Info("Phase wait completed but state was superseded", { Expected = targetPhase, Actual = currentState })
		return false
	end

	return true
end

function RoundService.TransitionTo(newState: GameTypes.RoundState)
	stateGeneration += 1
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
		local def = StationConfig.Stations[currentStationId]
		local stationName = def and def.Name or currentStationId
		broadcastNotification("Train departing from terminal! In transit to " .. stationName .. "...", "Alert")

	elseif newState == "EXTRACTION" then
		broadcastNotification("WARNING: Last train departure in 60s! Get to the extraction gate!", "Alert")
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
	table.clear(playerVotes)
	currentStationId = GameConfig.Round.DefaultStationId
	if destinationVotesRemote then
		destinationVotesRemote:FireAllClients(RoundService.GetDestinationVotesSummary())
	end
	for _, player in ipairs(Players:GetPlayers()) do
		teleportToHub(player)
	end
end

return RoundService
