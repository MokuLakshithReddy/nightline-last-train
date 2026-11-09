--!strict
-- GameTypes.luau
-- Shared Luau type contracts for NIGHTLINE: LAST TRAIN

export type RoundState = 
	| "WAITING"
	| "INTERMISSION"
	| "BOARDING"
	| "TRAVEL"
	| "EXPLORATION"
	| "EXTRACTION"
	| "RETURN"
	| "RESULTS"

export type MissionType =
	| "RestorePower"
	| "RecoverCargo"
	| "RepairSignal"

export type MissionState = {
	Id: string,
	Type: MissionType,
	Title: string,
	Description: string,
	Progress: number,
	TargetProgress: number,
	IsComplete: boolean,
}

export type PlayerExpeditionStatus = 
	| "Hub"
	| "Rostered"
	| "Active"
	| "Extracted"
	| "Eliminated"
	| "Disconnected"

export type InventoryItem = {
	Id: string,
	Name: string,
	Type: "Equipment" | "Consumable" | "MissionItem",
	Quantity: number,
}

export type PlayerInventory = {
	Slot1: InventoryItem?,
	Slot2: InventoryItem?,
	MissionItems: { [string]: number },
}

export type PlayerStatistics = {
	Runs: number,
	SuccessfulEscapes: number,
	ObjectivesCompleted: number,
	ItemsRecovered: number,
}

export type SessionLock = {
	JobId: string,
	LockTimestamp: number,
}

export type PlayerProfile = {
	SchemaVersion: number,
	Scrap: number,
	UnlockedStations: { [string]: boolean },
	TrainUpgrades: { [string]: boolean },
	OwnedCosmetics: { [string]: boolean },
	EquippedCosmetics: { [string]: string },
	Artifacts: { [string]: boolean },
	Statistics: PlayerStatistics,
	SessionLock: SessionLock?,
	LastProcessedRoundId: string?,
	ProcessedReceipts: { [string]: boolean }?,
}

export type RoundStatePayload = {
	State: RoundState,
	ServerTimestamp: number,
	PhaseEndsAt: number,
	StationId: string,
	Duration: number,
}

export type NotificationPayload = {
	MessageKey: string,
	MessageText: string,
	Severity: "Info" | "Warning" | "Alert" | "Success",
	Duration: number?,
}

return {}
