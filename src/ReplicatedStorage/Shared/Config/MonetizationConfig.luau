--!strict
-- MonetizationConfig.luau
-- Server-authoritative catalog of Developer Products and Game Passes for NIGHTLINE: LAST TRAIN

export type ProductType = "DeveloperProduct" | "GamePass"

export type ProductDefinition = {
	Id: number,
	Name: string,
	Type: ProductType,
	Description: string,
	GrantType: "Scrap" | "Cosmetic",
	GrantValue: any,
}

local DeveloperProducts: { [number]: ProductDefinition } = {
	-- Scrap Pouch (100 Scrap)
	[1001] = {
		Id = 1001,
		Name = "Scrap Pouch",
		Type = "DeveloperProduct",
		Description = "A small pouch containing 100 salvaged Scrap metal pieces.",
		GrantType = "Scrap",
		GrantValue = 100,
	},
	-- Scrap Crate (300 Scrap)
	[1002] = {
		Id = 1002,
		Name = "Scrap Crate",
		Type = "DeveloperProduct",
		Description = "An industrial crate packed with 300 salvage Scrap pieces.",
		GrantType = "Scrap",
		GrantValue = 300,
	},
	-- Scrap Vault (750 Scrap)
	[1003] = {
		Id = 1003,
		Name = "Scrap Vault",
		Type = "DeveloperProduct",
		Description = "A high-yield transit cache with 750 salvage Scrap pieces.",
		GrantType = "Scrap",
		GrantValue = 750,
	},
}

local GamePasses: { [number]: ProductDefinition } = {
	-- Conductor VIP Uniform
	[2001] = {
		Id = 2001,
		Name = "Conductor Uniform",
		Type = "GamePass",
		Description = "Exclusive vintage Conductor uniform cosmetic and golden whistle badge.",
		GrantType = "Cosmetic",
		GrantValue = "ConductorUniform",
	},
	-- Veteran Lantern Pass
	[2002] = {
		Id = 2002,
		Name = "Veteran Lantern",
		Type = "GamePass",
		Description = "Vintage bronze lantern cosmetic casing with custom flame hue.",
		GrantType = "Cosmetic",
		GrantValue = "VeteranLantern",
	},
}

local MonetizationConfig = {
	DeveloperProducts = DeveloperProducts,
	GamePasses = GamePasses,
}

return MonetizationConfig
