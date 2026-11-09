--!strict
-- RewardService.luau
-- Authoritative calculation and idempotent distribution of Scrap and artifacts

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("RewardConfig"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("RewardService")

local grantedRounds: { [string]: { [number]: boolean } } = {}

local RewardService = {}

function RewardService.Init()
	log:Info("Initializing RewardService...")
end

function RewardService.AwardExpeditionRewards(
	roundId: string,
	player: Player,
	missionCompleted: boolean,
	extracted: boolean,
	extraScrap: number?
): number
	if not grantedRounds[roundId] then
		grantedRounds[roundId] = {}
	end

	if grantedRounds[roundId][player.UserId] then
		log:Warn("Reward already granted for this round; preventing duplicate", {
			RoundId = roundId,
			UserId = player.UserId,
		})
		return 0
	end

	local totalPayout = 0
	if missionCompleted then
		totalPayout += RewardConfig.BaseMissionReward
	end
	if extracted then
		totalPayout += RewardConfig.ExtractionBonus
	end
	if extraScrap and extraScrap > 0 then
		totalPayout += extraScrap
	end

	if totalPayout > 0 then
		PlayerDataService.AddScrap(player, totalPayout)
		local profile = PlayerDataService.GetProfile(player)
		if profile then
			profile.Statistics.Runs += 1
			if extracted then
				profile.Statistics.SuccessfulEscapes += 1
			end
			if missionCompleted then
				profile.Statistics.ObjectivesCompleted += 1
			end
		end
		grantedRounds[roundId][player.UserId] = true

		log:Info("Granted expedition rewards", {
			UserId = player.UserId,
			Player = player.Name,
			Payout = totalPayout,
			MissionCompleted = missionCompleted,
			Extracted = extracted,
		})
	end

	return totalPayout
end

return RewardService
