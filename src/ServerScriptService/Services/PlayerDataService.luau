--!strict
-- PlayerDataService.luau
-- Authoritative persistence layer with active session locking, serialized writes, and safe release

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"):WaitForChild("GameTypes"))
local RewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("RewardConfig"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("PlayerDataService")

local DATASTORE_NAME = "Nightline_PlayerData_v1"
local CURRENT_SCHEMA_VERSION = 1
local SESSION_LEASE_DURATION = 1200 -- 20 minutes lease timeout for orphaned locks

local DefaultData: GameTypes.PlayerProfile = {
	SchemaVersion = CURRENT_SCHEMA_VERSION,
	Scrap = 0,
	UnlockedStations = { Station001 = true },
	TrainUpgrades = {},
	OwnedCosmetics = {},
	EquippedCosmetics = {},
	Artifacts = {},
	Statistics = {
		Runs = 0,
		SuccessfulEscapes = 0,
		ObjectivesCompleted = 0,
		ItemsRecovered = 0,
	},
	SessionLock = nil,
	LastProcessedRoundId = nil,
}

local dataStore: DataStore? = nil
local profilesCache: { [number]: GameTypes.PlayerProfile } = {}
local isDirty: { [number]: boolean } = {}
local loadFailed: { [number]: boolean } = {}
local isSaving: { [number]: boolean } = {}

local profileUpdatedRemote: RemoteEvent? = nil

local PlayerDataService = {}

local function deepCopy<T>(original: T): T
	local copy: any = {}
	for k, v in pairs(original :: any) do
		if type(v) == "table" then
			copy[k] = deepCopy(v)
		else
			copy[k] = v
		end
	end
	return copy
end

local function reconcileProfile(loaded: any): GameTypes.PlayerProfile
	local profile = deepCopy(DefaultData)
	if type(loaded) ~= "table" then
		return profile
	end

	if type(loaded.Scrap) == "number" and loaded.Scrap >= 0 then
		profile.Scrap = loaded.Scrap
	end
	if type(loaded.UnlockedStations) == "table" then
		for k, v in pairs(loaded.UnlockedStations) do
			if type(k) == "string" and v == true then
				profile.UnlockedStations[k] = true
			end
		end
	end
	if type(loaded.TrainUpgrades) == "table" then
		for k, v in pairs(loaded.TrainUpgrades) do
			if type(k) == "string" and v == true then
				profile.TrainUpgrades[k] = true
			end
		end
	end
	if type(loaded.Artifacts) == "table" then
		for k, v in pairs(loaded.Artifacts) do
			if type(k) == "string" and v == true then
				profile.Artifacts[k] = true
			end
		end
	end
	if type(loaded.Statistics) == "table" then
		profile.Statistics.Runs = loaded.Statistics.Runs or 0
		profile.Statistics.SuccessfulEscapes = loaded.Statistics.SuccessfulEscapes or 0
		profile.Statistics.ObjectivesCompleted = loaded.Statistics.ObjectivesCompleted or 0
		profile.Statistics.ItemsRecovered = loaded.Statistics.ItemsRecovered or 0
	end
	if type(loaded.SessionLock) == "table" then
		profile.SessionLock = {
			JobId = tostring(loaded.SessionLock.JobId or ""),
			LockTimestamp = tonumber(loaded.SessionLock.LockTimestamp) or 0,
		}
	end
	if type(loaded.LastProcessedRoundId) == "string" then
		profile.LastProcessedRoundId = loaded.LastProcessedRoundId
	end

	return profile
end

function PlayerDataService.Init()
	log:Info("Initializing PlayerDataService with session locking...")

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local existing = remotes:FindFirstChild("ProfileUpdated") :: RemoteEvent?
	if not existing then
		existing = Instance.new("RemoteEvent")
		existing.Name = "ProfileUpdated"
		existing.Parent = remotes
	end
	profileUpdatedRemote = existing

	if not RunService:IsStudio() or pcall(function() return DataStoreService:GetDataStore("TestAccess") end) then
		local success, ds = pcall(function()
			return DataStoreService:GetDataStore(DATASTORE_NAME)
		end)
		if success and ds then
			dataStore = ds
			log:Info("Connected to DataStoreService with session lock authority.")
		else
			log:Warn("DataStore access unavailable; utilizing local session cache.")
		end
	else
		log:Info("Running in Studio with mock session persistence.")
	end

	Players.PlayerAdded:Connect(function(player)
		local profile = PlayerDataService.LoadProfile(player)
		PlayerDataService.Sync(player, profile)
	end)

	Players.PlayerRemoving:Connect(function(player)
		PlayerDataService.SaveProfile(player, true)
		profilesCache[player.UserId] = nil
		isDirty[player.UserId] = nil
		loadFailed[player.UserId] = nil
		isSaving[player.UserId] = nil
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			PlayerDataService.SaveProfile(player, true)
		end
	end)
end

function PlayerDataService.LoadProfile(player: Player): GameTypes.PlayerProfile
	local userId = player.UserId
	if profilesCache[userId] then
		return profilesCache[userId]
	end

	local profile: GameTypes.PlayerProfile
	if dataStore then
		local key = "Player_" .. tostring(userId)
		local currentJobId = game.JobId ~= "" and game.JobId or "StudioSession"
		local lockSuccess = false

		for attempt = 1, 3 do
			local success, result = pcall(function()
				return dataStore:UpdateAsync(key, function(storedData)
					local current = reconcileProfile(storedData)
					local now = os.time()

					-- Check existing session lock
					if current.SessionLock and current.SessionLock.JobId ~= currentJobId then
						local elapsed = now - current.SessionLock.LockTimestamp
						if elapsed < SESSION_LEASE_DURATION then
							-- Active session lock held by another server!
							log:Warn("Active session lock held by another server; aborting takeover", {
								UserId = userId,
								HoldingJobId = current.SessionLock.JobId,
								ElapsedSeconds = elapsed,
							})
							return nil
						end
					end

					-- Acquire session lock for this server instance
					current.SessionLock = {
						JobId = currentJobId,
						LockTimestamp = now,
					}
					return current
				end)
			end)

			if success and result then
				profile = result
				lockSuccess = true
				log:Info("Acquired session lock and loaded profile", {
					UserId = userId,
					Scrap = profile.Scrap,
					JobId = currentJobId,
				})
				break
			else
				log:Warn("Session lock acquisition attempt failed, retrying...", {
					UserId = userId,
					Attempt = attempt,
					Error = tostring(result),
				})
				task.wait(1.5 * attempt)
			end
		end

		if not lockSuccess then
			log:Error("Failed to acquire session lock; setting profile to read-only to prevent data corruption", {
				UserId = userId,
			})
			loadFailed[userId] = true
			profile = deepCopy(DefaultData)
		end
	else
		profile = deepCopy(DefaultData)
	end

	profilesCache[userId] = profile
	return profile
end

function PlayerDataService.GetProfile(player: Player): GameTypes.PlayerProfile?
	return profilesCache[player.UserId]
end

function PlayerDataService.AddScrap(player: Player, amount: number): boolean
	local profile = profilesCache[player.UserId]
	if not profile or amount <= 0 then return false end

	profile.Scrap += amount
	isDirty[player.UserId] = true
	log:Info("Granted scrap to player", { UserId = player.UserId, Added = amount, Total = profile.Scrap })
	PlayerDataService.Sync(player, profile)
	return true
end

function PlayerDataService.AddArtifact(player: Player, artifactId: string): boolean
	local profile = profilesCache[player.UserId]
	if not profile then return false end

	if not profile.Artifacts[artifactId] then
		profile.Artifacts[artifactId] = true
		isDirty[player.UserId] = true
		log:Info("Artifact unlocked for player", { UserId = player.UserId, Artifact = artifactId })
		PlayerDataService.Sync(player, profile)
		return true
	end
	return false
end

function PlayerDataService.PurchaseUpgrade(player: Player, upgradeId: string): (boolean, string)
	local profile = profilesCache[player.UserId]
	if not profile then
		return false, "Profile not loaded"
	end

	local upgradeDef = RewardConfig.Upgrades[upgradeId]
	if not upgradeDef then
		return false, "Invalid upgrade ID"
	end

	if profile.TrainUpgrades[upgradeId] then
		return false, "Upgrade already purchased"
	end

	if profile.Scrap < upgradeDef.CostScrap then
		return false, "Insufficient Scrap balance"
	end

	profile.Scrap -= upgradeDef.CostScrap
	profile.TrainUpgrades[upgradeId] = true
	isDirty[player.UserId] = true

	log:Info("Player purchased train upgrade", {
		Player = player.Name,
		Upgrade = upgradeId,
		Cost = upgradeDef.CostScrap,
		RemainingScrap = profile.Scrap,
	})

	PlayerDataService.Sync(player, profile)
	return true, "Upgrade successfully purchased!"
end

function PlayerDataService.Sync(player: Player, profile: GameTypes.PlayerProfile)
	if profileUpdatedRemote then
		profileUpdatedRemote:FireClient(player, profile)
	end
end

-- Serialized save with session lock verification and release on departure
function PlayerDataService.SaveProfile(player: Player, isReleasing: boolean?)
	local userId = player.UserId
	local profile = profilesCache[userId]
	if not profile then return end

	if loadFailed[userId] then
		log:Warn("Skipping save because session lock/load was unsuccessful; preventing overwrite", { UserId = userId })
		return
	end

	if not isDirty[userId] and not isReleasing then
		return
	end

	-- Mutex: wait if a save operation is already in-flight for this player
	while isSaving[userId] do
		task.wait(0.2)
	end
	isSaving[userId] = true

	if dataStore then
		local key = "Player_" .. tostring(userId)
		local currentJobId = game.JobId ~= "" and game.JobId or "StudioSession"
		local retries = 3
		local saved = false

		for attempt = 1, retries do
			local success, err = pcall(function()
				dataStore:UpdateAsync(key, function(storedData)
					local current = reconcileProfile(storedData)

					-- Verify we still own the session lock
					if current.SessionLock and current.SessionLock.JobId ~= currentJobId then
						local elapsed = os.time() - current.SessionLock.LockTimestamp
						if elapsed < SESSION_LEASE_DURATION then
							log:Error("Session lock was stolen by another server; aborting save to protect data", {
								UserId = userId,
								HoldingJobId = current.SessionLock.JobId,
							})
							return nil
						end
					end

					-- Apply in-memory modifications
					current.Scrap = profile.Scrap
					current.UnlockedStations = profile.UnlockedStations
					current.TrainUpgrades = profile.TrainUpgrades
					current.OwnedCosmetics = profile.OwnedCosmetics
					current.EquippedCosmetics = profile.EquippedCosmetics
					current.Artifacts = profile.Artifacts
					current.Statistics = profile.Statistics
					current.LastProcessedRoundId = profile.LastProcessedRoundId

					if isReleasing then
						current.SessionLock = nil
						log:Info("Releasing session lock for departing player", { UserId = userId })
					else
						current.SessionLock = {
							JobId = currentJobId,
							LockTimestamp = os.time(),
						}
					end

					return current
				end)
			end)

			if success then
				saved = true
				isDirty[userId] = false
				log:Info("Profile saved successfully to DataStore", {
					UserId = userId,
					Attempt = attempt,
					Released = isReleasing == true,
				})
				break
			else
				log:Warn("DataStore save retry failed", {
					UserId = userId,
					Attempt = attempt,
					Error = tostring(err),
				})
				task.wait(1.2 * attempt)
			end
		end

		if not saved then
			log:Error("Exhausted retries while attempting to save profile", { UserId = userId })
		end
	else
		isDirty[userId] = false
	end

	isSaving[userId] = false
end

return PlayerDataService
