--!strict
-- SecurityService.luau
-- Central rate-limiting and input validation for server-authoritative integrity

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("SecurityService")

type TokenBucket = {
	Tokens: number,
	LastRefill: number,
}

local playerBuckets: { [number]: TokenBucket } = {}

local SecurityService = {}

function SecurityService.Init()
	log:Info("Initializing SecurityService...")
	Players.PlayerRemoving:Connect(function(player)
		playerBuckets[player.UserId] = nil
	end)
end

-- Sliding token bucket rate-limiter
function SecurityService.CheckRateLimit(player: Player, cost: number?): boolean
	local effectiveCost = cost or 1
	local now = os.clock()
	local bucket = playerBuckets[player.UserId]

	if not bucket then
		bucket = {
			Tokens = GameConfig.Security.TokenBucketCapacity,
			LastRefill = now,
		}
		playerBuckets[player.UserId] = bucket
	else
		local elapsed = now - bucket.LastRefill
		bucket.Tokens = math.min(GameConfig.Security.TokenBucketCapacity, bucket.Tokens + (elapsed * GameConfig.Security.TokenBucketRefillRate))
		bucket.LastRefill = now
	end

	if bucket.Tokens >= effectiveCost then
		bucket.Tokens -= effectiveCost
		return true
	else
		log:Warn("Rate limit exceeded for player", { UserId = player.UserId, Name = player.Name })
		return false
	end
end

-- Validates player distance to a target world position
function SecurityService.ValidateDistance(player: Player, targetPosition: Vector3, maxDistance: number?): boolean
	local limit = maxDistance or GameConfig.Security.MaxInteractionDistance
	local character = player.Character
	if not character then return false end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return false end

	local distance = (rootPart.Position - targetPosition).Magnitude
	if distance > limit then
		log:Warn("Distance check failed", {
			UserId = player.UserId,
			Distance = math.floor(distance),
			MaxAllowed = limit,
		})
		return false
	end

	return true
end

-- Validates string inputs against length and type
function SecurityService.ValidateString(value: any, maxLength: number?): (boolean, string?)
	if typeof(value) ~= "string" then
		return false, nil
	end
	local limit = maxLength or GameConfig.Security.MaxPayloadStringLength
	if #value > limit then
		return false, nil
	end
	return true, value
end

-- Validates finite, non-NaN numbers
function SecurityService.ValidateNumber(value: any, min: number?, max: number?): (boolean, number?)
	if typeof(value) ~= "number" then return false, nil end
	if value ~= value or value == math.huge or value == -math.huge then
		return false, nil
	end
	if min and value < min then return false, nil end
	if max and value > max then return false, nil end
	return true, value
end

return SecurityService
