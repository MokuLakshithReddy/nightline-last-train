--!strict
-- MonsterService.luau
-- Authoritative monster lifecycle coordinator, noise listening, and physical model builder

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local MonsterConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MonsterConfig"))
local HollowAI = require(script.Parent.Parent:WaitForChild("AI"):WaitForChild("HollowAI"))
local MovementService = require(script.Parent:WaitForChild("MovementService"))
local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("MonsterService")

local currentMonsterModel: Model? = nil
local currentAIContext: HollowAI.HollowContext? = nil
local aiLoopThread: thread? = nil
local noiseListeningConnection: RBXScriptConnection? = nil

local notificationRemote: RemoteEvent? = nil
local playerStatusRemote: RemoteEvent? = nil

local MonsterService = {}

local function createPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = false
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function MonsterService.Init()
	log:Info("Initializing MonsterService...")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	notificationRemote = remotes:WaitForChild("Notification") :: RemoteEvent
	playerStatusRemote = remotes:WaitForChild("PlayerStatusUpdated") :: RemoteEvent

	HollowAI.OnPlayerAttacked:Connect(function(player: Player)
		log:Info("Handling player elimination by The Hollow", { Player = player.Name })

		pcall(function()
			local RoundService = require(script.Parent:WaitForChild("RoundService"))
			local roundId = RoundService.GetCurrentRoundId()
			AnalyticsService.TrackPlayerElimination(player, roundId, "TheHollow")
		end)

		-- Inform all clients
		if notificationRemote then
			notificationRemote:FireAllClients({
				MessageKey = "PLAYER_ELIMINATED",
				MessageText = string.format("%s was eliminated by The Hollow in the darkness!", player.Name),
				Severity = "Alert",
				Duration = 5,
			})
		end

		if playerStatusRemote then
			playerStatusRemote:FireAllClients(player.UserId, "Eliminated", "Eliminated by The Hollow")
		end

		-- Teleport eliminated player back to Hub safe carriage
		local character = player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			local root = character.HumanoidRootPart :: BasePart
			MovementService.RegisterTeleport(player, 2.5)
			root.CFrame = CFrame.new(GameConfig.World.HubCenter + Vector3.new(0, 3, 0))
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)
end

