--!strict
-- MonsterService.luau
-- Authoritative monster lifecycle coordinator (Milestone 3 preparation)

local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("MonsterService")

local MonsterService = {}

function MonsterService.Init()
	log:Info("Initializing MonsterService...")
end

function MonsterService.SpawnMonster()
	log:Info("MonsterService: Standing by for Station 001 deployment (Milestone 3).")
end

function MonsterService.DespawnMonster()
	log:Info("MonsterService: Cleaned monster entities.")
end

return MonsterService
