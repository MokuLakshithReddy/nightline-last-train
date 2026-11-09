--!strict
-- ObjectiveService.luau
-- Authoritative station objective lifecycle and progress management

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"):WaitForChild("GameTypes"))
local ObjectiveConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ObjectiveConfig"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Signal"))
local log = Logger.new("ObjectiveService")

local activeMission: GameTypes.MissionState? = nil
local objectiveUpdatedRemote: RemoteEvent? = nil

local ObjectiveService = {
	OnMissionCompleted = Signal.new(),
}

function ObjectiveService.Init()
	log:Info("Initializing ObjectiveService...")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	objectiveUpdatedRemote = remotes:WaitForChild("ObjectiveUpdated") :: RemoteEvent
end

function ObjectiveService.StartMission(missionType: GameTypes.MissionType?): GameTypes.MissionState
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

	log:Info("Started new objective", {
		Id = activeMission.Id,
		Title = activeMission.Title,
		Target = activeMission.TargetProgress,
	})

	ObjectiveService.Broadcast()
	return activeMission
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
		log:Info("Primary objective completed!", { Id = activeMission.Id })
		ObjectiveService.OnMissionCompleted:Fire(activeMission)
	end

	ObjectiveService.Broadcast()
	return true
end

function ObjectiveService.Reset()
	activeMission = nil
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
