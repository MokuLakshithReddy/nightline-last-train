--!strict
-- CameraController.luau
-- Presentation and perspective camera controller for NIGHTLINE: LAST TRAIN
-- Manages cinematic transitions during Train Travel and Return states with fail-safe restoration

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("CameraController")

local localPlayer = Players.LocalPlayer

local isTransitionActive: boolean = false
local activeTransitionThread: thread? = nil
local activeTween: Tween? = nil
local currentPhase: string = "WAITING"

local CameraController = {}

-- Safely restores camera control to standard player character controls
function CameraController.RestorePlayerCamera()
	if activeTransitionThread then
		task.cancel(activeTransitionThread)
		activeTransitionThread = nil
	end

	if activeTween then
		pcall(function()
			activeTween:Cancel()
		end)
		activeTween = nil
	end

	isTransitionActive = false

	local camera = Workspace.CurrentCamera
	if not camera then return end

	pcall(function()
		camera.CameraType = Enum.CameraType.Custom
		local character = localPlayer and localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end)
end

-- Plays cinematic camera transit sequence when train departs for an expedition
function CameraController.PlayTravelTransition(duration: number?)
	local dur = duration or 4
	CameraController.RestorePlayerCamera()

	local camera = Workspace.CurrentCamera
	if not camera then return end

	local character = localPlayer and localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local basePos = rootPart and rootPart.Position or Vector3.new(-10, 8, 0)

	local startCF = CFrame.new(basePos + Vector3.new(-6, 3, -12), basePos + Vector3.new(0, 1, 10))
	local targetCF = CFrame.new(basePos + Vector3.new(4, 2, 8), basePos + Vector3.new(0, 1, 25))

	isTransitionActive = true

	local ok, err = pcall(function()
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = startCF

		local tweenInfo = TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		local tween = TweenService:Create(camera, tweenInfo, { CFrame = targetCF })
		activeTween = tween
		tween:Play()
	end)

	if not ok then
		log:Warn("Failed to start travel camera tween; restoring camera immediately", { Error = tostring(err) })
		CameraController.RestorePlayerCamera()
		return
	end

	activeTransitionThread = task.delay(dur, function()
		activeTransitionThread = nil
		CameraController.RestorePlayerCamera()
	end)
end

-- Plays cinematic extraction departure sequence when train heads back to the Hub
function CameraController.PlayReturnTransition(duration: number?)
	local dur = duration or 3.5
	CameraController.RestorePlayerCamera()

	local camera = Workspace.CurrentCamera
	if not camera then return end

	local character = localPlayer and localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local basePos = rootPart and rootPart.Position or Vector3.new(0, 8, 0)

	local startCF = CFrame.new(basePos + Vector3.new(0, 4, -15), basePos + Vector3.new(0, 1, 10))
	local targetCF = CFrame.new(basePos + Vector3.new(0, 7, -25), basePos + Vector3.new(0, 1, 0))

	isTransitionActive = true

	local ok, err = pcall(function()
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = startCF

		local tweenInfo = TweenInfo.new(dur, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
		local tween = TweenService:Create(camera, tweenInfo, { CFrame = targetCF })
		activeTween = tween
		tween:Play()
	end)

	if not ok then
		log:Warn("Failed to start return camera tween; restoring camera immediately", { Error = tostring(err) })
		CameraController.RestorePlayerCamera()
		return
	end

	activeTransitionThread = task.delay(dur, function()
		activeTransitionThread = nil
		CameraController.RestorePlayerCamera()
	end)
end

function CameraController.IsTransitionActive(): boolean
	return isTransitionActive
end

function CameraController.GetCurrentPhase(): string
	return currentPhase
end

function CameraController.GetCameraType(): Enum.CameraType?
	local camera = Workspace.CurrentCamera
	return camera and camera.CameraType or nil
end

function CameraController.Init()
	log:Info("Initializing CameraController...")

	-- Handle camera reference changes
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if not isTransitionActive and Workspace.CurrentCamera then
			pcall(function()
				Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
			end)
		end
	end)

	-- Handle character lifecycle events
	if localPlayer then
		localPlayer.CharacterAdded:Connect(function()
			task.wait(0.1)
			if not isTransitionActive then
				CameraController.RestorePlayerCamera()
			end
		end)

		localPlayer.CharacterRemoving:Connect(function()
			CameraController.RestorePlayerCamera()
		end)
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local roundStateRemote = remotes:WaitForChild("RoundStateChanged") :: RemoteEvent

	roundStateRemote.OnClientEvent:Connect(function(state: string)
		currentPhase = state
		if state == "TRAVEL" then
			CameraController.PlayTravelTransition(4)
		elseif state == "RETURN" then
			CameraController.PlayReturnTransition(3.5)
		else
			if isTransitionActive then
				CameraController.RestorePlayerCamera()
			end
		end
	end)
end

return CameraController
