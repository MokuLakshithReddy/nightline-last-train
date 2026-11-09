--!strict
-- StationConfig.luau
-- Station templates, area designations, and dynamic event specifications

export type StationArea = {
	Name: string,
	Purpose: string,
	RiskLevel: "Safe" | "Low" | "Medium" | "High",
}

export type StationDefinition = {
	Id: string,
	Name: string,
	Subtitle: string,
	Description: string,
	Areas: { [string]: StationArea },
	AllowedMissions: { string },
	MaxLootNodes: number,
}

local Stations: { [string]: StationDefinition } = {
	Station001 = {
		Id = "Station001",
		Name = "The Forgotten Terminal",
		Subtitle = "Sub-Level Transit Hub",
		Description = "An abandoned art-deco passenger terminal plunged into darkness. Shadows linger in the concourse.",
		Areas = {
			Platform = { Name = "Train Platform", Purpose = "Entry & Extraction zone", RiskLevel = "Safe" },
			Concourse = { Name = "Main Concourse", Purpose = "Central transit navigation hub", RiskLevel = "Medium" },
			Maintenance = { Name = "Maintenance Room", Purpose = "Power breaker & fuse racks", RiskLevel = "Medium" },
			ControlRoom = { Name = "Control Room", Purpose = "Terminal signaling arrays", RiskLevel = "Medium" },
			CargoStorage = { Name = "Cargo Storage", Purpose = "Container salvage storage", RiskLevel = "High" },
			Tunnel = { Name = "Underground Tunnel", Purpose = "High-risk optional exploration route", RiskLevel = "High" },
		},
		AllowedMissions = { "RestorePower", "RecoverCargo", "RepairSignal" },
		MaxLootNodes = 8,
	},
}

local StationConfig = {
	Stations = Stations,
	DefaultStation = "Station001",
	Events = {
		PowerFailure = { Id = "PowerFailure", Name = "Power Grid Failure", Duration = 30 },
		SupplyCache = { Id = "SupplyCache", Name = "Emergency Supply Cache", Duration = 60 },
		LockedDoor = { Id = "LockedDoor", Name = "Pneumatic Lockdown", Duration = 45 },
	},
}

return StationConfig

