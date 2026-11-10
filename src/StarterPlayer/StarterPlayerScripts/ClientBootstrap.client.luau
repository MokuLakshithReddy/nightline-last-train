--!strict
-- ClientBootstrap.client.luau
-- Client entry point and presentation controller coordinator for NIGHTLINE: LAST TRAIN

local StarterPlayerScripts = script.Parent
local Controllers = StarterPlayerScripts:WaitForChild("Controllers")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("ClientBootstrap")

log:Info("Initializing NIGHTLINE client...")

local UIController = require(Controllers:WaitForChild("UIController"))
local InputController = require(Controllers:WaitForChild("InputController"))
local CameraController = require(Controllers:WaitForChild("CameraController"))
local InteractionController = require(Controllers:WaitForChild("InteractionController"))
local AudioController = require(Controllers:WaitForChild("AudioController"))
local EffectsController = require(Controllers:WaitForChild("EffectsController"))

EffectsController.Init()
UIController.Init()
InputController.Init()
CameraController.Init()
InteractionController.Init()
AudioController.Init()

-- Synchronize authoritative server teleportation directly onto client character physics
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local teleportRemote = remotes:WaitForChild("TeleportClient") :: RemoteEvent
teleportRemote.OnClientEvent:Connect(function(destination: Vector3)
	local char = localPlayer.Character
	if char then
		char:PivotTo(CFrame.new(destination))
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end
end)

log:Info("NIGHTLINE client ready.")

