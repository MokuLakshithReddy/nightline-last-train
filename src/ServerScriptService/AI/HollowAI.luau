--!strict
-- HollowAI.luau
-- Authoritative AI state machine and sensory perception for The Hollow creature

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MonsterConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MonsterConfig"))
local AIStateMachine = require(script.Parent:WaitForChild("AIStateMachine"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Signal"))
local log = Logger.new("HollowAI")

export type NoiseEvent = {
	Position: Vector3,
	Loudness: number,
	Radius: number,
	Timestamp: number,
	Source: Player?,
}

export type HollowContext = {
	Model: Model,
	Humanoid: Humanoid,
	RootPart: BasePart,
	EyeLight: PointLight,
	EyePart: BasePart,
	StateMachine: AIStateMachine.StateMachine,
	PatrolWaypoints: { Vector3 },
	CurrentWaypointIndex: number,
	CurrentTarget: Player?,
	LastKnownTargetPosition: Vector3?,
	InvestigatePosition: Vector3?,
	InvestigateStartTime: number,
	SearchStartTime: number,
	LastAttackTime: number,
	LastScanTime: number,
	LastPathComputeTime: number,
	IsWindingUpAttack: boolean,
	ActivePath: Path?,
	IsActive: boolean,
}

local HollowAI = {
	OnPlayerAttacked = Signal.new(),
	OnNoiseDetected = Signal.new(),
}

-- Noise broker
local recentNoises: { NoiseEvent } = {}

function HollowAI.EmitNoise(position: Vector3, radius: number, loudness: number, source: Player?)
	local noise: NoiseEvent = {
		Position = position,
		Loudness = loudness,
		Radius = radius,
		Timestamp = os.clock(),
		Source = source,
	}
	table.insert(recentNoises, noise)
	HollowAI.OnNoiseDetected:Fire(noise)

	-- Clean old noises (> 4 seconds)
	local now = os.clock()
	for i = #recentNoises, 1, -1 do
		if now - recentNoises[i].Timestamp > 4 then
			table.remove(recentNoises, i)
		end
	end
end

-- Checks line of sight between monster eyes and target character
local function hasLineOfSight(eyePos: Vector3, targetCharacter: Model): boolean
	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetRoot then return false end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { targetCharacter.Parent or targetCharacter }
	rayParams.IgnoreWater = true

	local direction = (targetRoot.Position - eyePos)
	local result = Workspace:Raycast(eyePos, direction, rayParams)

	if not result then
		return true
	end

	-- If it hit the target character or its children
	if result.Instance:IsDescendantOf(targetCharacter) then
		return true
	end

	return false
end

-- Finds best visible player within field of view and hearing
local function scanForTargets(context: HollowContext): Player?
	local now = os.clock()
	if now - context.LastScanTime < MonsterConfig.Perception.ScanIntervalSeconds then
		return context.CurrentTarget
	end
	context.LastScanTime = now

	local monsterPos = context.RootPart.Position
	local monsterForward = context.RootPart.CFrame.LookVector
	local eyePos = context.EyePart.Position

	local closestTarget: Player? = nil
	local closestDist = math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local targetPos = (character.HumanoidRootPart :: BasePart).Position
				local diff = targetPos - monsterPos
				local dist = diff.Magnitude

				-- 1. Sight detection check
				if dist <= MonsterConfig.Perception.Vision.MaxDistance then
					local dirToTarget = diff.Unit
					local dot = monsterForward:Dot(dirToTarget)
					local fovThreshold = math.cos(math.rad(MonsterConfig.Perception.Vision.FieldOfViewDegrees / 2))

					if dot >= fovThreshold or dist <= 12 then -- Peripheral/close hearing
						if hasLineOfSight(eyePos, character) then
							if dist < closestDist then
								closestDist = dist
								closestTarget = player
							end
						end
					end
				end
			end
		end
	end

	-- 2. Noise detection check (if no direct sight)
	if not closestTarget then
		for _, noise in ipairs(recentNoises) do
			local noiseDist = (noise.Position - monsterPos).Magnitude
			if noiseDist <= noise.Radius then
				context.InvestigatePosition = noise.Position
				context.InvestigateStartTime = now
				if context.StateMachine.CurrentState == "PATROL" or context.StateMachine.CurrentState == "SEARCH" then
					context.StateMachine:TransitionTo("INVESTIGATE", context)
				end
				break
			end
		end
	end

	return closestTarget
end

-- Helper to move monster along PathfindingService path
local function moveToPosition(context: HollowContext, targetPos: Vector3, speed: number)
	context.Humanoid.WalkSpeed = speed

	local now = os.clock()
	if now - context.LastPathComputeTime < 0.6 then
		return
	end
	context.LastPathComputeTime = now

	local path = PathfindingService:CreatePath({
		AgentRadius = 3.0,
		AgentHeight = 7.0,
		AgentCanJump = false,
		WaypointSpacing = 4,
	})

	local success, _ = pcall(function()
		path:ComputeAsync(context.RootPart.Position, targetPos)
	end)

	if success and path.Status == Enum.PathStatus.Success then
		context.ActivePath = path
		local waypoints = path:GetWaypoints()
		if #waypoints >= 2 then
			context.Humanoid:MoveTo(waypoints[2].Position)
		else
			context.Humanoid:MoveTo(targetPos)
		end
	else
		-- Fallback direct move
		context.Humanoid:MoveTo(targetPos)
	end
end

-- Attacks player with windup and line-of-sight validation
local function attemptAttack(context: HollowContext, player: Player)
	local now = os.clock()
	if now - context.LastAttackTime < MonsterConfig.Combat.AttackCooldown then
		return
	end
	if context.IsWindingUpAttack then
		return
	end

	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end
	local root = character.HumanoidRootPart :: BasePart

	local distance = (root.Position - context.RootPart.Position).Magnitude
	if distance > MonsterConfig.Combat.AttackRange then
		return
	end

	if not hasLineOfSight(context.EyePart.Position, character) then
		return
	end

	context.IsWindingUpAttack = true
	context.LastAttackTime = now

	-- Attack telegraph: Visual and eye flare
	context.EyeLight.Brightness = 3.5
	context.EyePart.Color = Color3.fromRGB(255, 20, 20)

	task.delay(MonsterConfig.Combat.AttackWindupSeconds, function()
		context.EyeLight.Brightness = 1.2
		context.EyePart.Color = Color3.fromRGB(255, 60, 60)
		context.IsWindingUpAttack = false

		-- Final hit verification
		if not context.IsActive or not player.Character then return end
		local finalChar = player.Character
		local finalRoot = finalChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if finalRoot and (finalRoot.Position - context.RootPart.Position).Magnitude <= (MonsterConfig.Combat.AttackRange + 1.5) then
			log:Info("The Hollow eliminated player", { Player = player.Name })
			HollowAI.OnPlayerAttacked:Fire(player)
		end
	end)
end

function HollowAI.Create(model: Model, waypoints: { Vector3 }): HollowContext
	local humanoid = model:WaitForChild("Humanoid") :: Humanoid
	local rootPart = model:WaitForChild("HumanoidRootPart") :: BasePart
	local head = model:WaitForChild("Head") :: BasePart
	local eyePart = head:WaitForChild("Eyes") :: BasePart
	local eyeLight = eyePart:WaitForChild("EyeLight") :: PointLight

	local sm = AIStateMachine.new()

	local context: HollowContext = {
		Model = model,
		Humanoid = humanoid,
		RootPart = rootPart,
		EyeLight = eyeLight,
		EyePart = eyePart,
		StateMachine = sm,
		PatrolWaypoints = waypoints,
		CurrentWaypointIndex = 1,
		CurrentTarget = nil,
		LastKnownTargetPosition = nil,
		InvestigatePosition = nil,
		InvestigateStartTime = 0,
		SearchStartTime = 0,
		LastAttackTime = 0,
		LastScanTime = 0,
		LastPathComputeTime = 0,
		IsWindingUpAttack = false,
		ActivePath = nil,
		IsActive = true,
	}

	-- 1. PATROL STATE
	sm:AddState("PATROL", {
		Enter = function(ctx: HollowContext)
			ctx.EyeLight.Color = Color3.fromRGB(255, 120, 40)
			ctx.Humanoid.WalkSpeed = MonsterConfig.Speeds.Patrol
		end,
		Update = function(ctx: HollowContext, _dt: number)
			local target = scanForTargets(ctx)
			if target then
				ctx.CurrentTarget = target
				ctx.StateMachine:TransitionTo("CHASE", ctx)
				return
			end

			if #ctx.PatrolWaypoints == 0 then return end
			local targetWaypoint = ctx.PatrolWaypoints[ctx.CurrentWaypointIndex]
			local dist = (targetWaypoint - ctx.RootPart.Position).Magnitude
			if dist <= 4 then
				ctx.CurrentWaypointIndex = (ctx.CurrentWaypointIndex % #ctx.PatrolWaypoints) + 1
			else
				moveToPosition(ctx, targetWaypoint, MonsterConfig.Speeds.Patrol)
			end
		end,
		Exit = function(_ctx: HollowContext) end,
	})

	-- 2. INVESTIGATE STATE
	sm:AddState("INVESTIGATE", {
		Enter = function(ctx: HollowContext)
			ctx.EyeLight.Color = Color3.fromRGB(240, 180, 50)
			ctx.Humanoid.WalkSpeed = MonsterConfig.Speeds.Investigate
		end,
		Update = function(ctx: HollowContext, _dt: number)
			local target = scanForTargets(ctx)
			if target then
				ctx.CurrentTarget = target
				ctx.StateMachine:TransitionTo("CHASE", ctx)
				return
			end

			local now = os.clock()
			if not ctx.InvestigatePosition or (now - ctx.InvestigateStartTime > MonsterConfig.Perception.InvestigateTimeout) then
				ctx.StateMachine:TransitionTo("SEARCH", ctx)
				return
			end

			local dist = (ctx.InvestigatePosition - ctx.RootPart.Position).Magnitude
			if dist <= 4 then
				ctx.StateMachine:TransitionTo("SEARCH", ctx)
			else
				moveToPosition(ctx, ctx.InvestigatePosition, MonsterConfig.Speeds.Investigate)
			end
		end,
		Exit = function(ctx: HollowContext)
			ctx.InvestigatePosition = nil
		end,
	})

	-- 3. CHASE STATE
	sm:AddState("CHASE", {
		Enter = function(ctx: HollowContext)
			ctx.EyeLight.Color = Color3.fromRGB(255, 30, 30)
			ctx.Humanoid.WalkSpeed = MonsterConfig.Speeds.Chase
		end,
		Update = function(ctx: HollowContext, _dt: number)
			local target = ctx.CurrentTarget
			if not target or not target.Character or not target.Character:FindFirstChild("HumanoidRootPart") then
				ctx.StateMachine:TransitionTo("SEARCH", ctx)
				return
			end

			local root = target.Character.HumanoidRootPart :: BasePart
			local dist = (root.Position - ctx.RootPart.Position).Magnitude

			-- Attack check
			if dist <= MonsterConfig.Combat.AttackRange then
				attemptAttack(ctx, target)
			else
				moveToPosition(ctx, root.Position, MonsterConfig.Speeds.Chase)
			end

			ctx.LastKnownTargetPosition = root.Position

			-- Check if target escaped line of sight and range
			if dist > MonsterConfig.Perception.Vision.MaxDistance + 15 then
				ctx.StateMachine:TransitionTo("SEARCH", ctx)
			end
		end,
		Exit = function(ctx: HollowContext)
			ctx.CurrentTarget = nil
		end,
	})

	-- 4. SEARCH STATE
	sm:AddState("SEARCH", {
		Enter = function(ctx: HollowContext)
			ctx.SearchStartTime = os.clock()
			ctx.EyeLight.Color = Color3.fromRGB(200, 100, 200)
			ctx.Humanoid.WalkSpeed = MonsterConfig.Speeds.Search
		end,
		Update = function(ctx: HollowContext, _dt: number)
			local target = scanForTargets(ctx)
			if target then
				ctx.CurrentTarget = target
				ctx.StateMachine:TransitionTo("CHASE", ctx)
				return
			end

			local now = os.clock()
			if now - ctx.SearchStartTime > MonsterConfig.Perception.SearchDuration then
				ctx.StateMachine:TransitionTo("RETURN", ctx)
				return
			end

			if ctx.LastKnownTargetPosition then
				local searchPoint = ctx.LastKnownTargetPosition + Vector3.new(math.sin(now) * 8, 0, math.cos(now) * 8)
				moveToPosition(ctx, searchPoint, MonsterConfig.Speeds.Search)
			end
		end,
		Exit = function(ctx: HollowContext)
			ctx.LastKnownTargetPosition = nil
		end,
	})

	-- 5. RETURN STATE
	sm:AddState("RETURN", {
		Enter = function(ctx: HollowContext)
			ctx.EyeLight.Color = Color3.fromRGB(150, 150, 160)
			ctx.Humanoid.WalkSpeed = MonsterConfig.Speeds.Return
		end,
		Update = function(ctx: HollowContext, _dt: number)
			local target = scanForTargets(ctx)
			if target then
				ctx.CurrentTarget = target
				ctx.StateMachine:TransitionTo("CHASE", ctx)
				return
			end

			if #ctx.PatrolWaypoints == 0 then
				ctx.StateMachine:TransitionTo("PATROL", ctx)
				return
			end

			local targetWaypoint = ctx.PatrolWaypoints[ctx.CurrentWaypointIndex]
			local dist = (targetWaypoint - ctx.RootPart.Position).Magnitude
			if dist <= 5 then
				ctx.StateMachine:TransitionTo("PATROL", ctx)
			else
				moveToPosition(ctx, targetWaypoint, MonsterConfig.Speeds.Return)
			end
		end,
		Exit = function(_ctx: HollowContext) end,
	})

	sm:TransitionTo("PATROL", context)
	return context
end

return HollowAI
