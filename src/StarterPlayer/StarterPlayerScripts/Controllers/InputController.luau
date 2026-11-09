--!strict
-- InputController.luau
-- Cross-platform input mapping and mobile touch controls for NIGHTLINE: LAST TRAIN

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

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
				reqEquipment:FireServer(slot, slot == 1 and "Flashlight" or nil)
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
	ContextActionService:SetPosition("SprintAction", UDim2.new(1, -110, 1, -170))

	-- Equipment: 1 / 2 (Keyboard), DPad Left / Right (Controller), Touch buttons
	ContextActionService:BindAction("EquipSlot1", handleSlotAction, true, Enum.KeyCode.One, Enum.KeyCode.DPadLeft)
	ContextActionService:SetTitle("EquipSlot1", "[1] Item")
	ContextActionService:SetPosition("EquipSlot1", UDim2.new(1, -170, 1, -100))

	ContextActionService:BindAction("EquipSlot2", handleSlotAction, true, Enum.KeyCode.Two, Enum.KeyCode.DPadRight)
	ContextActionService:SetTitle("EquipSlot2", "[2] Item")
	ContextActionService:SetPosition("EquipSlot2", UDim2.new(1, -100, 1, -100))

	localPlayer.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.WalkSpeed = GameConfig.Player.WalkSpeed
	end)

	if UserInputService.TouchEnabled then
		log:Info("Mobile touch input interface configured.")
	end
end

return InputController
