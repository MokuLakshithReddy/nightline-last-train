--!strict
-- InputController.luau
-- Cross-platform input mapping, flashlight/flare controls, and mobile touch bindings for NIGHTLINE: LAST TRAIN

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("InputController")

local localPlayer = Players.LocalPlayer

local InputController = {}

local function setSprint(active: boolean)
	local character = localPlayer.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = active and GameConfig.Player.SprintSpeed or GameConfig.Player.WalkSpeed
		end
	end

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local requestSprint = remotes:FindFirstChild("RequestSprint") :: RemoteEvent?
		if requestSprint then
			requestSprint:FireServer(active)
		end
	end
end

local function handleSprintAction(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if inputState == Enum.UserInputState.Begin then
		setSprint(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		setSprint(false)
	end
	return Enum.ContextActionResult.Pass
end

local function handleSlotAction(actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if inputState == Enum.UserInputState.Begin then
		local slot = actionName == "EquipSlot1" and 1 or 2
		log:Debug("Equip slot triggered", { Slot = slot })
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if remotes then
			local reqEquipment = remotes:FindFirstChild("RequestEquipment") :: RemoteEvent?
			if reqEquipment then
				reqEquipment:FireServer(slot, slot == 1 and "Flashlight" or "Flare")
			end
		end
	end
	return Enum.ContextActionResult.Pass
end

local function handleFlashlightAction(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if inputState == Enum.UserInputState.Begin then
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if remotes then
			local toggleRemote = remotes:FindFirstChild("ToggleFlashlight") :: RemoteEvent?
			if toggleRemote then
				toggleRemote:FireServer()
			end
		end
	end
	return Enum.ContextActionResult.Pass
end

local function handleThrowFlareAction(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if inputState == Enum.UserInputState.Begin then
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local cam = Workspace.CurrentCamera
		local lookDir = cam and cam.CFrame.LookVector or (root and root.CFrame.LookVector or Vector3.new(0, 0, -1))
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if remotes then
			local throwRemote = remotes:FindFirstChild("ThrowFlare") :: RemoteEvent?
			if throwRemote then
				throwRemote:FireServer(lookDir)
			end
		end
	end
	return Enum.ContextActionResult.Pass
end

function InputController.Init()
	log:Info("Initializing cross-platform input bindings...")

	-- Sprint: Shift (Keyboard), L3 (Controller), On-screen touch button (Mobile)
	ContextActionService:BindAction("SprintAction", handleSprintAction, true, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("SprintAction", "Sprint")
	ContextActionService:SetPosition("SprintAction", UDim2.new(1, -95, 1, -165))

	-- Equipment: 1 / 2 (Keyboard), DPad Left / Right (Controller), Touch buttons
	ContextActionService:BindAction("EquipSlot1", handleSlotAction, true, Enum.KeyCode.One, Enum.KeyCode.DPadLeft)
	ContextActionService:SetTitle("EquipSlot1", "[1] Flashlight")
	ContextActionService:SetPosition("EquipSlot1", UDim2.new(1, -225, 1, -90))

	ContextActionService:BindAction("EquipSlot2", handleSlotAction, true, Enum.KeyCode.Two, Enum.KeyCode.DPadRight)
	ContextActionService:SetTitle("EquipSlot2", "[2] Flare")
	ContextActionService:SetPosition("EquipSlot2", UDim2.new(1, -155, 1, -90))

	-- Flashlight Toggle: F (Keyboard), ButtonY (Controller), Mobile touch button
	ContextActionService:BindAction("ToggleFlashlight", handleFlashlightAction, true, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
	ContextActionService:SetTitle("ToggleFlashlight", "[F] Light")
	ContextActionService:SetPosition("ToggleFlashlight", UDim2.new(1, -85, 1, -90))

	-- Throw Flare: G (Keyboard), ButtonB (Controller), Mobile touch button
	ContextActionService:BindAction("ThrowFlare", handleThrowFlareAction, true, Enum.KeyCode.G, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle("ThrowFlare", "[G] Flare")
	ContextActionService:SetPosition("ThrowFlare", UDim2.new(1, -165, 1, -165))

	localPlayer.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.WalkSpeed = GameConfig.Player.WalkSpeed
	end)

	if UserInputService.TouchEnabled then
		log:Info("Mobile touch input interface configured.")
	end
end

return InputController