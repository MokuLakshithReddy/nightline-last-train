--!strict
-- MovementService.luau
-- Authoritative server-side movement validation, sprint state ownership, and comprehensive anti-cheat enforcement
--
-- Security Coverage & Limitations:
-- --------------------------------
-- 1. Horizontal Speed Enforcement:
--    Restricts X/Z displacement to (expectedSpeed * dt * 1.5) + 4.0 studs buffer (accounting for network jitter).
-- 2. Vertical Anomaly & Fling Detection:
--    Allows normal jumping (JumpPower up to 50 studs/sec) and gravity falling (up to 220 studs/sec freefall).
--    Rejects abnormal upward flings (> 55 studs/sec) or downward void-clip teleports.
-- 3. Solid Geometry Wall-Traversal Mitigation:
--    Casts server-side raycasts between verified safe position and reported position.
--    Detects traversal through solid, anchored architectural walls and doors.
-- 4. Safe Rollback Verification:
--    Validates the restored position before rubberbanding to prevent placing players inside geometry or voids.
-- 5. Violation Escalation & Rate Limiting:
--    Tracks per-player violation counts with periodic decay; logs persistent exploit warnings.
--
-- Note on Remaining Limitations:
-- Server raycasting and displacement checks provide robust defense against common speed hacks,
-- vertical flings, and direct wall-clipping. They do not constitute absolute client physics sandboxing
-- against complex mesh collision interiors or moving train assemblies without client-side physics simulation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local SecurityService = require(script.Parent:WaitForChild("SecurityService"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("MovementService")

local playerSprinting: { [number]: boolean } = {}
local lastPositions: { [number]: Vector3 } = {}
local lastSafePositions: { [number]: Vector3 } = {}
local lastTimes: { [number]: number } = {}
local teleportGraceUntil: { [number]: number } = {}
local violationCounts: { [number]: number } = {}
local lastDecayTime: number = os.clock()

local MovementService = {}

local function isPositionObstructed(pos: Vector3, character: Model): boolean
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }

	local parts = Workspace:GetPartBoundsInBox(CFrame.new(pos), Vector3.new(1.8, 4.5, 1.8), overlap)
	for _, part in ipairs(parts) do
		if part.CanCollide and part.Anchored and part.Transparency < 0.95 then
			return true
		end
	end
	return false
end

local function getSafeRollbackCFrame(lastSafe: Vector3, character: Model): CFrame
	local targetPos = lastSafe
	if isPositionObstructed(targetPos, character) then
		-- Cast ray downward from lastSafe + 4 studs up to find floor
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { character }
		rayParams.IgnoreWater = true
		local hit = Workspace:Raycast(lastSafe + Vector3.new(0, 4, 0), Vector3.new(0, -10, 0), rayParams)
		if hit and hit.Instance and hit.Instance.CanCollide then
			targetPos = hit.Position + Vector3.new(0, 2.5, 0)
		end
	end
	return CFrame.new(targetPos)
end

-- Pure movement sanity validator (shared between Heartbeat loop and test suite)
function MovementService.CheckMovementSanity(
	lastPos: Vector3,
	currentPos: Vector3,
	dt: number,
	expectedSpeed: number
): (boolean, string?)
	if dt <= 0.001 then
		return true, nil
	end

	-- 1. Horizontal displacement check
	local horizontalDisp = Vector2.new(currentPos.X - lastPos.X, currentPos.Z - lastPos.Z).Magnitude
	local maxAllowedHoriz = (expectedSpeed * dt * 1.5) + 4.0 -- 50% speed margin + 4 studs latency buffer
	if horizontalDisp > maxAllowedHoriz and horizontalDisp > 8.0 then
		return false, "HorizontalSpeed"
	end

	-- 2. Vertical displacement & velocity check
	local verticalDisp = currentPos.Y - lastPos.Y
	local maxUpwardSpeed = 50.0 -- Allows standard jumping + slope climb
	local maxAllowedUpward = (maxUpwardSpeed * dt * 1.5) + 5.0
	if verticalDisp > maxAllowedUpward and verticalDisp > 12.0 then
		return false, "VerticalUpwardFling"
	end

	local maxDownwardSpeed = 220.0 -- Allows gravitational terminal freefall
	local maxAllowedDownward = (maxDownwardSpeed * dt * 1.5) + 12.0
	if -verticalDisp > maxAllowedDownward and -verticalDisp > 35.0 then
		return false, "VerticalDownwardAnomaly"
	end

	return true, nil
end

function MovementService.Init()
	log:Info("Initializing MovementService with authoritative sprint, vertical sanity, and anti-cheat validation...")

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

	local function trackCharacter(player: Player, character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		local hum = character:WaitForChild("Humanoid", 5) :: Humanoid?
		if hum then
			hum.WalkSpeed = GameConfig.Player.WalkSpeed
		end
		if root then
			lastPositions[player.UserId] = root.Position
			lastSafePositions[player.UserId] = root.Position
			lastTimes[player.UserId] = os.clock()
			teleportGraceUntil[player.UserId] = os.clock() + 3.0
			violationCounts[player.UserId] = 0
		end
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			trackCharacter(player, character)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			task.spawn(function()
				trackCharacter(player, player.Character)
			end)
		end
		player.CharacterAdded:Connect(function(character)
			trackCharacter(player, character)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		playerSprinting[userId] = nil
		lastPositions[userId] = nil
		lastSafePositions[userId] = nil
		lastTimes[userId] = nil
		teleportGraceUntil[userId] = nil
		violationCounts[userId] = nil
	end)

	-- Authoritative movement sanity check loop (runs on Heartbeat)
	RunService.Heartbeat:Connect(function()
		local now = os.clock()

		-- Periodic violation decay (every 10 seconds)
		if now - lastDecayTime >= 10.0 then
			lastDecayTime = now
			for uId, count in pairs(violationCounts) do
				if count > 0 then
					violationCounts[uId] = count - 1
				end
			end
		end

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
							local valid, violationReason = MovementService.CheckMovementSanity(lastPos, root.Position, dt, expectedSpeed)

							-- Solid wall traversal check
							local rayDir = root.Position - lastPos
							local rayDist = rayDir.Magnitude
							if valid and rayDist > 1.5 then
								local rayParams = RaycastParams.new()
								rayParams.FilterType = Enum.RaycastFilterType.Exclude
								rayParams.FilterDescendantsInstances = { character }
								rayParams.IgnoreWater = true

								local hit = Workspace:Raycast(lastPos, rayDir, rayParams)
								if hit and hit.Instance and hit.Instance.CanCollide and hit.Instance.Anchored then
									if hit.Instance.Transparency < 0.95 and hit.Instance.Size.Magnitude > 1.0 then
										local distToHit = (hit.Position - lastPos).Magnitude
										if distToHit < rayDist - 0.5 and distToHit > 0.5 then
											valid = false
											violationReason = "WallTraversal"
										end
									end
								end
							end

							if not valid then
								local currentCount = (violationCounts[userId] or 0) + 1
								violationCounts[userId] = currentCount

								log:Warn("Movement violation detected; rubberbanding player", {
									Player = player.Name,
									Reason = violationReason,
									Displacement = math.floor(rayDist),
									Dt = dt,
									Violations = currentCount,
								})

								if currentCount >= 5 then
									log:Error("Persistent movement exploit violations from player", {
										Player = player.Name,
										UserId = userId,
										TotalViolations = currentCount,
									})
								end

								-- Restore to verified safe position
								local safeCFrame = getSafeRollbackCFrame(lastSafePositions[userId] or lastPos, character)
								root.CFrame = safeCFrame
								root.AssemblyLinearVelocity = Vector3.zero
								teleportGraceUntil[userId] = now + 0.6
							else
								lastPositions[userId] = root.Position
								lastSafePositions[userId] = root.Position
								lastTimes[userId] = now
							end
						end
					else
						lastPositions[userId] = root.Position
						lastSafePositions[userId] = root.Position
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

function MovementService.RegisterTeleport(player: Player, duration: number?, destination: Vector3?)
	local grace = duration or 3.5
	local userId = player.UserId
	teleportGraceUntil[userId] = os.clock() + grace

	local targetPos = destination
	if not targetPos then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			targetPos = root.Position
		end
	end

	if targetPos then
		lastPositions[userId] = targetPos
		lastSafePositions[userId] = targetPos
		lastTimes[userId] = os.clock()
		violationCounts[userId] = 0
	end
end

function MovementService.GetLastSafePosition(player: Player): Vector3?
	return lastSafePositions[player.UserId]
end

function MovementService.GetViolationCount(player: Player): number
	return violationCounts[player.UserId] or 0
end

function MovementService.ResetViolationCount(player: Player)
	violationCounts[player.UserId] = 0
end

return MovementService
