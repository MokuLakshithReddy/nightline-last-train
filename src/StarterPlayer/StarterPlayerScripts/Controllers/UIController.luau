--!strict
-- UIController.luau
-- Responsive user interface, HUD, and Upgrade Shop controller for NIGHTLINE: LAST TRAIN

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameTypes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"):WaitForChild("GameTypes"))
local RewardConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("RewardConfig"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("UIController")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

local UIController = {}

-- UI Elements
local mainScreenGui: ScreenGui? = nil
local timerLabel: TextLabel? = nil
local stateLabel: TextLabel? = nil
local objectiveFrame: Frame? = nil
local objectiveTitle: TextLabel? = nil
local objectiveProgress: TextLabel? = nil
local notificationBanner: Frame? = nil
local notificationText: TextLabel? = nil
local slot1Label: TextLabel? = nil
local slot2Label: TextLabel? = nil

-- Upgrade Shop Elements
local upgradeShopFrame: Frame? = nil
local scrapBalanceLabel: TextLabel? = nil
local artifactCountLabel: TextLabel? = nil
local upgradeListContainer: ScrollingFrame? = nil

local currentPhaseEndsAt: number = 0
local cachedProfile: GameTypes.PlayerProfile? = nil

local function formatTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local mins = math.floor(s / 60)
	local secs = s % 60
	return string.format("%02d:%02d", mins, secs)
end

function UIController.Init()
	log:Info("Initializing responsive HUD and Upgrade Shop...")
	UIController.BuildHUD()
	UIController.BuildUpgradeShop()

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local roundStateRemote = remotes:WaitForChild("RoundStateChanged") :: RemoteEvent
	local objectiveRemote = remotes:WaitForChild("ObjectiveUpdated") :: RemoteEvent
	local notificationRemote = remotes:WaitForChild("Notification") :: RemoteEvent
	local inventoryRemote = remotes:WaitForChild("InventoryUpdated") :: RemoteEvent
	local profileRemote = remotes:WaitForChild("ProfileUpdated") :: RemoteEvent

	roundStateRemote.OnClientEvent:Connect(function(state: string, _serverTime: number, phaseEndsAt: number, _stationId: string)
		currentPhaseEndsAt = phaseEndsAt
		if stateLabel then
			stateLabel.Text = string.upper(state)
			if state == "EXPLORATION" then
				stateLabel.TextColor3 = Color3.fromRGB(240, 200, 80)
			elseif state == "EXTRACTION" then
				stateLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
			elseif state == "RETURN" or state == "RESULTS" then
				stateLabel.TextColor3 = Color3.fromRGB(80, 220, 120)
			else
				stateLabel.TextColor3 = Color3.fromRGB(200, 210, 225)
			end
		end

		if objectiveFrame then
			objectiveFrame.Visible = (state == "EXPLORATION" or state == "EXTRACTION")
		end

		-- Automatically close shop when departure/travel occurs
		if state == "TRAVEL" or state == "EXPLORATION" then
			if upgradeShopFrame then
				upgradeShopFrame.Visible = false
			end
		end
	end)

	objectiveRemote.OnClientEvent:Connect(function(objectiveId: string, progress: number, targetProgress: number, isComplete: boolean)
		if not objectiveFrame or not objectiveTitle or not objectiveProgress then return end
		if objectiveId == "" then
			objectiveFrame.Visible = false
			return
		end

		objectiveTitle.Text = string.upper(objectiveId)
		if isComplete then
			objectiveProgress.Text = "OBJECTIVE SECURED (Return to Train)"
			objectiveProgress.TextColor3 = Color3.fromRGB(80, 240, 120)
		else
			objectiveProgress.Text = string.format("Progress: %d / %d", progress, targetProgress)
			objectiveProgress.TextColor3 = Color3.fromRGB(220, 220, 230)
		end
	end)

	notificationRemote.OnClientEvent:Connect(function(payload: GameTypes.NotificationPayload)
		UIController.ShowNotification(payload.MessageText, payload.Severity)
	end)

	inventoryRemote.OnClientEvent:Connect(function(inventory: GameTypes.PlayerInventory)
		if slot1Label then
			slot1Label.Text = inventory.Slot1 and ("[1] " .. inventory.Slot1.Name) or "[1] [Empty]"
		end
		if slot2Label then
			slot2Label.Text = inventory.Slot2 and ("[2] " .. inventory.Slot2.Name) or "[2] [Empty]"
		end
	end)

	profileRemote.OnClientEvent:Connect(function(profile: GameTypes.PlayerProfile)
		cachedProfile = profile
		UIController.UpdateShopUI()
	end)

	-- Open upgrade terminal via ProximityPrompt
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player == localPlayer and prompt.Name == "OpenUpgradeTerminalPrompt" then
			UIController.ToggleUpgradeShop(true)
		end
	end)

	-- Timer update loop
	task.spawn(function()
		while true do
			if timerLabel and currentPhaseEndsAt > 0 then
				local remaining = currentPhaseEndsAt - os.clock()
				timerLabel.Text = formatTime(remaining)
			end
			task.wait(0.25)
		end
	end)
