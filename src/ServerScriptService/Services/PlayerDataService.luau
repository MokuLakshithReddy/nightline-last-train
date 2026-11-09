--!strict
-- PlayerDataService.luau
-- Robust, versioned persistence layer using DataStoreService with safe retries

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"):WaitForChild("GameTypes"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("PlayerDataService")

local DATASTORE_NAME = "Nightline_PlayerData_v1"
local CURRENT_SCHEMA_VERSION = 1

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
}

local dataStore: DataStore? = nil
local profilesCache: { [number]: GameTypes.PlayerProfile } = {}
local isDirty: { [number]: boolean } = {}
local loadFailed: { [number]: boolean } = {}

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

	return profile
end

function PlayerDataService.Init()
	log:Info("Initializing PlayerDataService...")
	if not RunService:IsStudio() or pcall(function() return DataStoreService:GetDataStore("TestAccess") end) then
		local success, ds = pcall(function()
			return DataStoreService:GetDataStore(DATASTORE_NAME)
		end)
		if success and ds then
			dataStore = ds
			log:Info("Connected to DataStoreService successfully.")
		else
			log:Warn("DataStore access unavailable; utilizing local session cache.")
		end
	else
		log:Info("Running in Studio with mock session persistence.")
	end

	Players.PlayerAdded:Connect(function(player)
		PlayerDataService.LoadProfile(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		PlayerDataService.SaveProfile(player)
		profilesCache[player.UserId] = nil
		isDirty[player.UserId] = nil
		loadFailed[player.UserId] = nil
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			PlayerDataService.SaveProfile(player)
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
		local success, result = pcall(function()
			return dataStore:GetAsync(key)
		end)

		if success then
			profile = reconcileProfile(result)
			log:Info("Loaded persistent profile for player", { UserId = userId, Scrap = profile.Scrap })
		else
			log:Error("Failed to fetch DataStore key; marking read-only to prevent overwrite", {
				UserId = userId,
				Error = tostring(result),
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
	return true
end

function PlayerDataService.SaveProfile(player: Player)
	local userId = player.UserId
	local profile = profilesCache[userId]
	if not profile then return end
	if loadFailed[userId] then
		log:Warn("Skipping save because initial load failed; preventing data overwrite", { UserId = userId })
		return
	end
	if not isDirty[userId] then
		return
	end

	if dataStore then
		local key = "Player_" .. tostring(userId)
		local retries = 3
		local saved = false
		for attempt = 1, retries do
			local success, err = pcall(function()
				dataStore:UpdateAsync(key, function(_oldData)
					return profile
				end)
			end)
			if success then
				saved = true
				isDirty[userId] = false
				log:Info("Profile saved to DataStore", { UserId = userId, Attempt = attempt })
				break
			else
				log:Warn("DataStore save retry failed", { UserId = userId, Attempt = attempt, Error = tostring(err) })
				task.wait(1 * attempt)
			end
		end

		if not saved then
			log:Error("Exhausted retries while attempting to save profile", { UserId = userId })
		end
	else
		isDirty[userId] = false
	end
end

return PlayerDataService
