--!strict
-- InteractionController.luau
-- Client-side presentation and feedback for ProximityPrompt interactions

local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("InteractionController")

local InteractionController = {}

function InteractionController.Init()
	log:Info("Initializing InteractionController...")
end

return InteractionController

