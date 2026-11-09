--!strict
-- MovementService.luau
-- Authoritative server-side movement validation, sprint state ownership, and anti-speed exploit enforcement

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("MovementService")

local playerSprinting: { [number]: boolean } = {}
local lastPositions: { [number]: Vector3 } = {}
local lastTimes: { [number]: number } = {}
local teleportGraceUntil: { [number]: number } = {}

local MovementService = {}

function MovementService.Init()
	log:Info("Initializing MovementService with authoritative sprint and anti-cheat validation...")

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local requestSprint = remotes:FindFirstChild("RequestSprint") :: RemoteEvent?
	if not requestSprint then
		requestSprint = Instance.new("RemoteEvent")
		requestSprint.Name = "RequestSprint"
		requestSprint.Parent = remotes
	end

	requestSprint.OnServerEvent:Connect(function(player: Player, active: any)
		if typeof(active) ~= "boolean" then return end
		MovementService.SetSprint(player, active)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
			local hum = character:WaitForChild("Humanoid", 5) :: Humanoid?
			if hum then
				hum.WalkSpeed = GameConfig.Player.WalkSpeed
			end
			if root then
				lastPositions[player.UserId] = root.Position
				lastTimes[player.UserId] = os.clock()
				teleportGraceUntil[player.UserId] = os.clock() + 2.0
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		playerSprinting[userId] = nil
		lastPositions[userId] = nil
		lastTimes[userId] = nil
		teleportGraceUntil[userId] = nil
	end)

	-- Authoritative movement sanity check loop (runs on Heartbeat)
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local userId = player.UserId
			local character = player.Character
			if character then
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local hum = character:FindFirstChildOfClass("Humanoid")
				if root and hum and hum.Health > 0 then
					local isSprinting = playerSprinting[userId] or false
					local expectedSpeed = isSprinting and GameConfig.Player.SprintSpeed or GameConfig.Player.WalkSpeed

					-- Maintain authoritative WalkSpeed on Humanoid
					if hum.WalkSpeed ~= expectedSpeed then
						hum.WalkSpeed = expectedSpeed
					end

					local lastPos = lastPositions[userId]
					local lastTime = lastTimes[userId]
					local graceUntil = teleportGraceUntil[userId] or 0

					if lastPos and lastTime and now > graceUntil then
						local dt = now - lastTime
						if dt >= 0.05 then
							local horizontalDisp = Vector2.new(root.Position.X - lastPos.X, root.Position.Z - lastPos.Z).Magnitude
							local maxAllowedDistance = (expectedSpeed * dt * 1.5) + 4.0 -- 50% margin + 4 studs buffer for latency jitter

							if horizontalDisp > maxAllowedDistance and horizontalDisp > 8.0 then
								log:Warn("Suspicious horizontal displacement detected; rubberbanding player", {
									Player = player.Name,
									Displacement = math.floor(horizontalDisp),
									MaxAllowed = math.floor(maxAllowedDistance),
									Dt = dt,
								})
								-- Teleport back to last verified safe position
								root.CFrame = CFrame.new(lastPos + Vector3.new(0, 0.5, 0))
								root.AssemblyLinearVelocity = Vector3.zero
							else
								lastPositions[userId] = root.Position
								lastTimes[userId] = now
							end
						end
					else
						lastPositions[userId] = root.Position
						lastTimes[userId] = now
					end
				end
			end
		end
	end)
end

function MovementService.SetSprint(player: Player, active: boolean): boolean
	if not SecurityService.CheckRateLimit(player, 1) then
		return false
	end

	local character = player.Character
	if not character then return false end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end

	playerSprinting[player.UserId] = active
	local speed = active and GameConfig.Player.SprintSpeed or GameConfig.Player.WalkSpeed
	hum.WalkSpeed = speed

	log:Debug("Player sprint state updated", { Player = player.Name, Active = active, Speed = speed })
	return true
end

function MovementService.IsPlayerSprinting(player: Player): boolean
	return playerSprinting[player.UserId] or false
end

function MovementService.RegisterTeleport(player: Player, duration: number?)
	local grace = duration or 2.0
	local userId = player.UserId
	teleportGraceUntil[userId] = os.clock() + grace

	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			lastPositions[userId] = root.Position
			lastTimes[userId] = os.clock()
		end
	end
end

return MovementService
