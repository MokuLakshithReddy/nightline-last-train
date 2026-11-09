--!strict
-- ItemConfig.luau
-- Equipment, consumables, and mission items configuration

export type ItemDefinition = {
	Id: string,
	Name: string,
	Type: "Equipment" | "Consumable" | "MissionItem",
	MaxStack: number,
	Description: string,
	Weight: number,
	VisualColor: Color3,
}

local Items: { [string]: ItemDefinition } = {
	Flashlight = {
		Id = "Flashlight",
		Name = "Standard Flashlight",
		Type = "Equipment",
		MaxStack = 1,
		Description = "Handheld lantern providing directional beam illumination.",
		Weight = 1.0,
		VisualColor = Color3.fromRGB(240, 240, 180),
	},
	Flare = {
		Id = "Flare",
		Name = "Distraction Flare",
		Type = "Consumable",
		MaxStack = 3,
		Description = "High-intensity flare that generates noise and light to misdirect creatures.",
		Weight = 0.5,
		VisualColor = Color3.fromRGB(255, 60, 40),
	},
	Fuse = {
		Id = "Fuse",
		Name = "Industrial Fuse",
		Type = "MissionItem",
		MaxStack = 3,
		Description = "Heavy electrical fuse needed to restore station breaker power.",
		Weight = 2.0,
		VisualColor = Color3.fromRGB(80, 180, 255),
	},
	CargoContainer = {
		Id = "CargoContainer",
		Name = "Lost Cargo Crate",
		Type = "MissionItem",
		MaxStack = 1,
		Description = "Secured cargo salvage container. Carry to the train drop point.",
		Weight = 4.0,
		VisualColor = Color3.fromRGB(230, 190, 80),
	},
	Battery = {
		Id = "Battery",
		Name = "Emergency Battery",
		Type = "Consumable",
		MaxStack = 2,
		Description = "Spare cell providing auxiliary charge and salvage value.",
		Weight = 0.5,
		VisualColor = Color3.fromRGB(120, 255, 120),
	},
}

local ItemConfig = {
	MaxEquipmentSlots = 2,
	Items = Items,
}

return ItemConfig
