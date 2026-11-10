--!strict
-- PlayerDataService.luau
-- Authoritative persistence layer with active session locking, serialized writes, safe release, and periodic heartbeat

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"):WaitForChild("GameTypes"))
local RewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("RewardConfig"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))
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
	ProcessedReceipts = {},
}

local dataStore: DataStore? = nil
local dataStoreAvailable: boolean = false
local isStudioMockMode: boolean = RunService:IsStudio()
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

	if type(loaded.SchemaVersion) == "number" then
		profile.SchemaVersion = loaded.SchemaVersion
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
	if type(loaded.OwnedCosmetics) == "table" then
		for k, v in pairs(loaded.OwnedCosmetics) do
			if type(k) == "string" and v == true then
				profile.OwnedCosmetics[k] = true
			end
		end
	end
	if type(loaded.EquippedCosmetics) == "table" then
		for k, v in pairs(loaded.EquippedCosmetics) do
			if type(k) == "string" and type(v) == "string" then
				profile.EquippedCosmetics[k] = v
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
		profile.Statistics.Runs = (type(loaded.Statistics.Runs) == "number" and loaded.Statistics.Runs >= 0) and loaded.Statistics.Runs or 0
		profile.Statistics.SuccessfulEscapes = (type(loaded.Statistics.SuccessfulEscapes) == "number" and loaded.Statistics.SuccessfulEscapes >= 0) and loaded.Statistics.SuccessfulEscapes or 0
		profile.Statistics.ObjectivesCompleted = (type(loaded.Statistics.ObjectivesCompleted) == "number" and loaded.Statistics.ObjectivesCompleted >= 0) and loaded.Statistics.ObjectivesCompleted or 0
		profile.Statistics.ItemsRecovered = (type(loaded.Statistics.ItemsRecovered) == "number" and loaded.Statistics.ItemsRecovered >= 0) and loaded.Statistics.ItemsRecovered or 0
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
	if type(loaded.ProcessedReceipts) == "table" then
		for k, v in pairs(loaded.ProcessedReceipts) do
			if type(k) == "string" and v == true then
				if not profile.ProcessedReceipts then
					profile.ProcessedReceipts = {}
				end
				profile.ProcessedReceipts[k] = true
			end
		end
	end

	return profile
end

