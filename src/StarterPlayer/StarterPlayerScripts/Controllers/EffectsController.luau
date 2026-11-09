--!strict
-- EffectsController.luau
-- Environmental lighting, atmospheric fog, and camera feedback for NIGHTLINE: LAST TRAIN

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("EffectsController")

local EffectsController = {}

local currentCamera = Workspace.CurrentCamera

function EffectsController.Init()
	log:Info("Initializing dynamic effects and lighting controller...")

	EffectsController.ApplyHubLighting()

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local roundStateRemote = remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	roundStateRemote.OnClientEvent:Connect(function(state: string)
		if state == "WAITING" or state == "INTERMISSION" or state == "BOARDING" or state == "RETURN" or state == "RESULTS" then
			EffectsController.ApplyHubLighting()

		elseif state == "TRAVEL" then
			EffectsController.ShakeCamera(1.5, 0.4)

		elseif state == "EXPLORATION" then
			EffectsController.ApplyStationLighting()

		elseif state == "EXTRACTION" then
			EffectsController.ApplyExtractionLighting()
			EffectsController.ShakeCamera(0.8, 0.3)
		end
	end)
end

function EffectsController.ApplyHubLighting()
	local tweenInfo = TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(Lighting, tweenInfo, {
		ClockTime = 22,
		Brightness = 1.0,
		FogEnd = 300,
		FogStart = 40,
		FogColor = Color3.fromRGB(24, 26, 32),
		Ambient = Color3.fromRGB(45, 45, 55),
		OutdoorAmbient = Color3.fromRGB(30, 32, 40),
	}):Play()
end

function EffectsController.ApplyStationLighting()
	local tweenInfo = TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(Lighting, tweenInfo, {
		ClockTime = 0,
		Brightness = 0.4,
		FogEnd = 160,
		FogStart = 15,
		FogColor = Color3.fromRGB(12, 14, 18),
		Ambient = Color3.fromRGB(18, 20, 26),
		OutdoorAmbient = Color3.fromRGB(15, 16, 20),
	}):Play()
end

function EffectsController.ApplyExtractionLighting()
	local tweenInfo = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(Lighting, tweenInfo, {
		Brightness = 0.5,
		FogEnd = 140,
		FogStart = 10,
		FogColor = Color3.fromRGB(28, 14, 14),
		Ambient = Color3.fromRGB(25, 18, 20),
	}):Play()
end

function EffectsController.ShakeCamera(duration: number, intensity: number)
	task.spawn(function()
		local startTime = os.clock()
		while os.clock() - startTime < duration do
			if currentCamera then
				local offsetX = (math.random() - 0.5) * intensity
				local offsetY = (math.random() - 0.5) * intensity
				currentCamera.CFrame = currentCamera.CFrame * CFrame.Angles(math.rad(offsetX), math.rad(offsetY), 0)
			end
			task.wait(0.03)
		end
	end)
end

return EffectsController
