--!strict
-- AudioController.luau
-- Environmental and ambient audio orchestrator for NIGHTLINE: LAST TRAIN

local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("AudioController")

local localPlayer = Players.LocalPlayer

local AudioController = {
	MasterVolume = 1.0,
	MusicVolume = 0.8,
	SFXVolume = 1.0,
}

-- Sounds
local trainRumbleSound: Sound? = nil
local stationAmbienceSound: Sound? = nil
local heartbeatSound: Sound? = nil
local alarmSound: Sound? = nil

local function createSound(name: string, soundId: string, volume: number, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = volume
	sound.Looped = looped
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.Parent = SoundService
	return sound
end

function AudioController.Init()
	log:Info("Initializing dynamic audio controller...")

	-- Procedural audio sound assets using native Roblox audio library IDs
	trainRumbleSound = createSound("TrainRumble", "rbxassetid://9114221764", 0.45, true)
	stationAmbienceSound = createSound("StationAmbience", "rbxassetid://9114223170", 0.5, true)
	heartbeatSound = createSound("ProximityHeartbeat", "rbxassetid://9114224095", 0.0, true)
	alarmSound = createSound("ExtractionAlarm", "rbxassetid://9114222485", 0.7, false)

	trainRumbleSound:Play()

	-- State-based audio transitions
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local roundStateRemote = remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	roundStateRemote.OnClientEvent:Connect(function(state: string)
		if state == "WAITING" or state == "INTERMISSION" or state == "BOARDING" then
			if trainRumbleSound then trainRumbleSound.Volume = 0.35 end
			if stationAmbienceSound then stationAmbienceSound.Volume = 0.1 end
			if heartbeatSound then heartbeatSound.Volume = 0 end

		elseif state == "TRAVEL" then
			if trainRumbleSound then trainRumbleSound.Volume = 0.8 end
			if stationAmbienceSound then stationAmbienceSound.Volume = 0.0 end

		elseif state == "EXPLORATION" then
			if trainRumbleSound then trainRumbleSound.Volume = 0.05 end
			if stationAmbienceSound then
				stationAmbienceSound.Volume = 0.65
				stationAmbienceSound:Play()
			end

		elseif state == "EXTRACTION" then
			if alarmSound then alarmSound:Play() end
			if stationAmbienceSound then stationAmbienceSound.Volume = 0.8 end

		elseif state == "RETURN" or state == "RESULTS" then
			if heartbeatSound then heartbeatSound.Volume = 0 end
			if trainRumbleSound then trainRumbleSound.Volume = 0.6 end
			if stationAmbienceSound then stationAmbienceSound.Volume = 0.1 end
		end
	end)

	-- Heartbeat proximity listener (The Hollow distance check)
	task.spawn(function()
		while true do
			task.wait(0.3)
			local char = localPlayer.Character
			local monster = Workspace:FindFirstChild("World")
				and Workspace.World:FindFirstChild("Runtime")
				and Workspace.World.Runtime:FindFirstChild("TheHollow") :: Model?

			if char and char:FindFirstChild("HumanoidRootPart") and monster and monster:FindFirstChild("HumanoidRootPart") then
				local playerPos = (char.HumanoidRootPart :: BasePart).Position
				local monsterPos = (monster.HumanoidRootPart :: BasePart).Position
				local dist = (playerPos - monsterPos).Magnitude

				if dist < 60 and heartbeatSound then
					if not heartbeatSound.IsPlaying then heartbeatSound:Play() end
					local intensity = math.clamp(1.0 - (dist / 60), 0.1, 1.0)
					heartbeatSound.Volume = intensity * 0.9 * AudioController.SFXVolume
					heartbeatSound.PlaybackSpeed = 1.0 + (intensity * 0.5)
				elseif heartbeatSound and heartbeatSound.Volume > 0 then
					heartbeatSound.Volume = 0
				end
			elseif heartbeatSound and heartbeatSound.Volume > 0 then
				heartbeatSound.Volume = 0
			end
		end
	end)
end

return AudioController
