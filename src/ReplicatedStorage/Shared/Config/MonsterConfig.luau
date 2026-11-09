--!strict
-- MonsterConfig.luau
-- Authoritative configuration for The Hollow creature AI

local MonsterConfig = {
	Id = "TheHollow",
	Name = "The Hollow",
	Description = "A sound-sensitive shadow entity hunting forgotten corridors.",

	Speeds = {
		Patrol = 10,
		Investigate = 13,
		Chase = 19,
		Search = 8,
		Return = 12,
	},

	Perception = {
		Hearing = {
			WalkNoiseRadius = 20,
			RunNoiseRadius = 45,
			InteractionNoiseRadius = 35,
			FlareNoiseRadius = 75,
			WalkStepInterval = 0.5, -- footstep cadence for walking (seconds)
			RunStepInterval = 0.3,  -- footstep cadence for sprinting (seconds)
			MinStepDistance = 2.0,  -- minimum distance (studs) traveled between footsteps
		},
		Vision = {
			MaxDistance = 50,
			FieldOfViewDegrees = 110,
			FlashlightDetectionMultiplier = 1.6,
		},
		SearchDuration = 8,
		InvestigateTimeout = 12,
		ScanIntervalSeconds = 0.35, -- Controlled perception tick to prevent frame spikes
	},

	Combat = {
		AttackRange = 5.5,
		AttackCooldown = 2.5,
		AttackWindupSeconds = 0.4,
		EliminationDamage = 100,
	},
}

return MonsterConfig

