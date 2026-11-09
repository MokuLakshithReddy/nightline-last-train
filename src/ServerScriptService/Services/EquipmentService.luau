--!strict
-- EquipmentService.luau
-- Authoritative equipment mechanics: Functional Flashlight beam and Throwing Flares with consumption

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HollowAI = require(script.Parent.Parent:WaitForChild("AI"):WaitForChild("HollowAI"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("EquipmentService")

local flashlightStates: { [number]: boolean } = {}
local activeFlashlightModels: { [number]: Model } = {}

local EquipmentService = {}

function EquipmentService.Init()
	log:Info("Initializing EquipmentService with authoritative equipment state...")

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local toggleFlashlight = remotes:FindFirstChild("ToggleFlashlight") :: RemoteEvent?
	if not toggleFlashlight then
		toggleFlashlight = Instance.new("RemoteEvent")
		toggleFlashlight.Name = "ToggleFlashlight"
		toggleFlashlight.Parent = remotes
	end

	local throwFlare = remotes:FindFirstChild("ThrowFlare") :: RemoteEvent?
	if not throwFlare then
		throwFlare = Instance.new("RemoteEvent")
		throwFlare.Name = "ThrowFlare"
		throwFlare.Parent = remotes
	end

	toggleFlashlight.OnServerEvent:Connect(function(player: Player)
		EquipmentService.ToggleFlashlight(player)
	end)

	throwFlare.OnServerEvent:Connect(function(player: Player, lookVector: any)
		if typeof(lookVector) ~= "Vector3" then return end
		EquipmentService.ThrowFlare(player, lookVector)
	end)

	Players.PlayerRemoving:Connect(function(player)
		EquipmentService.RemoveFlashlight(player)
	end)
end

function EquipmentService.ToggleFlashlight(player: Player): boolean
	local character = player.Character
	if not character then return false end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end

	local isOn = not (flashlightStates[player.UserId] or false)
	flashlightStates[player.UserId] = isOn

	if isOn then
		EquipmentService.AttachFlashlightModel(player, character)
		log:Info("Player turned ON flashlight", { Player = player.Name })
	else
		EquipmentService.RemoveFlashlight(player)
		log:Info("Player turned OFF flashlight", { Player = player.Name })
	end

	return isOn
end

function EquipmentService.IsFlashlightOn(player: Player): boolean
	return flashlightStates[player.UserId] or false
end

function EquipmentService.AttachFlashlightModel(player: Player, character: Model)
	EquipmentService.RemoveFlashlight(player)

	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not torso then return end

	local model = Instance.new("Model")
	model.Name = "PlayerFlashlight"
	model.Parent = character

	local casing = Instance.new("Part")
	casing.Name = "FlashlightCasing"
	casing.Size = Vector3.new(0.6, 0.6, 1.4)
	casing.Color = Color3.fromRGB(30, 32, 36)
	casing.Material = Enum.Material.Metal
	casing.CanCollide = false
	casing.Anchored = false
	casing.CFrame = torso.CFrame * CFrame.new(0.8, 0.2, -0.6)
	casing.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = casing
	weld.Parent = casing

	local bulb = Instance.new("Part")
	bulb.Name = "Bulb"
	bulb.Size = Vector3.new(0.5, 0.5, 0.2)
	bulb.Color = Color3.fromRGB(255, 250, 200)
	bulb.Material = Enum.Material.Neon
	bulb.CanCollide = false
	bulb.Anchored = false
	bulb.CFrame = casing.CFrame * CFrame.new(0, 0, -0.7)
	bulb.Parent = model

	local bulbWeld = Instance.new("WeldConstraint")
	bulbWeld.Part0 = casing
	bulbWeld.Part1 = bulb
	bulbWeld.Parent = bulb

	local spotLight = Instance.new("SpotLight")
	spotLight.Name = "Beam"
	spotLight.Face = Enum.NormalId.Back
	spotLight.Color = Color3.fromRGB(255, 245, 210)
	spotLight.Brightness = 2.4
	spotLight.Range = 45
	spotLight.Angle = 65
	spotLight.Shadows = true
	spotLight.Parent = bulb

	activeFlashlightModels[player.UserId] = model
end

function EquipmentService.RemoveFlashlight(player: Player)
	flashlightStates[player.UserId] = false
	if activeFlashlightModels[player.UserId] then
		activeFlashlightModels[player.UserId]:Destroy()
		activeFlashlightModels[player.UserId] = nil
	end
end

function EquipmentService.ThrowFlare(player: Player, direction: Vector3)
	local character = player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
	if not InventoryService.HasEquippedItem(player, "Flare") then
		log:Warn("Player attempted to throw flare without having one equipped", { Player = player.Name })
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if remotes then
			local notif = remotes:FindFirstChild("Notification") :: RemoteEvent?
			if notif then
				notif:FireClient(player, {
					MessageKey = "NO_FLARE_EQUIPPED",
					MessageText = "You must equip a Flare before throwing it!",
					Severity = "Warning",
					Duration = 3,
				})
			end
		end
		return
	end

	-- Authoritatively consume the flare from player inventory slots
	InventoryService.ConsumeEquippedItem(player, "Flare")

	local cleanDir = direction.Unit
	if cleanDir.Magnitude ~= cleanDir.Magnitude then
		cleanDir = root.CFrame.LookVector
	end

	log:Info("Player threw distraction flare", { Player = player.Name })

	local flare = Instance.new("Part")
	flare.Name = "DistractionFlare"
	flare.Size = Vector3.new(0.6, 0.6, 1.8)
	flare.CFrame = root.CFrame * CFrame.new(0, 1, -2)
	flare.Color = Color3.fromRGB(255, 40, 30)
	flare.Material = Enum.Material.Neon
	flare.CanCollide = true
	flare.Parent = Workspace

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 60, 40)
	light.Brightness = 2.5
	light.Range = 30
	light.Shadows = true
	light.Parent = flare

	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(255, 80, 50))
	smoke.Size = NumberSequence.new(0.5, 2.0)
	smoke.Transparency = NumberSequence.new(0.2, 1.0)
	smoke.Rate = 25
	smoke.Speed = NumberRange.new(2, 4)
	smoke.Lifetime = NumberRange.new(0.8, 1.5)
	smoke.Parent = flare

	-- Throw velocity
	flare.AssemblyLinearVelocity = (cleanDir * 55) + Vector3.new(0, 18, 0)

	-- Emit noise to distract The Hollow
	HollowAI.EmitNoise(flare.Position, 75, 3.0, player)

	-- Continuous noise pulses while burning
	task.spawn(function()
		for _ = 1, 6 do
			task.wait(1.5)
			if flare and flare.Parent then
				HollowAI.EmitNoise(flare.Position, 65, 2.5, player)
			end
		end
	end)

	Debris:AddItem(flare, 12)
end

return EquipmentService