end

function UIController.ToggleUpgradeShop(visible: boolean)
	if upgradeShopFrame then
		upgradeShopFrame.Visible = visible
		if visible then
			UIController.UpdateShopUI()
		end
	end
end

function UIController.UpdateShopUI()
	if not cachedProfile then return end
	if scrapBalanceLabel then
		scrapBalanceLabel.Text = string.format("SCRAP BALANCE: %d", cachedProfile.Scrap)
	end

	if artifactCountLabel then
		local count = 0
		for _, v in pairs(cachedProfile.Artifacts) do
			if v == true then count += 1 end
		end
		artifactCountLabel.Text = string.format("ARTIFACTS RECOVERED: %d / 4", count)
	end

	if not upgradeListContainer then return end
	for _, child in ipairs(upgradeListContainer:GetChildren()) do
		if child:IsA("Frame") then
			local upgradeId = child.Name
			local buyBtn = child:FindFirstChild("BuyButton") :: TextButton?
			if buyBtn and cachedProfile.TrainUpgrades[upgradeId] then
				buyBtn.Text = "OWNED"
				buyBtn.BackgroundColor3 = Color3.fromRGB(60, 65, 70)
				buyBtn.TextColor3 = Color3.fromRGB(160, 165, 175)
				buyBtn.Active = false
			end
		end
	end
end

function UIController.ShowNotification(text: string, severity: "Info" | "Warning" | "Alert" | "Success")
	if not notificationBanner or not notificationText then return end

	local colors = {
		Info = Color3.fromRGB(40, 100, 180),
		Warning = Color3.fromRGB(200, 140, 30),
		Alert = Color3.fromRGB(190, 40, 40),
		Success = Color3.fromRGB(35, 150, 70),
	}

	notificationBanner.BackgroundColor3 = colors[severity] or colors.Info
	notificationText.Text = text
	notificationBanner.Visible = true
	notificationBanner.Position = UDim2.fromScale(0.5, -0.15)

	local tweenIn = TweenService:Create(
		notificationBanner,
		TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.08) }
	)
	tweenIn:Play()

	task.delay(3.5, function()
		local tweenOut = TweenService:Create(
			notificationBanner,
			TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
			{ Position = UDim2.fromScale(0.5, -0.15) }
		)
		tweenOut:Play()
		tweenOut.Completed:Connect(function()
			notificationBanner.Visible = false
		end)
	end)
end

