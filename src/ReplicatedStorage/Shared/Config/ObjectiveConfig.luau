--!strict
-- ObjectiveConfig.luau
-- Authoritative templates and parameters for station mission objectives

export type ObjectiveDefinition = {
	Id: string,
	Type: string,
	Title: string,
	Description: string,
	TargetCount: number,
	TargetTag: string,
	InteractionText: string,
	BaseRewardScrap: number,
}

local Objectives: { [string]: ObjectiveDefinition } = {
	RestorePower = {
		Id = "RestorePower",
		Type = "RestorePower",
		Title = "RESTORE POWER",
		Description = "Locate 3 industrial fuses and install them into the maintenance breaker sockets.",
		TargetCount = 3,
		TargetTag = "FuseSocket",
		InteractionText = "Install Fuse",
		BaseRewardScrap = 100,
	},
	RecoverCargo = {
		Id = "RecoverCargo",
		Type = "RecoverCargo",
		Title = "RECOVER LOST CARGO",
		Description = "Find 2 lost cargo crates in storage and secure them onto the train platform.",
		TargetCount = 2,
		TargetTag = "CargoDropZone",
		InteractionText = "Deliver Cargo",
		BaseRewardScrap = 100,
	},
	RepairSignal = {
		Id = "RepairSignal",
		Type = "RepairSignal",
		Title = "REPAIR THE SIGNAL",
		Description = "Align and reboot 3 relay terminals inside the control room.",
		TargetCount = 3,
		TargetTag = "SignalTerminal",
		InteractionText = "Reboot Terminal",
		BaseRewardScrap = 100,
	},
}

local ObjectiveConfig = {
	Objectives = Objectives,
	OrderList = { "RestorePower", "RecoverCargo", "RepairSignal" },
}

return ObjectiveConfig
