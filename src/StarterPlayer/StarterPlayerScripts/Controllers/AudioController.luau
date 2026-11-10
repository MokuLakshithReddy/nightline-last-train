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

local function safePlay(sound: Sound?)
	if not sound then return end
	pcall(function()
		sound:Play()
	end)
end

local function setVolume(sound: Sound?, volume: number)
	if not sound then return end
	sound.Volume = math.clamp(volume, 0, 1)
end

function AudioController.Init()
	log:Info("Initializing dynamic audio controller...")

	-- Procedural audio sound assets using native Roblox audio library IDs
	trainRumbleSound = createSound("TrainRumble", "rbxassetid://9114221764", 0.45, true)
	stationAmbienceSound = createSound("StationAmbience", "rbxassetid://9114223170", 0.5, true)
	heartbeatSound = createSound("ProximityHeartbeat", "rbxassetid://9114224095", 0.0, true)
	alarmSound = createSound("ExtractionAlarm", "rbxassetid://9114222485", 0.7, false)

	safePlay(trainRumbleSound)

	-- State-based audio transitions
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local roundStateRemote = remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	roundStateRemote.OnClientEvent:Connect(function(state: string)
		if state == "WAITING" or state == "INTERMISSION" or state == "BOARDING" then
			setVolume(trainRumbleSound, 0.35)
			setVolume(stationAmbienceSound, 0.1)
			setVolume(heartbeatSound, 0)

		elseif state == "TRAVEL" then
			setVolume(trainRumbleSound, 0.8)
			setVolume(stationAmbienceSound, 0.0)

		elseif state == "EXPLORATION" then
			setVolume(trainRumbleSound, 0.05)
			setVolume(stationAmbienceSound, 0.65)
			safePlay(stationAmbienceSound)

		elseif state == "EXTRACTION" then
			safePlay(alarmSound)
			setVolume(stationAmbienceSound, 0.8)

		elseif state == "RETURN" or state == "RESULTS" then
			setVolume(heartbeatSound, 0)
			setVolume(trainRumbleSound, 0.6)
			setVolume(stationAmbienceSound, 0.1)
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
					safePlay(heartbeatSound)
					local intensity = math.clamp(1.0 - (dist / 60), 0.1, 1.0)
					heartbeatSound.Volume = intensity * 0.9 * AudioController.SFXVolume
					heartbeatSound.PlaybackSpeed = 1.0 + (intensity * 0.5)
				elseif heartbeatSound and heartbeatSound.Volume > 0 then
					setVolume(heartbeatSound, 0)
				end
			elseif heartbeatSound and heartbeatSound.Volume > 0 then
				setVolume(heartbeatSound, 0)
			end
		end
	end)
end

return AudioController