function UIController.BuildHUD()
	mainScreenGui = Instance.new("ScreenGui")
	mainScreenGui.Name = "NIGHTLINE_HUD"
	mainScreenGui.ResetOnSpawn = false
	mainScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	mainScreenGui.Parent = playerGui

	-- Top Round Status & Countdown Header
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.AnchorPoint = Vector2.new(0.5, 0)
	topBar.Position = UDim2.fromScale(0.5, 0.015)
	topBar.Size = UDim2.fromOffset(320, 54)
	topBar.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	topBar.BorderSizePixel = 0
	topBar.Parent = mainScreenGui

	local topCorner = Instance.new("UICorner")
	topCorner.CornerRadius = UDim.new(0, 8)
	topCorner.Parent = topBar

	local topStroke = Instance.new("UIStroke")
	topStroke.Color = Color3.fromRGB(50, 55, 65)
	topStroke.Thickness = 1.5
	topStroke.Parent = topBar

	stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "StateLabel"
	stateLabel.Position = UDim2.fromOffset(14, 6)
	stateLabel.Size = UDim2.new(1, -120, 0, 22)
	stateLabel.BackgroundTransparency = 1
	stateLabel.Font = Enum.Font.GothamBold
	stateLabel.Text = "WAITING"
	stateLabel.TextColor3 = Color3.fromRGB(200, 210, 225)
	stateLabel.TextSize = 14
	stateLabel.TextXAlignment = Enum.TextXAlignment.Left
	stateLabel.Parent = topBar

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubLabel"
	subLabel.Position = UDim2.fromOffset(14, 28)
	subLabel.Size = UDim2.new(1, -120, 0, 18)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.Gotham
	subLabel.Text = "NIGHTLINE: LAST TRAIN"
	subLabel.TextColor3 = Color3.fromRGB(120, 130, 145)
	subLabel.TextSize = 11
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.Parent = topBar

	timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.AnchorPoint = Vector2.new(1, 0.5)
	timerLabel.Position = UDim2.new(1, -14, 0.5, 0)
	timerLabel.Size = UDim2.fromOffset(90, 36)
	timerLabel.BackgroundColor3 = Color3.fromRGB(26, 30, 38)
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.Text = "00:00"
	timerLabel.TextColor3 = Color3.fromRGB(240, 240, 250)
	timerLabel.TextSize = 20
	timerLabel.Parent = topBar

	local timerCorner = Instance.new("UICorner")
	timerCorner.CornerRadius = UDim.new(0, 6)
	timerCorner.Parent = timerLabel

	-- Objective Widget (Top Left)
	objectiveFrame = Instance.new("Frame")
	objectiveFrame.Name = "ObjectiveWidget"
	objectiveFrame.Position = UDim2.fromOffset(20, 20)
	objectiveFrame.Size = UDim2.fromOffset(260, 64)
	objectiveFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	objectiveFrame.BorderSizePixel = 0
	objectiveFrame.Visible = false
	objectiveFrame.Parent = mainScreenGui

	local objCorner = Instance.new("UICorner")
	objCorner.CornerRadius = UDim.new(0, 8)
	objCorner.Parent = objectiveFrame

	local objStroke = Instance.new("UIStroke")
	objStroke.Color = Color3.fromRGB(50, 55, 65)
	objStroke.Thickness = 1.5
	objStroke.Parent = objectiveFrame

	objectiveTitle = Instance.new("TextLabel")
	objectiveTitle.Name = "Title"
	objectiveTitle.Position = UDim2.fromOffset(12, 8)
	objectiveTitle.Size = UDim2.new(1, -24, 0, 20)
	objectiveTitle.BackgroundTransparency = 1
	objectiveTitle.Font = Enum.Font.GothamBold
	objectiveTitle.Text = "PRIMARY OBJECTIVE"
	objectiveTitle.TextColor3 = Color3.fromRGB(240, 200, 80)
	objectiveTitle.TextSize = 13
	objectiveTitle.TextXAlignment = Enum.TextXAlignment.Left
	objectiveTitle.Parent = objectiveFrame

	objectiveProgress = Instance.new("TextLabel")
	objectiveProgress.Name = "Progress"
	objectiveProgress.Position = UDim2.fromOffset(12, 32)
	objectiveProgress.Size = UDim2.new(1, -24, 0, 22)
	objectiveProgress.BackgroundTransparency = 1
	objectiveProgress.Font = Enum.Font.GothamMedium
	objectiveProgress.Text = "Progress: 0 / 3"
	objectiveProgress.TextColor3 = Color3.fromRGB(220, 220, 230)
	objectiveProgress.TextSize = 12
	objectiveProgress.TextXAlignment = Enum.TextXAlignment.Left
	objectiveProgress.Parent = objectiveFrame

	-- Notification Toast Banner
	notificationBanner = Instance.new("Frame")
	notificationBanner.Name = "NotificationBanner"
	notificationBanner.AnchorPoint = Vector2.new(0.5, 0)
	notificationBanner.Position = UDim2.fromScale(0.5, -0.15)
	notificationBanner.Size = UDim2.fromOffset(420, 44)
	notificationBanner.BackgroundColor3 = Color3.fromRGB(40, 100, 180)
	notificationBanner.BorderSizePixel = 0
	notificationBanner.Visible = false
	notificationBanner.ZIndex = 10
	notificationBanner.Parent = mainScreenGui

	local notifCorner = Instance.new("UICorner")
	notifCorner.CornerRadius = UDim.new(0, 8)
	notifCorner.Parent = notificationBanner

	notificationText = Instance.new("TextLabel")
	notificationText.Name = "Text"
	notificationText.Size = UDim2.fromScale(1, 1)
	notificationText.BackgroundTransparency = 1
	notificationText.Font = Enum.Font.GothamBold
	notificationText.Text = ""
	notificationText.TextColor3 = Color3.fromRGB(255, 255, 255)
	notificationText.TextSize = 14
	notificationText.ZIndex = 11
	notificationText.Parent = notificationBanner

	-- Bottom Equipment Slots HUD
	local inventoryBar = Instance.new("Frame")
	inventoryBar.Name = "InventoryBar"
	inventoryBar.AnchorPoint = Vector2.new(0.5, 1)
	inventoryBar.Position = UDim2.fromScale(0.5, 0.98)
	inventoryBar.Size = UDim2.fromOffset(340, 48)
	inventoryBar.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	inventoryBar.BorderSizePixel = 0
	inventoryBar.Parent = mainScreenGui

	local invCorner = Instance.new("UICorner")
	invCorner.CornerRadius = UDim.new(0, 8)
	invCorner.Parent = inventoryBar

	local invStroke = Instance.new("UIStroke")
	invStroke.Color = Color3.fromRGB(50, 55, 65)
	invStroke.Thickness = 1.5
	invStroke.Parent = inventoryBar

	slot1Label = Instance.new("TextLabel")
	slot1Label.Name = "Slot1"
	slot1Label.Position = UDim2.fromOffset(10, 8)
	slot1Label.Size = UDim2.new(0.5, -15, 1, -16)
	slot1Label.BackgroundColor3 = Color3.fromRGB(26, 30, 38)
	slot1Label.Font = Enum.Font.GothamMedium
	slot1Label.Text = "[1] Flashlight"
	slot1Label.TextColor3 = Color3.fromRGB(220, 225, 235)
	slot1Label.TextSize = 12
	slot1Label.Parent = inventoryBar

	local s1Corner = Instance.new("UICorner")
	s1Corner.CornerRadius = UDim.new(0, 6)
	s1Corner.Parent = slot1Label

	slot2Label = Instance.new("TextLabel")
	slot2Label.Name = "Slot2"
	slot2Label.Position = UDim2.new(0.5, 5, 0, 8)
	slot2Label.Size = UDim2.new(0.5, -15, 1, -16)
	slot2Label.BackgroundColor3 = Color3.fromRGB(26, 30, 38)
	slot2Label.Font = Enum.Font.GothamMedium
	slot2Label.Text = "[2] [Empty]"
	slot2Label.TextColor3 = Color3.fromRGB(150, 155, 165)
	slot2Label.TextSize = 12
	slot2Label.Parent = inventoryBar

	local s2Corner = Instance.new("UICorner")
	s2Corner.CornerRadius = UDim.new(0, 6)
	s2Corner.Parent = slot2Label
