--!strict
-- RewardService.luau
-- Authoritative calculation, persistent profile-level idempotency, and comprehensive run statistics

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("RewardConfig"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("RewardService")

local grantedRounds: { [string]: { [number]: boolean } } = {}

local RewardService = {}

function RewardService.Init()
	log:Info("Initializing RewardService with persistent idempotency and statistics tracking...")
end

function RewardService.AwardExpeditionRewards(
	roundId: string,
	player: Player,
	missionCompleted: boolean,
	extracted: boolean,
	unbankedScrap: number?,
	collectedArtifacts: { string }?
): number
	-- In-memory duplicate guard
	if not grantedRounds[roundId] then
		grantedRounds[roundId] = {}
	end

	if grantedRounds[roundId][player.UserId] then
		log:Warn("Reward already granted in this server session; skipping duplicate", {
			RoundId = roundId,
			UserId = player.UserId,
		})
		return 0
	end

	local profile = PlayerDataService.GetProfile(player)
	if not profile then
		log:Error("Cannot award rewards; profile is nil", { UserId = player.UserId })
		return 0
	end

	-- Persistent Profile-Level Idempotency Check (Problem 5)
	if profile.LastProcessedRoundId == roundId then
		log:Warn("Expedition round already committed to persistent profile; skipping duplicate grant", {
			RoundId = roundId,
			UserId = player.UserId,
		})
		return 0
	end
	profile.LastProcessedRoundId = roundId

	-- Always Update Expedition Statistics Regardless of Payout (Problem 5)
	profile.Statistics.Runs += 1

	if extracted then
		profile.Statistics.SuccessfulEscapes += 1
		-- Permanently grant artifacts collected during the expedition
		if collectedArtifacts then
			for _, artifactId in ipairs(collectedArtifacts) do
				PlayerDataService.AddArtifact(player, artifactId)
			end
		end
	end

	if missionCompleted then
		profile.Statistics.ObjectivesCompleted += 1
	end

	-- Calculate Authoritative Payout Formula
	local totalPayout = 0
	if missionCompleted then
		totalPayout += RewardConfig.BaseMissionReward
	end
	if extracted then
		totalPayout += RewardConfig.ExtractionBonus
		-- Bank unbanked scrap only upon successful extraction (Problem 1)
		if unbankedScrap and unbankedScrap > 0 then
			totalPayout += unbankedScrap
			profile.Statistics.ItemsRecovered += 1
		end
	end

	if totalPayout > 0 then
		PlayerDataService.AddScrap(player, totalPayout)
	else
		-- Sync statistics update even if 0 payout
		PlayerDataService.Sync(player, profile)
	end

	grantedRounds[roundId][player.UserId] = true

	log:Info("Expedition outcome recorded", {
		UserId = player.UserId,
		Player = player.Name,
		Runs = profile.Statistics.Runs,
		TotalPayout = totalPayout,
		MissionCompleted = missionCompleted,
		Extracted = extracted,
		UnbankedScrapBanked = extracted and (unbankedScrap or 0) or 0,
	})

	return totalPayout
end

return RewardService
