--!strict
-- InteractionService.luau
-- Authoritative router for contextual ProximityPrompt interactions

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Signal"))
local log = Logger.new("InteractionService")

local interactionCooldowns: { [string]: number } = {}

local InteractionService = {
	OnPromptTriggered = Signal.new(),
}

function InteractionService.Init()
	log:Info("Initializing InteractionService...")

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

		-- 3. Cooldown check per prompt
		local cooldownKey = tostring(prompt:GetDebugId(1)) .. "_" .. tostring(player.UserId)
		local now = os.clock()
		if interactionCooldowns[cooldownKey] and (now - interactionCooldowns[cooldownKey]) < 0.5 then
			return
		end
		interactionCooldowns[cooldownKey] = now

		log:Debug("Validated prompt interaction", {
			Player = player.Name,
			Prompt = prompt.Name,
			Action = prompt.ActionText,
		})

		InteractionService.OnPromptTriggered:Fire(prompt, player)
	end)
end

return InteractionService

