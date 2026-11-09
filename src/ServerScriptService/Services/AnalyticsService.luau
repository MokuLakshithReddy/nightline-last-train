--!strict
-- AnalyticsService.luau
-- Authoritative server telemetry for core gameplay funnels

local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("AnalyticsService")

local AnalyticsService = {}

function AnalyticsService.Init()
	log:Info("Initializing AnalyticsService...")
end

function AnalyticsService.TrackEvent(eventName: string, player: Player?, attributes: { [string]: any }?)
	local context: { [string]: any } = attributes or {}
	if player then
		context["UserId"] = player.UserId
	end
	log:Info("Telemetry [" .. eventName .. "]", context)
end

return AnalyticsService
