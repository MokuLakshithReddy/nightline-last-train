--!strict
-- GameConfig.luau
-- Authoritative global balance and lifecycle constants for NIGHTLINE: LAST TRAIN

local GameConfig = {
	Version = "1.0.0",

	Server = {
		MaxPlayers = 6,
		MinPlayersToStart = 1,
	},

	-- Phase durations in seconds (Appendix A / Section 3.2)
	Round = {
		Durations = {
			INTERMISSION = 15,
			BOARDING = 45,
			TRAVEL = 20,
			EXPLORATION = 180,
			EXTRACTION = 60,
			RETURN = 20,
			RESULTS = 30,
		},
		DefaultStationId = "Station001",
	},

	-- World space constants
	World = {
		HubCenter = Vector3.new(0, 5, 0),
		HubSpawnOffset = Vector3.new(0, 3, 0),
		TrainInteriorCenter = Vector3.new(0, 5, -20),
		PlatformCenter = Vector3.new(0, 5, 10),
		ActiveStationOffset = Vector3.new(0, 500, 0), -- Off-screen / secluded station runtime
	},

	-- Security and rate limit bounds
	Security = {
		MaxRemoteRatePerSecond = 10,
		MaxInteractionDistance = 15,
		MaxPayloadStringLength = 128,
		TokenBucketCapacity = 15,
		TokenBucketRefillRate = 5,
	},

	-- Character mechanics
	Player = {
		WalkSpeed = 14,
		SprintSpeed = 22,
		JumpPower = 40,
		MaxHealth = 100,
	},
}

return GameConfig

