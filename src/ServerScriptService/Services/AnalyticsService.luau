--!strict
-- AnalyticsService.luau
-- Authoritative server telemetry for core gameplay funnels and economic health
-- Integrates with Roblox AnalyticsService with strict payload validation, schema hygiene, and PII avoidance

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxAnalytics: any = nil
pcall(function()
	RobloxAnalytics = game:GetService("AnalyticsService")
end)

local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("AnalyticsService")

export type TelemetryEvent = {
	EventName: string,
	UserId: number?,
	Attributes: { [string]: any },
	Timestamp: number,
}

local MAX_RECENT_BUFFER = 200
local MAX_ATTRIBUTE_KEY_LEN = 32
local MAX_ATTRIBUTE_VAL_LEN = 128
local MAX_ATTRIBUTES_COUNT = 15

local recentEvents: { TelemetryEvent } = {}

local AnalyticsService = {}

local function sanitizeAttributes(raw: { [string]: any }?): { [string]: any }
	local sanitized: { [string]: any } = {}
	if not raw then return sanitized end

	local count = 0
	for key, value in pairs(raw) do
		if count >= MAX_ATTRIBUTES_COUNT then break end
		if typeof(key) == "string" and #key <= MAX_ATTRIBUTE_KEY_LEN then
			local valType = typeof(value)
			if valType == "string" then
				sanitized[key] = string.sub(value, 1, MAX_ATTRIBUTE_VAL_LEN)
				count += 1
			elseif valType == "number" or valType == "boolean" then
				sanitized[key] = value
				count += 1
			end
		end
	end

	return sanitized
end

function AnalyticsService.Init()
	log:Info("Initializing authoritative AnalyticsService telemetry...")
end

function AnalyticsService.TrackEvent(eventName: string, player: Player?, attributes: { [string]: any }?, metricValue: number?)
	local sanitized = sanitizeAttributes(attributes)
	if player then
		sanitized["UserId"] = player.UserId
	end

	local eventRecord: TelemetryEvent = {
		EventName = eventName,
		UserId = player and player.UserId or nil,
		Attributes = sanitized,
		Timestamp = os.time(),
	}

	table.insert(recentEvents, eventRecord)
	if #recentEvents > MAX_RECENT_BUFFER then
		table.remove(recentEvents, 1)
	end

	log:Info("Telemetry [" .. eventName .. "]", sanitized)

	-- Dispatch to Roblox AnalyticsService if available in live environment
	if RobloxAnalytics and player then
		pcall(function()
			RobloxAnalytics:LogCustomEvent(player, eventName, metricValue or 1, sanitized)
		end)
	end
end

function AnalyticsService.TrackSessionStart(player: Player, runs: number, scrap: number)
	AnalyticsService.TrackEvent("SessionStart", player, {
		TotalRuns = runs,
		CurrentScrap = scrap,
	})
end

function AnalyticsService.TrackExpeditionStart(roundId: string, stationId: string, rosterSize: number)
	AnalyticsService.TrackEvent("ExpeditionStart", nil, {
		RoundId = roundId,
		StationId = stationId,
		RosterSize = rosterSize,
	}, rosterSize)
end

function AnalyticsService.TrackExpeditionEnd(roundId: string, stationId: string, survivedCount: number, rosterSize: number, scrapExtracted: number)
	AnalyticsService.TrackEvent("ExpeditionEnd", nil, {
		RoundId = roundId,
		StationId = stationId,
		SurvivedCount = survivedCount,
		RosterSize = rosterSize,
		ScrapExtracted = scrapExtracted,
	}, survivedCount)
end

function AnalyticsService.TrackObjectiveCompleted(player: Player?, missionType: string, stepNumber: number, totalSteps: number)
	AnalyticsService.TrackEvent("ObjectiveStepCompleted", player, {
		MissionType = missionType,
		Step = stepNumber,
		TotalSteps = totalSteps,
	}, stepNumber)
end

function AnalyticsService.TrackPlayerExtraction(player: Player, roundId: string, unbankedScrap: number)
	AnalyticsService.TrackEvent("PlayerExtracted", player, {
		RoundId = roundId,
		UnbankedScrap = unbankedScrap,
	}, unbankedScrap)
end

function AnalyticsService.TrackPlayerElimination(player: Player, roundId: string, reason: string)
	AnalyticsService.TrackEvent("PlayerEliminated", player, {
		RoundId = roundId,
		Reason = reason,
	})
end

function AnalyticsService.TrackUpgradePurchased(player: Player, upgradeId: string, costScrap: number, remainingBalance: number)
	AnalyticsService.TrackEvent("UpgradePurchased", player, {
		UpgradeId = upgradeId,
		CostScrap = costScrap,
		RemainingBalance = remainingBalance,
	}, costScrap)

	-- Also log economy event if supported
	if RobloxAnalytics then
		pcall(function()
			RobloxAnalytics:LogEconomyEvent(
				player,
				Enum.AnalyticsEconomyFlowType.Sink,
				"Scrap",
				costScrap,
				remainingBalance,
				Enum.AnalyticsEconomyTransactionType.Shop,
				upgradeId
			)
		end)
	end
end

function AnalyticsService.GetRecentEvents(limit: number?): { TelemetryEvent }
	local maxCount = limit or #recentEvents
	local slice: { TelemetryEvent } = {}
	local startIdx = math.max(1, #recentEvents - maxCount + 1)
	for i = startIdx, #recentEvents do
		table.insert(slice, recentEvents[i])
	end
	return slice
end

function AnalyticsService.ClearRecentEvents()
	table.clear(recentEvents)
end

return AnalyticsService