function PlayerDataService.Init()
	log:Info("Initializing PlayerDataService with session locking and heartbeat lease-refresh...")

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local existing = remotes:FindFirstChild("ProfileUpdated") :: RemoteEvent?
	if not existing then
		existing = Instance.new("RemoteEvent")
		existing.Name = "ProfileUpdated"
		existing.Parent = remotes
	end
	profileUpdatedRemote = existing

	local isStudio = RunService:IsStudio()
	if isStudio then
		-- In Studio, check if API access to DataStores is actually enabled
		local testOk = pcall(function()
			local testDs = DataStoreService:GetDataStore("__StudioApiCheck")
			testDs:GetAsync("__probe__")
		end)
		if testOk then
			local success, ds = pcall(function()
				return DataStoreService:GetDataStore(DATASTORE_NAME)
			end)
			if success and ds then
				dataStore = ds
				dataStoreAvailable = true
				isStudioMockMode = false
				log:Info("Connected to live DataStoreService in Studio.")
			else
				dataStore = nil
				dataStoreAvailable = false
				isStudioMockMode = true
				log:Info("Running in Studio with intentional mock persistence mode.")
			end
		else
			dataStore = nil
			dataStoreAvailable = false
			isStudioMockMode = true
			log:Info("Running in Studio with intentional mock persistence mode (API access disabled).")
		end
	else
		-- Production environment: MUST connect to live DataStore
		local success, ds = pcall(function()
			return DataStoreService:GetDataStore(DATASTORE_NAME)
		end)
		if success and ds then
			dataStore = ds
			dataStoreAvailable = true
			isStudioMockMode = false
			log:Info("Connected to production DataStoreService with session lock authority.")
		else
			dataStore = nil
			dataStoreAvailable = false
			isStudioMockMode = false
			log:Error("CRITICAL: Production DataStoreService access unavailable; failing closed into read-only mode to prevent data corruption!")
		end
	end

	Players.PlayerAdded:Connect(function(player)
		local profile = PlayerDataService.LoadProfile(player)
		PlayerDataService.Sync(player, profile)
		AnalyticsService.TrackSessionStart(player, profile.Statistics and profile.Statistics.Runs or 0, profile.Scrap)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			local profile = PlayerDataService.LoadProfile(player)
			PlayerDataService.Sync(player, profile)
			AnalyticsService.TrackSessionStart(player, profile.Statistics and profile.Statistics.Runs or 0, profile.Scrap)
		end)
	end

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

	-- Periodic Session Lock Lease Refresh Loop (runs every 5 minutes / 300 seconds)
	task.spawn(function()
		while true do
			task.wait(300)
			if dataStore then
				for _, player in ipairs(Players:GetPlayers()) do
					local userId = player.UserId
					if profilesCache[userId] and not loadFailed[userId] then
						task.spawn(function()
							PlayerDataService.SaveProfile(player, false, true)
						end)
					end
				end
			end
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
			if RunService:IsStudio() then
				log:Warn("Studio DataStore session lock acquisition failed; falling back to writable in-memory mock profile for testing", {
					UserId = userId,
				})
				isStudioMockMode = true
				dataStoreAvailable = false
				loadFailed[userId] = false
				profile = deepCopy(DefaultData)
			else
				log:Error("Failed to acquire session lock; setting profile to read-only to prevent data corruption", {
					UserId = userId,
				})
				loadFailed[userId] = true
				profile = deepCopy(DefaultData)
			end
		end
	elseif isStudioMockMode then
		loadFailed[userId] = false
		profile = deepCopy(DefaultData)
	else
		-- Production environment without DataStore access: Fail closed!
		log:Error("Production DataStore access unavailable; failing closed with read-only profile", {
			UserId = userId,
		})
		loadFailed[userId] = true
		profile = deepCopy(DefaultData)
	end

	profilesCache[userId] = profile
	return profile
end

function PlayerDataService.GetProfile(player: Player): GameTypes.PlayerProfile?
	return profilesCache[player.UserId]
end

-- Centralized check verifying the profile is active and writable (not marked read-only due to lock failure)
function PlayerDataService.IsProfileWritable(player: Player): boolean
	local userId = player.UserId
	if not dataStoreAvailable and not isStudioMockMode then
		-- Fail closed in production when DataStore is unavailable
		return false
	end
	if loadFailed[userId] == true then
		return false
	end
	if profilesCache[userId] == nil then
		return false
	end
	return true
end

function PlayerDataService.AddScrap(player: Player, amount: number): boolean
	if not PlayerDataService.IsProfileWritable(player) then
		log:Warn("Rejected AddScrap: profile is read-only or not loaded", { UserId = player.UserId })
		return false
	end

	local profile = profilesCache[player.UserId]
	if not profile or amount <= 0 then return false end

	profile.Scrap += amount
	isDirty[player.UserId] = true
	log:Info("Granted scrap to player", { UserId = player.UserId, Added = amount, Total = profile.Scrap })
	PlayerDataService.Sync(player, profile)
	return true
end

function PlayerDataService.DeductScrap(player: Player, amount: number): boolean
	if not PlayerDataService.IsProfileWritable(player) then
		log:Warn("Rejected DeductScrap: profile is read-only or not loaded", { UserId = player.UserId })
		return false
	end

	local profile = profilesCache[player.UserId]
	if not profile or amount <= 0 or profile.Scrap < amount then
		return false
	end

	profile.Scrap -= amount
	isDirty[player.UserId] = true
	log:Info("Deducted scrap from player", { UserId = player.UserId, Deducted = amount, Remaining = profile.Scrap })
	PlayerDataService.Sync(player, profile)
	return true
end

function PlayerDataService.AddArtifact(player: Player, artifactId: string): boolean
	if not PlayerDataService.IsProfileWritable(player) then
		log:Warn("Rejected AddArtifact: profile is read-only or not loaded", { UserId = player.UserId })
		return false
	end

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
	if not PlayerDataService.IsProfileWritable(player) then
		return false, "Profile is currently read-only due to lock failure; purchases disabled"
	end

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
	AnalyticsService.TrackUpgradePurchased(player, upgradeId, upgradeDef.CostScrap, profile.Scrap)
	return true, "Upgrade successfully purchased!"
end

function PlayerDataService.AddCosmetic(player: Player, cosmeticId: string): boolean
	if not PlayerDataService.IsProfileWritable(player) then
		log:Warn("Rejected AddCosmetic: profile is read-only or not loaded", { UserId = player.UserId })
		return false
	end

	local profile = profilesCache[player.UserId]
	if not profile then return false end

	if not profile.OwnedCosmetics[cosmeticId] then
		profile.OwnedCosmetics[cosmeticId] = true
		isDirty[player.UserId] = true
		log:Info("Cosmetic unlocked for player", { UserId = player.UserId, Cosmetic = cosmeticId })
		PlayerDataService.Sync(player, profile)
		return true
	end
	return false
end

function PlayerDataService.EquipCosmetic(player: Player, slot: string, cosmeticId: string?): boolean
	if not PlayerDataService.IsProfileWritable(player) then
		log:Warn("Rejected EquipCosmetic: profile is read-only or not loaded", { UserId = player.UserId })
		return false
	end

	local profile = profilesCache[player.UserId]
	if not profile then return false end

	if cosmeticId == nil then
		profile.EquippedCosmetics[slot] = nil
		isDirty[player.UserId] = true
		PlayerDataService.Sync(player, profile)
		return true
	end

	if not profile.OwnedCosmetics[cosmeticId] then
		log:Warn("Player attempted to equip unowned cosmetic", { Player = player.Name, Cosmetic = cosmeticId })
		return false
	end

	profile.EquippedCosmetics[slot] = cosmeticId
	isDirty[player.UserId] = true
	PlayerDataService.Sync(player, profile)
	return true
end

function PlayerDataService.Sync(player: Player, profile: GameTypes.PlayerProfile)
	if profileUpdatedRemote then
		profileUpdatedRemote:FireClient(player, profile)
	end
end

-- Serialized save with strict session lock verification and release on departure
function PlayerDataService.SaveProfile(player: Player, isReleasing: boolean?, isHeartbeat: boolean?): boolean
	local userId = player.UserId
	local profile = profilesCache[userId]
	if not profile then return false end

	if loadFailed[userId] then
		log:Warn("Skipping save because session lock/load was unsuccessful; preventing overwrite", { UserId = userId })
		return false
	end

	if not isDirty[userId] and not isReleasing and not isHeartbeat then
		return true
	end

	-- Mutex: wait if a save operation is already in-flight for this player
	while isSaving[userId] do
		task.wait(0.2)
	end
	isSaving[userId] = true

	local saveSuccess = false

	if dataStore then
		local key = "Player_" .. tostring(userId)
		local currentJobId = game.JobId ~= "" and game.JobId or "StudioSession"
		local retries = 3

		for attempt = 1, retries do
			local success, result = pcall(function()
				return dataStore:UpdateAsync(key, function(storedData)
					local current = reconcileProfile(storedData)

					-- Strict session lock ownership check:
					-- Server must already hold the session lock. If missing or owned by another JobId, reject save.
					if not current.SessionLock or current.SessionLock.JobId ~= currentJobId then
						log:Error("Session lock ownership validation failed; this server does not hold active lock", {
							UserId = userId,
							CurrentServerJobId = currentJobId,
							StoredLockJobId = current.SessionLock and current.SessionLock.JobId or "nil",
						})
						return nil
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

					-- Durably merge processed receipts
					if profile.ProcessedReceipts then
						if not current.ProcessedReceipts then
							current.ProcessedReceipts = {}
						end
						for rId, val in pairs(profile.ProcessedReceipts) do
							if val == true then
								current.ProcessedReceipts[rId] = true
							end
						end
					end

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

			-- Verify both pcall success and non-nil return from UpdateAsync callback
			if success and result ~= nil then
				saveSuccess = true
				isDirty[userId] = false
				log:Info("Profile saved successfully to DataStore", {
					UserId = userId,
					Attempt = attempt,
					Released = isReleasing == true,
					Heartbeat = isHeartbeat == true,
				})
				break
			else
				log:Warn("DataStore save retry failed or lock rejected", {
					UserId = userId,
					Attempt = attempt,
					Result = tostring(result),
				})
				task.wait(1.2 * attempt)
			end
		end

		if not saveSuccess then
			log:Error("Exhausted retries while attempting to save profile", { UserId = userId })
		end
	elseif isStudioMockMode then
		-- Explicit Studio mock mode: local in-memory session only
		isDirty[userId] = false
		saveSuccess = true
	else
		-- Production environment without DataStore: Fail closed!
		log:Error("Attempted SaveProfile in production with no active DataStore; write failed", {
			UserId = userId,
		})
		-- Preserve dirty state (do not clear isDirty[userId])
		saveSuccess = false
	end

	isSaving[userId] = false
	return saveSuccess
end

function PlayerDataService.SetMockMode(isMock: boolean)
	isStudioMockMode = isMock
	if isMock then
		table.clear(loadFailed)
	end
end

function PlayerDataService.SetDataStore(ds: any)
	dataStore = ds
	dataStoreAvailable = (ds ~= nil)
end

function PlayerDataService.IsDataStoreAvailable(): boolean
	return dataStoreAvailable
end

function PlayerDataService.IsMockMode(): boolean
	return isStudioMockMode
end

return PlayerDataService