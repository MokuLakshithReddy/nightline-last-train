--!strict
-- RewardConfig.luau
-- Authoritative reward payouts, upgrade catalog, and collectible definitions

export type UpgradeDefinition = {
	Id: string,
	Name: string,
	CostScrap: number,
	Description: string,
	Category: "Utility" | "Cabin" | "Engine",
}

export type ArtifactDefinition = {
	Id: string,
	Name: string,
	Rarity: "Common" | "Rare" | "Relic",
	Description: string,
}

local TrainUpgrades: { [string]: UpgradeDefinition } = {
	EmergencyLighting = {
		Id = "EmergencyLighting",
		Name = "Cabin Arc Lamps",
		CostScrap = 75,
		Description = "Brightens train interior and adds exterior warning spotlights.",
		Category = "Cabin",
	},
	WorkbenchLocker = {
		Id = "WorkbenchLocker",
		Name = "Equipment Locker",
		CostScrap = 120,
		Description = "Provides an organized locker in the hub for rapid equipment preparation.",
		Category = "Utility",
	},
	ReinforcedPlating = {
		Id = "ReinforcedPlating",
		Name = "Reinforced Plating",
		CostScrap = 150,
		Description = "Heavier steel exterior plates giving the train a formidable aesthetic.",
		Category = "Cabin",
	},
	AdvancedEngine = {
		Id = "AdvancedEngine",
		Name = "Overdrive Boiler",
		CostScrap = 250,
		Description = "Restored steam pressure pistons providing enhanced departure VFX.",
		Category = "Engine",
	},
}

local Artifacts: { [string]: ArtifactDefinition } = {
	ConductorsPocketwatch = {
		Id = "ConductorsPocketwatch",
		Name = "Conductor's Brass Pocketwatch",
		Rarity = "Common",
		Description = "Stopped at 23:47. The brass casing is engraved with 'Nightline Route #1'.",
	},
	AntiqueLantern = {
		Id = "AntiqueLantern",
		Name = "Weathered Kerosene Lantern",
		Rarity = "Rare",
		Description = "Used by track workers before the blackout.",
	},
	ForgottenLedger = {
		Id = "ForgottenLedger",
		Name = "Station Master's Ledger",
		Rarity = "Rare",
		Description = "Final entries report unexplainable acoustic anomalies on the lower tracks.",
	},
	SignalWhistle = {
		Id = "SignalWhistle",
		Name = "Silver Signal Whistle",
		Rarity = "Relic",
		Description = "Produces a sound frequency capable of piercing the dense subterranean fog.",
	},
}

local RewardConfig = {
	BaseMissionReward = 100,
	ExtractionBonus = 50,
	ScrapCachePayout = 20,

	Upgrades = TrainUpgrades,
	Artifacts = Artifacts,
}

return RewardConfig
