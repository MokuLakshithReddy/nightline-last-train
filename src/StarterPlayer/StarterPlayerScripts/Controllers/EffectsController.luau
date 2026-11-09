--!strict
-- EffectsController.luau
-- Environmental lighting, mist, and post-processing visual feedback

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("EffectsController")

local EffectsController = {}

function EffectsController.Init()
	log:Info("Initializing environmental lighting effects...")

	Lighting.ClockTime = 22
	Lighting.Brightness = 1
	Lighting.FogEnd = 240
	Lighting.FogStart = 30
	Lighting.FogColor = Color3.fromRGB(20, 22, 28)
	Lighting.Ambient = Color3.fromRGB(30, 32, 40)
	Lighting.OutdoorAmbient = Color3.fromRGB(25, 26, 32)
end

return EffectsController
