--!strict
-- CameraController.luau
-- Presentation and perspective camera controller

local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("CameraController")

local CameraController = {}

function CameraController.Init()
	log:Info("Initializing CameraController...")
end

return CameraController
