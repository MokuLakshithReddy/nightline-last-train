--!strict
-- AudioController.luau
-- Environmental and ambient audio orchestrator

local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("AudioController")

local AudioController = {}

function AudioController.Init()
	log:Info("Initializing AudioController...")
end

return AudioController