end

function UIController.BuildUpgradeShop()
	if not mainScreenGui then return end

	upgradeShopFrame = Instance.new("Frame")
	upgradeShopFrame.Name = "UpgradeShopModal"
	upgradeShopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	upgradeShopFrame.Position = UDim2.fromScale(0.5, 0.5)
	upgradeShopFrame.Size = UDim2.fromOffset(500, 380)
	upgradeShopFrame.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
	upgradeShopFrame.BorderSizePixel = 0
	upgradeShopFrame.Visible = false
	upgradeShopFrame.ZIndex = 20
	upgradeShopFrame.Parent = mainScreenGui

	local shopCorner = Instance.new("UICorner")
	shopCorner.CornerRadius = UDim.new(0, 10)
	shopCorner.Parent = upgradeShopFrame

	local shopStroke = Instance.new("UIStroke")
	shopStroke.Color = Color3.fromRGB(70, 90, 120)
	shopStroke.Thickness = 2
	shopStroke.Parent = upgradeShopFrame

	-- Header Title
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Position = UDim2.fromOffset(20, 14)
	header.Size = UDim2.new(1, -80, 0, 26)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBold
	header.Text = "TRAIN WORKSHOP & UPGRADES"
	header.TextColor3 = Color3.fromRGB(240, 210, 100)
	header.TextSize = 18
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.ZIndex = 21
	header.Parent = upgradeShopFrame

	-- Close Button (X)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -16, 0, 14)
	closeBtn.Size = UDim2.fromOffset(28, 28)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextSize = 14
	closeBtn.ZIndex = 22
	closeBtn.Parent = upgradeShopFrame
	closeBtn.MouseButton1Click:Connect(function()
		UIController.ToggleUpgradeShop(false)
	end)

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 6)
	closeCorner.Parent = closeBtn

	-- Balances Banner
	local balancesBar = Instance.new("Frame")
	balancesBar.Name = "BalancesBar"
	balancesBar.Position = UDim2.fromOffset(20, 46)
	balancesBar.Size = UDim2.new(1, -40, 0, 32)
	balancesBar.BackgroundColor3 = Color3.fromRGB(26, 32, 42)
	balancesBar.ZIndex = 21
	balancesBar.Parent = upgradeShopFrame

	local balCorner = Instance.new("UICorner")
	balCorner.CornerRadius = UDim.new(0, 6)
	balCorner.Parent = balancesBar

	scrapBalanceLabel = Instance.new("TextLabel")
	scrapBalanceLabel.Name = "ScrapBalance"
	scrapBalanceLabel.Position = UDim2.fromOffset(12, 0)
	scrapBalanceLabel.Size = UDim2.new(0.5, -12, 1, 0)
	scrapBalanceLabel.BackgroundTransparency = 1
	scrapBalanceLabel.Font = Enum.Font.GothamBold
	scrapBalanceLabel.Text = "SCRAP BALANCE: 0"
	scrapBalanceLabel.TextColor3 = Color3.fromRGB(120, 240, 160)
	scrapBalanceLabel.TextSize = 13
	scrapBalanceLabel.TextXAlignment = Enum.TextXAlignment.Left
	scrapBalanceLabel.ZIndex = 22
	scrapBalanceLabel.Parent = balancesBar

	artifactCountLabel = Instance.new("TextLabel")
	artifactCountLabel.Name = "ArtifactCount"
	artifactCountLabel.AnchorPoint = Vector2.new(1, 0)
	artifactCountLabel.Position = UDim2.new(1, -12, 0, 0)
	artifactCountLabel.Size = UDim2.new(0.5, -12, 1, 0)
	artifactCountLabel.BackgroundTransparency = 1
	artifactCountLabel.Font = Enum.Font.GothamBold
	artifactCountLabel.Text = "ARTIFACTS RECOVERED: 0 / 4"
	artifactCountLabel.TextColor3 = Color3.fromRGB(220, 190, 80)
	artifactCountLabel.TextSize = 13
	artifactCountLabel.TextXAlignment = Enum.TextXAlignment.Right
	artifactCountLabel.ZIndex = 22
	artifactCountLabel.Parent = balancesBar

	-- Upgrades List
	upgradeListContainer = Instance.new("ScrollingFrame")
	upgradeListContainer.Name = "UpgradeList"
	upgradeListContainer.Position = UDim2.fromOffset(20, 88)
	upgradeListContainer.Size = UDim2.new(1, -40, 1, -100)
	upgradeListContainer.BackgroundTransparency = 1
	upgradeListContainer.ScrollBarThickness = 6
	upgradeListContainer.CanvasSize = UDim2.fromOffset(0, 260)
	upgradeListContainer.ZIndex = 21
	upgradeListContainer.Parent = upgradeShopFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = upgradeListContainer

	-- Populate Upgrades from RewardConfig
	local upgradeList = { "EmergencyLighting", "WorkbenchLocker", "ReinforcedPlating", "AdvancedEngine" }
	for _, upId in ipairs(upgradeList) do
		local upDef = RewardConfig.Upgrades[upId]
		if upDef then
			local card = Instance.new("Frame")
			card.Name = upDef.Id
			card.Size = UDim2.new(1, -8, 0, 56)
			card.BackgroundColor3 = Color3.fromRGB(24, 28, 36)
			card.ZIndex = 22
			card.Parent = upgradeListContainer

			local cardCorner = Instance.new("UICorner")
			cardCorner.CornerRadius = UDim.new(0, 6)
			cardCorner.Parent = card

			local title = Instance.new("TextLabel")
			title.Position = UDim2.fromOffset(12, 6)
			title.Size = UDim2.new(1, -140, 0, 20)
			title.BackgroundTransparency = 1
			title.Font = Enum.Font.GothamBold
			title.Text = upDef.Name .. string.format(" (%d Scrap)", upDef.CostScrap)
			title.TextColor3 = Color3.fromRGB(235, 235, 245)
			title.TextSize = 13
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.ZIndex = 23
			title.Parent = card

			local desc = Instance.new("TextLabel")
			desc.Position = UDim2.fromOffset(12, 28)
			desc.Size = UDim2.new(1, -140, 0, 22)
			desc.BackgroundTransparency = 1
			desc.Font = Enum.Font.Gotham
			desc.Text = upDef.Description
			desc.TextColor3 = Color3.fromRGB(150, 155, 170)
			desc.TextSize = 11
			desc.TextXAlignment = Enum.TextXAlignment.Left
			desc.ZIndex = 23
			desc.Parent = card

			local buyBtn = Instance.new("TextButton")
			buyBtn.Name = "BuyButton"
			buyBtn.AnchorPoint = Vector2.new(1, 0.5)
			buyBtn.Position = UDim2.new(1, -12, 0.5, 0)
			buyBtn.Size = UDim2.fromOffset(100, 34)
			buyBtn.BackgroundColor3 = Color3.fromRGB(45, 130, 220)
			buyBtn.Font = Enum.Font.GothamBold
			buyBtn.Text = "PURCHASE"
			buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			buyBtn.TextSize = 12
			buyBtn.ZIndex = 24
			buyBtn.Parent = card

			local bCorner = Instance.new("UICorner")
			bCorner.CornerRadius = UDim.new(0, 6)
			bCorner.Parent = buyBtn

			buyBtn.MouseButton1Click:Connect(function()
				local remotes = ReplicatedStorage:FindFirstChild("Remotes")
				if remotes then
					local purchaseRemote = remotes:FindFirstChild("RequestPurchaseUpgrade") :: RemoteEvent?
					if purchaseRemote then
						purchaseRemote:FireServer(upDef.Id)
					end
				end
			end)
		end
	end
end

return UIController
