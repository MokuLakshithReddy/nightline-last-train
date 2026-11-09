--!strict
-- InteractionController.luau
-- Client-side presentation, contextual styling, and sensory feedback for ProximityPrompt interactions
-- Renders stylized custom prompts for Keyboard, Gamepad, and Touch devices without claiming authority

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("InteractionController")

local localPlayer = Players.LocalPlayer

type PromptData = {
	Gui: BillboardGui,
	ProgressBar: Frame?,
	Tween: Tween?,
	InputBadge: TextLabel,
	ActionLabel: TextLabel,
	ObjectLabel: TextLabel,
}

local activePrompts: { [ProximityPrompt]: PromptData } = {}
local lastInputType: Enum.ProximityPromptInputType = Enum.ProximityPromptInputType.Keyboard

local InteractionController = {}

local function getInputText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		local btn = prompt.GamepadKeyCode
		if btn == Enum.KeyCode.ButtonX then
			return "X"
		elseif btn == Enum.KeyCode.ButtonY then
			return "Y"
		elseif btn == Enum.KeyCode.ButtonA then
			return "A"
		elseif btn == Enum.KeyCode.ButtonB then
			return "B"
		else
			return btn.Name:gsub("Button", "")
		end
	else
		-- Keyboard
		local key = prompt.KeyboardKeyCode
		if key == Enum.KeyCode.E then
			return "E"
		else
			return key.Name
		end
	end
end

local function createPromptGui(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): PromptData?
	local adornee = prompt.Parent
	if not adornee or not adornee:IsA("BasePart") then
		return nil
	end

	local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CustomPromptGui_" .. prompt.Name
	billboard.Adornee = adornee
	billboard.Size = UDim2.fromOffset(220, 70)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = prompt.MaxActivationDistance + 5
	billboard.ResetOnSpawn = false

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 95, 115)
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	-- Key badge on the left
	local keyBadge = Instance.new("TextLabel")
	keyBadge.Name = "KeyBadge"
	keyBadge.Size = UDim2.fromOffset(36, 36)
	keyBadge.Position = UDim2.fromOffset(10, 10)
	keyBadge.BackgroundColor3 = Color3.fromRGB(30, 36, 48)
	keyBadge.TextColor3 = Color3.fromRGB(240, 200, 90)
	keyBadge.Font = Enum.Font.GothamBold
	keyBadge.TextSize = 16
	keyBadge.Text = getInputText(prompt, inputType)
	keyBadge.Parent = frame

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 6)
	badgeCorner.Parent = keyBadge

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = Color3.fromRGB(240, 200, 90)
	badgeStroke.Thickness = 1
	badgeStroke.Parent = keyBadge

	-- Action text
	local actionLabel = Instance.new("TextLabel")
	actionLabel.Name = "ActionLabel"
	actionLabel.Size = UDim2.new(1, -56, 0, 20)
	actionLabel.Position = UDim2.fromOffset(52, 10)
	actionLabel.BackgroundTransparency = 1
	actionLabel.TextColor3 = Color3.fromRGB(245, 245, 250)
	actionLabel.Font = Enum.Font.GothamMedium
	actionLabel.TextSize = 14
	actionLabel.TextXAlignment = Enum.TextXAlignment.Left
	actionLabel.Text = prompt.ActionText ~= "" and prompt.ActionText or "Interact"
	actionLabel.Parent = frame

	-- Object text
	local objectLabel = Instance.new("TextLabel")
	objectLabel.Name = "ObjectLabel"
	objectLabel.Size = UDim2.new(1, -56, 0, 16)
	objectLabel.Position = UDim2.fromOffset(52, 28)
	objectLabel.BackgroundTransparency = 1
	objectLabel.TextColor3 = Color3.fromRGB(160, 170, 185)
	objectLabel.Font = Enum.Font.Gotham
	objectLabel.TextSize = 12
	objectLabel.TextXAlignment = Enum.TextXAlignment.Left
	objectLabel.Text = prompt.ObjectText ~= "" and prompt.ObjectText or ""
	objectLabel.Parent = frame

	-- Hold progress bar if prompt requires hold
	local progressBar: Frame? = nil
	if prompt.HoldDuration > 0 then
		local track = Instance.new("Frame")
		track.Name = "ProgressTrack"
		track.Size = UDim2.new(1, -20, 0, 4)
		track.Position = UDim2.new(0, 10, 1, -10)
		track.BackgroundColor3 = Color3.fromRGB(35, 40, 50)
		track.BorderSizePixel = 0
		track.Parent = frame

		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(0, 2)
		trackCorner.Parent = track

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = Color3.fromRGB(240, 200, 90)
		fill.BorderSizePixel = 0
		fill.Parent = track

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 2)
		fillCorner.Parent = fill

		progressBar = fill
	end

	billboard.Parent = playerGui

	return {
		Gui = billboard,
		ProgressBar = progressBar,
		Tween = nil,
		InputBadge = keyBadge,
		ActionLabel = actionLabel,
		ObjectLabel = objectLabel,
	}
