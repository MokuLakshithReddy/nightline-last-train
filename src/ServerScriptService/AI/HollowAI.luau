--!strict
-- HollowAI.luau
-- Signature threat logic and state controller (Milestone 3 preparation)

local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("HollowAI")

local HollowAI = {}

function HollowAI.Init()
	log:Info("HollowAI initialized and standing by.")
end

return HollowAI
