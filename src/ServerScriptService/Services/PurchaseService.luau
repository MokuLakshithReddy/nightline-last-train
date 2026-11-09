--!strict
-- PurchaseService.luau
-- Server receipt validation stub (Milestone 6/7 preparation)

local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("PurchaseService")

local PurchaseService = {}

function PurchaseService.Init()
	log:Info("Initializing PurchaseService (monetization stub)...")
end

return PurchaseService