end

local function cleanupPrompt(prompt: ProximityPrompt)
	local data = activePrompts[prompt]
	if data then
		if data.Tween then
			pcall(function() data.Tween:Cancel() end)
		end
		if data.Gui then
			data.Gui:Destroy()
		end
		activePrompts[prompt] = nil
	end
end

local function configurePrompt(prompt: ProximityPrompt)
	if prompt:IsA("ProximityPrompt") then
		prompt.Style = Enum.ProximityPromptStyle.Custom
	end
end

function InteractionController.GetActivePromptCount(): number
	local count = 0
	for _ in pairs(activePrompts) do
		count += 1
	end
	return count
end

function InteractionController.GetActivePromptGui(prompt: ProximityPrompt): BillboardGui?
	local data = activePrompts[prompt]
	return data and data.Gui or nil
end

function InteractionController.GetLastInputType(): Enum.ProximityPromptInputType
	return lastInputType
end

function InteractionController.Init()
	log:Info("Initializing client InteractionController...")

	-- Scan existing prompts and configure custom style
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("ProximityPrompt") then
			configurePrompt(desc)
		end
	end

	-- Catch dynamically loaded prompts (e.g. procedural station load)
	Workspace.DescendantAdded:Connect(function(desc)
		if desc:IsA("ProximityPrompt") then
			configurePrompt(desc)
		end
	end)

	Workspace.DescendantRemoving:Connect(function(desc)
		if desc:IsA("ProximityPrompt") then
			cleanupPrompt(desc)
		end
	end)

	-- ProximityPromptService event bindings
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
		lastInputType = inputType
		cleanupPrompt(prompt)

		local data = createPromptGui(prompt, inputType)
		if data then
			activePrompts[prompt] = data
		end
	end)

	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		cleanupPrompt(prompt)
	end)

	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt)
		local data = activePrompts[prompt]
		if data and data.ProgressBar and prompt.HoldDuration > 0 then
			data.ProgressBar.Size = UDim2.fromScale(0, 1)
			local tweenInfo = TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear)
			local tween = TweenService:Create(data.ProgressBar, tweenInfo, {
				Size = UDim2.fromScale(1, 1),
			})
			data.Tween = tween
			tween:Play()
		end
	end)

	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
		local data = activePrompts[prompt]
		if data then
			if data.Tween then
				pcall(function() data.Tween:Cancel() end)
				data.Tween = nil
			end
			if data.ProgressBar then
				TweenService:Create(data.ProgressBar, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.fromScale(0, 1),
				}):Play()
			end
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local data = activePrompts[prompt]
		if data and data.Gui then
			local container = data.Gui:FindFirstChild("Container") :: Frame?
			if container then
				local stroke = container:FindFirstChildOfClass("UIStroke")
				if stroke then
					-- Brief visual pulse feedback on trigger
					TweenService:Create(stroke, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Color = Color3.fromRGB(100, 220, 255),
						Thickness = 3,
					}):Play()
				end
			end
		end
	end)

	-- Listen for notification rejections to provide contextual feedback
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local notifRemote = remotes:FindFirstChild("Notification") :: RemoteEvent?
	if notifRemote then
		notifRemote.OnClientEvent:Connect(function(payload: any)
			if typeof(payload) == "table" and payload.Severity == "Warning" then
				-- Play visual rejection shake on active prompts if relevant
				for _, data in pairs(activePrompts) do
					local container = data.Gui:FindFirstChild("Container") :: Frame?
					if container then
						local stroke = container:FindFirstChildOfClass("UIStroke")
						if stroke then
							TweenService:Create(stroke, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
								Color = Color3.fromRGB(240, 80, 80),
							}):Play()
							task.delay(0.4, function()
								if stroke and stroke.Parent then
									TweenService:Create(stroke, TweenInfo.new(0.2), {
										Color = Color3.fromRGB(80, 95, 115),
									}):Play()
								end
							end)
						end
					end
				end
			end
		end)
	end

	log:Info("InteractionController initialized successfully.")
end

return InteractionController
