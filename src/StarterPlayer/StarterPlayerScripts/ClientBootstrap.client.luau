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

log:Info("NIGHTLINE client ready.")
