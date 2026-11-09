--!strict
-- InteractionService.luau
-- Authoritative router for contextual ProximityPrompt interactions

local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Signal"))
local log = Logger.new("InteractionService")

-- Prompt-indexed cooldown table with weak keys to prevent memory leaks when prompts are destroyed
local promptCooldowns: { [ProximityPrompt]: { [number]: number } } = setmetatable({}, { __mode = "k" }) :: any

local InteractionService = {
	OnPromptTriggered = Signal.new(),
}

function InteractionService.Init()
	log:Info("Initializing InteractionService...")

	Players.PlayerRemoving:Connect(function(player: Player)
		for _, playerRecord in pairs(promptCooldowns) do
			playerRecord[player.UserId] = nil
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		local promptParent = prompt.Parent
		if not promptParent or not promptParent:IsA("BasePart") then return end

		-- 1. Rate-limit validation
		if not SecurityService.CheckRateLimit(player, 1) then
			return
		end

		-- 2. Range validation
		if not SecurityService.ValidateDistance(player, promptParent.Position, prompt.MaxActivationDistance + 4) then
			return
		end

		-- 3. Cooldown check per prompt using Instance key (no GetDebugId)
		local playerRecord = promptCooldowns[prompt]
		if not playerRecord then
			playerRecord = {}
			promptCooldowns[prompt] = playerRecord
		end

		local now = os.clock()
		local lastInteraction = playerRecord[player.UserId]
		if lastInteraction and (now - lastInteraction) < 0.5 then
			return
		end
		playerRecord[player.UserId] = now

		log:Debug("Validated prompt interaction", {
			Player = player.Name,
			Prompt = prompt.Name,
			Action = prompt.ActionText,
		})

		InteractionService.OnPromptTriggered:Fire(prompt, player)
	end)
end

return InteractionService

