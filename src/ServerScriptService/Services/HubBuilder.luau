--!strict
-- HubBuilder.luau
-- Procedural architect for the Train Hub, Passenger Carriage, Platform, and Upgrade Terminal

local Workspace = game:GetService("Workspace")

local Logger = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("HubBuilder")

local HubBuilder = {}

local function createPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function HubBuilder.BuildHub(): Folder
	local world = Workspace:FindFirstChild("World") :: Folder?
	if not world then
		world = Instance.new("Folder")
		world.Name = "World"
		world.Parent = Workspace
	end

	local runtime = world:FindFirstChild("Runtime") :: Folder?
	if not runtime then
		runtime = Instance.new("Folder")
		runtime.Name = "Runtime"
		runtime.Parent = world
	end

	local existingHub = world:FindFirstChild("Hub") :: Folder?
	if existingHub then
		log:Info("Hub already exists in Workspace.World.Hub")
		return existingHub
	end

	log:Info("Constructing stylized Train Hub and Passenger Carriage...")

	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub.Parent = world

	-- 1. Create Platform
	local platformFolder = Instance.new("Folder")
	platformFolder.Name = "Platform"
	platformFolder.Parent = hub

	-- Main platform slab
	createPart(
		platformFolder,
		"PlatformDeck",
		Vector3.new(30, 2, 80),
		CFrame.new(12, 1, 0),
		Color3.fromRGB(60, 62, 65),
		Enum.Material.Concrete
	)

	-- Platform safety edge (yellow caution stripe)
	createPart(
		platformFolder,
		"SafetyEdge",
		Vector3.new(2, 2.05, 80),
		CFrame.new(-2, 1, 0),
		Color3.fromRGB(220, 180, 40),
		Enum.Material.SmoothPlastic
	)

	-- Platform back wall with subway tiling
	createPart(
		platformFolder,
		"BackWall",
		Vector3.new(2, 16, 80),
		CFrame.new(27, 10, 0),
		Color3.fromRGB(45, 48, 52),
		Enum.Material.Brick
	)

	-- Platform roof canopy
	createPart(
		platformFolder,
		"Canopy",
		Vector3.new(34, 1.5, 84),
		CFrame.new(12, 18, 0),
		Color3.fromRGB(35, 38, 42),
		Enum.Material.Metal
	)

	-- Pillars supporting canopy
	for z = -30, 30, 20 do
		createPart(
			platformFolder,
			"Pillar",
			Vector3.new(1.5, 16, 1.5),
			CFrame.new(24, 9.5, z),
			Color3.fromRGB(80, 85, 90),
			Enum.Material.Metal
		)
	end

	-- Station Terminal Sign
	local signBoard = createPart(
		platformFolder,
		"StationSign",
		Vector3.new(0.5, 4, 24),
		CFrame.new(25.8, 13, 0),
		Color3.fromRGB(20, 22, 25),
		Enum.Material.SmoothPlastic
	)
	local signGui = Instance.new("SurfaceGui")
	signGui.Name = "StationSignGui"
	signGui.Face = Enum.NormalId.Left
	signGui.CanvasSize = Vector2.new(600, 100)
	signGui.Parent = signBoard

	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundColor3 = Color3.fromRGB(15, 18, 22)
	signLabel.TextColor3 = Color3.fromRGB(230, 210, 140)
	signLabel.Font = Enum.Font.GothamBold
	signLabel.TextSize = 28
	signLabel.Text = "NIGHTLINE TERMINAL — SAFE HAVEN"
	signLabel.Parent = signGui

	-- Platform Warm Lanterns
	for z = -25, 25, 25 do
		local lampPost = createPart(
			platformFolder,
			"LampFixture",
			Vector3.new(0.8, 0.8, 0.8),
			CFrame.new(10, 16.5, z),
			Color3.fromRGB(240, 220, 150),
			Enum.Material.Neon
		)
		local light = Instance.new("PointLight")
		light.Brightness = 1.2
		light.Color = Color3.fromRGB(255, 220, 160)
		light.Range = 26
		light.Shadows = true
		light.Parent = lampPost
	end

	-- 2. Create Train Rails & Bed
	local trackBed = createPart(
		hub,
		"TrackGravel",
		Vector3.new(14, 1.5, 100),
		CFrame.new(-10, 0.25, 0),
		Color3.fromRGB(30, 30, 32),
		Enum.Material.Pebble
	)
	trackBed.CanCollide = false

	-- Left and Right Rails
	createPart(hub, "RailLeft", Vector3.new(0.6, 0.8, 100), CFrame.new(-13, 1.2, 0), Color3.fromRGB(160, 165, 170), Enum.Material.Metal)
	createPart(hub, "RailRight", Vector3.new(0.6, 0.8, 100), CFrame.new(-7, 1.2, 0), Color3.fromRGB(160, 165, 170), Enum.Material.Metal)

	-- 3. Create Passenger Carriage (The Train Hub)
	local train = Instance.new("Model")
	train.Name = "Train"
	train.Parent = hub

	local trainX = -10
	local carriageLength = 50
	local carriageWidth = 10
	local carriageHeight = 10

	-- Carriage Floor
	local floor = createPart(
		train,
		"CarriageFloor",
		Vector3.new(carriageWidth, 1.2, carriageLength),
		CFrame.new(trainX, 2.6, 0),
		Color3.fromRGB(45, 30, 20),
		Enum.Material.WoodPlanks
	)
	train.PrimaryPart = floor

	-- Carriage Ceiling
	createPart(
		train,
		"CarriageCeiling",
		Vector3.new(carriageWidth, 1, carriageLength),
		CFrame.new(trainX, 12, 0),
		Color3.fromRGB(38, 42, 48),
		Enum.Material.Metal
	)

	-- Outer Wall
	createPart(
		train,
		"FarWall",
		Vector3.new(1, carriageHeight, carriageLength),
		CFrame.new(trainX - (carriageWidth / 2) + 0.5, 7.3, 0),
		Color3.fromRGB(30, 34, 40),
		Enum.Material.Metal
	)

	-- End Bulkheads (Front & Back)
	createPart(
		train,
		"FrontBulkhead",
		Vector3.new(carriageWidth, carriageHeight, 1),
		CFrame.new(trainX, 7.3, carriageLength / 2 - 0.5),
		Color3.fromRGB(25, 28, 33),
		Enum.Material.Metal
	)
	createPart(
		train,
		"BackBulkhead",
		Vector3.new(carriageWidth, carriageHeight, 1),
		CFrame.new(trainX, 7.3, -carriageLength / 2 + 0.5),
		Color3.fromRGB(25, 28, 33),
		Enum.Material.Metal
	)

	-- Platform-facing Wall with Open Passenger Boarding Doorway
	createPart(
		train,
		"PlatformWallLeft",
		Vector3.new(1, carriageHeight, 18),
		CFrame.new(trainX + (carriageWidth / 2) - 0.5, 7.3, -15),
		Color3.fromRGB(30, 34, 40),
		Enum.Material.Metal
	)
	createPart(
		train,
		"PlatformWallRight",
		Vector3.new(1, carriageHeight, 18),
		CFrame.new(trainX + (carriageWidth / 2) - 0.5, 7.3, 15),
		Color3.fromRGB(30, 34, 40),
		Enum.Material.Metal
	)
	createPart(
		train,
		"DoorLintel",
		Vector3.new(1, 2.5, 14),
		CFrame.new(trainX + (carriageWidth / 2) - 0.5, 11, 0),
		Color3.fromRGB(30, 34, 40),
		Enum.Material.Metal
	)

	-- Train Interior Lighting
	for z = -16, 16, 16 do
		local lamp = createPart(
			train,
			"InteriorLamp",
			Vector3.new(1.2, 0.4, 1.2),
			CFrame.new(trainX, 11.4, z),
			Color3.fromRGB(255, 230, 180),
			Enum.Material.Neon
		)
		local light = Instance.new("PointLight")
		light.Brightness = 1.0
		light.Color = Color3.fromRGB(255, 215, 160)
		light.Range = 22
		light.Shadows = true
		light.Parent = lamp
	end

	-- Passenger Seating inside the train
	local seatsFolder = Instance.new("Folder")
	seatsFolder.Name = "Seats"
	seatsFolder.Parent = train

	for z = -18, 18, 9 do
		if math.abs(z) > 4 then
			local seat = Instance.new("Seat")
			seat.Name = "PassengerSeat"
			seat.Size = Vector3.new(2.4, 1.2, 4)
			seat.CFrame = CFrame.new(trainX - 3.2, 3.8, z) * CFrame.Angles(0, math.rad(90), 0)
			seat.Color = Color3.fromRGB(110, 45, 45)
			seat.Material = Enum.Material.SmoothPlastic
			seat.Anchored = true
			seat.Parent = seatsFolder
		end
	end

	-- Departure Board inside train
	local boardPart = createPart(
		train,
		"DepartureBoard",
		Vector3.new(0.4, 3, 7),
		CFrame.new(trainX - 4.6, 8, 0),
		Color3.fromRGB(15, 15, 18),
		Enum.Material.SmoothPlastic
	)
	local boardGui = Instance.new("SurfaceGui")
	boardGui.Name = "DepartureBoardGui"
	boardGui.Face = Enum.NormalId.Right
	boardGui.CanvasSize = Vector2.new(400, 200)
	boardGui.Parent = boardPart

	local boardHeader = Instance.new("TextLabel")
	boardHeader.Name = "Header"
	boardHeader.Size = UDim2.fromScale(1, 0.35)
	boardHeader.BackgroundColor3 = Color3.fromRGB(25, 28, 35)
	boardHeader.TextColor3 = Color3.fromRGB(240, 200, 80)
	boardHeader.Font = Enum.Font.GothamBold
	boardHeader.TextSize = 20
	boardHeader.Text = "EXPEDITION STATUS"
	boardHeader.Parent = boardGui

	local boardStatus = Instance.new("TextLabel")
	boardStatus.Name = "StatusText"
	boardStatus.Position = UDim2.fromScale(0, 0.35)
	boardStatus.Size = UDim2.fromScale(1, 0.65)
	boardStatus.BackgroundColor3 = Color3.fromRGB(15, 18, 22)
	boardStatus.TextColor3 = Color3.fromRGB(220, 220, 230)
	boardStatus.Font = Enum.Font.GothamMedium
	boardStatus.TextSize = 16
	boardStatus.Text = "DESTINATION: Forgotten Terminal\nPREPARE CREW"
	boardStatus.Parent = boardGui

	-- Equipment Locker interactable
	local lockerPart = createPart(
		train,
		"EquipmentLocker",
		Vector3.new(2, 6, 3),
		CFrame.new(trainX + 3.5, 6, -20),
		Color3.fromRGB(70, 75, 80),
		Enum.Material.Metal
	)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LockerPrompt"
	prompt.ActionText = "Inspect Loadout"
	prompt.ObjectText = "Equipment Locker"
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0.2
	prompt.Parent = lockerPart

	-- Train Upgrade Workbench & Terminal
	local upgradeTerminal = createPart(
		train,
		"UpgradeTerminal",
		Vector3.new(3, 4, 3),
		CFrame.new(trainX + 3.5, 5, 20),
		Color3.fromRGB(45, 60, 80),
		Enum.Material.Metal
	)
	local upgradePrompt = Instance.new("ProximityPrompt")
	upgradePrompt.Name = "OpenUpgradeTerminalPrompt"
	upgradePrompt.ActionText = "Access Upgrades & Scrap"
	upgradePrompt.ObjectText = "Train Workshop Terminal"
	upgradePrompt.MaxActivationDistance = 10
	upgradePrompt.RequiresLineOfSight = false
	upgradePrompt.HoldDuration = 0.3
	upgradePrompt.Parent = upgradeTerminal

	local termScreen = createPart(
		upgradeTerminal,
		"Screen",
		Vector3.new(0.2, 1.8, 2.4),
		CFrame.new(trainX + 2.3, 6, 20),
		Color3.fromRGB(20, 25, 30),
		Enum.Material.SmoothPlastic
	)
	local termGui = Instance.new("SurfaceGui")
	termGui.Face = Enum.NormalId.Left
	termGui.CanvasSize = Vector2.new(240, 180)
	termGui.Parent = termScreen

	local termLabel = Instance.new("TextLabel")
	termLabel.Size = UDim2.fromScale(1, 1)
	termLabel.BackgroundColor3 = Color3.fromRGB(15, 20, 28)
	termLabel.TextColor3 = Color3.fromRGB(100, 220, 255)
	termLabel.Font = Enum.Font.Code
	termLabel.TextSize = 18
	termLabel.Text = "[WORKSHOP]\nSCRAP TERMINAL\nPRESS (E)"
	termLabel.Parent = termGui

	-- 4. Create Spawn Locations in Hub
	local spawnsFolder = Instance.new("Folder")
	spawnsFolder.Name = "Spawns"
	spawnsFolder.Parent = hub

	for i = 1, 6 do
		local offsetZ = (i - 3.5) * 6
		local spawnPart = Instance.new("SpawnLocation")
		spawnPart.Name = "HubSpawn_" .. tostring(i)
		spawnPart.Size = Vector3.new(4, 0.5, 4)
		spawnPart.CFrame = CFrame.new(trainX, 3.4, offsetZ)
		spawnPart.Color = Color3.fromRGB(60, 90, 130)
		spawnPart.Material = Enum.Material.SmoothPlastic
		spawnPart.Anchored = true
		spawnPart.CanCollide = false
		spawnPart.Transparency = 1
		spawnPart.Neutral = true
		spawnPart.Duration = 0
		spawnPart.Parent = spawnsFolder
	end

	log:Info("Train Hub successfully built and configured with Workshop Terminal.")
	return hub
end

return HubBuilder