function MonsterService.BuildMonsterModel(): Model
	local model = Instance.new("Model")
	model.Name = "TheHollow"

	local offset = GameConfig.World.ActiveStationOffset
	local spawnPos = offset + Vector3.new(42, 4, -40)

	-- RootPart
	local root = createPart(model, "HumanoidRootPart", Vector3.new(2.5, 5, 2), CFrame.new(spawnPos), Color3.fromRGB(15, 15, 18), Enum.Material.SmoothPlastic)
	root.Transparency = 1
	model.PrimaryPart = root

	-- Torso (Slender shadow figure)
	local torso = createPart(model, "Torso", Vector3.new(2.4, 4.2, 1.6), CFrame.new(spawnPos), Color3.fromRGB(18, 18, 22), Enum.Material.Slate)
	local rootWeld = Instance.new("WeldConstraint")
	rootWeld.Part0 = root
	rootWeld.Part1 = torso
	rootWeld.Parent = torso

	-- Head
	local head = createPart(model, "Head", Vector3.new(1.8, 2, 1.8), CFrame.new(spawnPos + Vector3.new(0, 3, 0)), Color3.fromRGB(12, 12, 15), Enum.Material.Slate)
	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0 = torso
	headWeld.Part1 = head
	headWeld.Parent = head

	-- Glowing Spectral Eyes
	local eyes = createPart(head, "Eyes", Vector3.new(1.2, 0.4, 0.3), CFrame.new(spawnPos + Vector3.new(0, 3.2, -0.9)), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
	eyes.CanCollide = false
	local eyeWeld = Instance.new("WeldConstraint")
	eyeWeld.Part0 = head
	eyeWeld.Part1 = eyes
	eyeWeld.Parent = eyes

	local eyeLight = Instance.new("PointLight")
	eyeLight.Name = "EyeLight"
	eyeLight.Color = Color3.fromRGB(255, 40, 40)
	eyeLight.Brightness = 1.2
	eyeLight.Range = 18
	eyeLight.Shadows = true
	eyeLight.Parent = eyes

	-- Shadow Particle Aura
	local attachment = Instance.new("Attachment")
	attachment.Parent = torso

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "ShadowSmoke"
	smoke.Color = ColorSequence.new(Color3.fromRGB(10, 10, 14))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(1, 3.5),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(1.0, 1.8)
	smoke.Rate = 18
	smoke.Speed = NumberRange.new(1, 2)
	smoke.SpreadAngle = Vector2.new(45, 45)
	smoke.Parent = attachment

	-- Humanoid configuration
	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.MaxHealth = 1000
	humanoid.Health = 1000
	humanoid.WalkSpeed = MonsterConfig.Speeds.Patrol
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	-- Note: Network ownership cannot be assigned while model is unparented;
	-- it is assigned in SpawnMonster after model is parented to Workspace.Runtime.

	return model
end

function MonsterService.SpawnMonster()
	local success, err = pcall(function()
		MonsterService.DespawnMonster()

		local world = Workspace:FindFirstChild("World")
		if not world then
			world = Instance.new("Folder")
			world.Name = "World"
			world.Parent = Workspace
		end
		local runtime = world:FindFirstChild("Runtime")
		if not runtime then
			runtime = Instance.new("Folder")
			runtime.Name = "Runtime"
			runtime.Parent = world
		end

		log:Info("Spawning The Hollow into Station 001...")

		local model = MonsterService.BuildMonsterModel()
		-- Parent to Workspace hierarchy FIRST before setting network ownership
		model.Parent = runtime
		currentMonsterModel = model

		-- Server network ownership for physical simulation integrity (requires part in Workspace)
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and root:IsDescendantOf(Workspace) then
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
		end

		local offset = GameConfig.World.ActiveStationOffset
		local waypoints = {
			offset + Vector3.new(42, 2, 0),    -- Concourse Center
			offset + Vector3.new(88, 2, 18),   -- Maintenance Room
			offset + Vector3.new(42, 2, 55),   -- Cargo Storage
			offset + Vector3.new(88, 2, -18),  -- Control Room
			offset + Vector3.new(42, -2, -65), -- Underground Tunnel
		}

		local context = HollowAI.Create(model, waypoints)
		currentAIContext = context

		-- Start AI tick loop (10 Hz)
		aiLoopThread = task.spawn(function()
			while context.IsActive do
				local tickOk, tickErr = pcall(function()
					context.StateMachine:Update(context, 0.1)
				end)
				if not tickOk then
					log:Error("Error in Hollow AI tick loop: " .. tostring(tickErr))
				end
				task.wait(0.1)
			end
		end)

		-- Listen for movement noise derived from server-authoritative movement state
		noiseListeningConnection = game:GetService("RunService").Heartbeat:Connect(function()
			for _, player in ipairs(Players:GetPlayers()) do
				local char = player.Character
				if char and char:FindFirstChild("HumanoidRootPart") then
					local hum = char:FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 and hum.MoveDirection.Magnitude > 0.1 then
						local isSprinting = MovementService.IsPlayerSprinting(player)
						local radius = isSprinting and MonsterConfig.Perception.Hearing.RunNoiseRadius or MonsterConfig.Perception.Hearing.WalkNoiseRadius
						local loudness = isSprinting and 2.0 or 1.0
						HollowAI.EmitNoise((char.HumanoidRootPart :: BasePart).Position, radius, loudness, player)
					end
				end
			end
		end)

		log:Info("The Hollow is actively patrolling Station 001.")
	end)

	if not success then
		log:Error("Failed to spawn monster: " .. tostring(err))
	end
end

function MonsterService.DespawnMonster()
	if noiseListeningConnection then
		noiseListeningConnection:Disconnect()
		noiseListeningConnection = nil
	end

	if currentAIContext then
		currentAIContext.IsActive = false
		currentAIContext = nil
	end

	if aiLoopThread then
		task.cancel(aiLoopThread)
		aiLoopThread = nil
	end

	if currentMonsterModel then
		log:Info("Despawning The Hollow model...")
		currentMonsterModel:Destroy()
		currentMonsterModel = nil
	end
end

return MonsterService
