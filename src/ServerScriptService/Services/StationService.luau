--!strict
-- StationService.luau
-- Authoritative level architect for Station 001: The Forgotten Terminal

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local StationConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("StationConfig"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("StationService")

local currentStation: Model? = nil

local StationService = {}

local function createPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	canCollide: boolean?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = if canCollide ~= nil then canCollide else true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function createSign(parent: Instance, text: string, cframe: CFrame, size: Vector3, face: Enum.NormalId)
	local board = createPart(parent, "SignBoard", size, cframe, Color3.fromRGB(20, 22, 26), Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.CanvasSize = Vector2.new(500, 100)
	gui.Parent = board

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(15, 18, 22)
	label.TextColor3 = Color3.fromRGB(240, 200, 90)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.Text = text
	label.Parent = gui
end

function StationService.Init()
	log:Info("Initializing StationService...")
end

function StationService.LoadStation(stationId: string?): Model
	local targetId = stationId or StationConfig.DefaultStation
	local stationDef = StationConfig.Stations[targetId] or StationConfig.Stations[StationConfig.DefaultStation]
	StationService.UnloadStation()

	log:Info("Constructing station level: " .. stationDef.Name, { StationId = targetId })

	local world = Workspace:WaitForChild("World")
	local runtime = world:WaitForChild("Runtime")

	local station = Instance.new("Model")
	station.Name = "ActiveStation"
	station:SetAttribute("StationId", targetId)
	station:SetAttribute("StationName", stationDef.Name)
	station.Parent = runtime

	local offset = GameConfig.World.ActiveStationOffset

	-- =========================================================================
	-- 1. AREA: TRAIN PLATFORM (Entry & Extraction Zone)
	-- =========================================================================
	local platformFolder = Instance.new("Folder")
	platformFolder.Name = "Platform"
	platformFolder.Parent = station

	-- Main extraction platform floor
	local platformDeck = createPart(
		platformFolder,
		"PlatformDeck",
		Vector3.new(24, 2, 80),
		CFrame.new(offset + Vector3.new(0, 0, 0)),
		Color3.fromRGB(52, 54, 60),
		Enum.Material.Concrete
	)
	station.PrimaryPart = platformDeck

	-- Platform hazard edge
	createPart(
		platformFolder,
		"CautionEdge",
		Vector3.new(2, 2.05, 80),
		CFrame.new(offset + Vector3.new(-11, 0, 0)),
		Color3.fromRGB(220, 170, 30),
		Enum.Material.SmoothPlastic
	)

	-- Extraction Area Volume
	local extractionZone = createPart(
		platformFolder,
		"ExtractionZone",
		Vector3.new(20, 10, 24),
		CFrame.new(offset + Vector3.new(0, 5, -24)),
		Color3.fromRGB(50, 210, 100),
		Enum.Material.ForceField,
		false
	)
	extractionZone.Transparency = 0.85

	local extractionBill = Instance.new("BillboardGui")
	extractionBill.Name = "ExtractionSign"
	extractionBill.Size = UDim2.fromScale(8, 2.5)
	extractionBill.AlwaysOnTop = true
	extractionBill.Adornee = extractionZone
	extractionBill.Parent = extractionZone

	local extractionLabel = Instance.new("TextLabel")
	extractionLabel.Size = UDim2.fromScale(1, 1)
	extractionLabel.BackgroundTransparency = 1
	extractionLabel.TextColor3 = Color3.fromRGB(80, 255, 130)
	extractionLabel.Font = Enum.Font.GothamBold
	extractionLabel.TextSize = 24
	extractionLabel.Text = "TRAIN EXTRACTION GATE"
	extractionLabel.Parent = extractionBill

	-- Cargo Drop-off Point on Platform
	local cargoDropPoint = createPart(
		platformFolder,
		"CargoDropPoint",
		Vector3.new(8, 0.4, 8),
		CFrame.new(offset + Vector3.new(6, 1.2, 10)),
		Color3.fromRGB(200, 150, 40),
		Enum.Material.DiamondPlate
	)
	local dropPrompt = Instance.new("ProximityPrompt")
	dropPrompt.Name = "DeliverCargoPrompt"
	dropPrompt.ActionText = "Deliver Cargo"
	dropPrompt.ObjectText = "Train Platform Cargo Pallet"
	dropPrompt.MaxActivationDistance = 8
	dropPrompt.RequiresLineOfSight = false
	dropPrompt.HoldDuration = 0.5
	dropPrompt.Parent = cargoDropPoint

	-- Platform Overhead Canopy & Partition Wall with Entrance Portal
	createPart(platformFolder, "PlatformWallNorth", Vector3.new(1.5, 16, 26), CFrame.new(offset + Vector3.new(12, 8, 27)), Color3.fromRGB(40, 42, 46), Enum.Material.Brick)
	createPart(platformFolder, "PlatformWallSouth", Vector3.new(1.5, 16, 26), CFrame.new(offset + Vector3.new(12, 8, -27)), Color3.fromRGB(40, 42, 46), Enum.Material.Brick)
	createPart(platformFolder, "PlatformPortalHeader", Vector3.new(1.5, 4, 28), CFrame.new(offset + Vector3.new(12, 14, 0)), Color3.fromRGB(40, 42, 46), Enum.Material.Brick)
	createPart(platformFolder, "PlatformRoof", Vector3.new(26, 1.5, 84), CFrame.new(offset + Vector3.new(0, 16, 0)), Color3.fromRGB(30, 32, 35), Enum.Material.Metal)

	createSign(platformFolder, "<- TO TRAIN / TO CONCOURSE ->", CFrame.new(offset + Vector3.new(11.2, 13, 0)), Vector3.new(0.4, 2.5, 20), Enum.NormalId.Left)

	-- =========================================================================
	-- 2. AREA: MAIN CONCOURSE (Central Transit Navigation Hub)
	-- =========================================================================
	local concourseFolder = Instance.new("Folder")
	concourseFolder.Name = "Concourse"
	concourseFolder.Parent = station

	-- Main concourse floor
	createPart(
		concourseFolder,
		"ConcourseFloor",
		Vector3.new(60, 2, 70),
		CFrame.new(offset + Vector3.new(42, 0, 0)),
		Color3.fromRGB(42, 44, 48),
		Enum.Material.Concrete
	)

	-- High arched ceiling
	createPart(concourseFolder, "ConcourseRoof", Vector3.new(64, 2, 74), CFrame.new(offset + Vector3.new(42, 20, 0)), Color3.fromRGB(28, 30, 34), Enum.Material.Metal)

	-- Concourse Boundary Walls
	createPart(concourseFolder, "NorthWall", Vector3.new(60, 20, 2), CFrame.new(offset + Vector3.new(42, 10, 35)), Color3.fromRGB(36, 38, 42), Enum.Material.Brick)
	createPart(concourseFolder, "SouthWall", Vector3.new(60, 20, 2), CFrame.new(offset + Vector3.new(42, 10, -35)), Color3.fromRGB(36, 38, 42), Enum.Material.Brick)

	-- Center Architectural Pillars
	for x = 25, 55, 15 do
		for z = -18, 18, 36 do
			createPart(concourseFolder, "ConcoursePillar", Vector3.new(2.5, 20, 2.5), CFrame.new(offset + Vector3.new(x, 10, z)), Color3.fromRGB(60, 65, 70), Enum.Material.Concrete)
		end
	end

	-- Directional Wayfinding Sign in Concourse Center
	createSign(concourseFolder, "MAINTENANCE [EAST] | CONTROL ROOM [NORTH]", CFrame.new(offset + Vector3.new(42, 14, 0)), Vector3.new(18, 2.5, 0.4), Enum.NormalId.Front)

	-- Concourse Lighting (Dim yellow lamps)
	for x = 25, 55, 15 do
		local lamp = createPart(concourseFolder, "CeilingLamp", Vector3.new(1.2, 0.4, 1.2), CFrame.new(offset + Vector3.new(x, 19, 0)), Color3.fromRGB(240, 210, 130), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Brightness = 0.75
		light.Color = Color3.fromRGB(220, 180, 110)
		light.Range = 26
		light.Shadows = true
		light.Parent = lamp
	end

	-- =========================================================================
	-- 3. AREA: MAINTENANCE ROOM (Power Breakers & Fuse Racks)
	-- =========================================================================
	local maintenanceFolder = Instance.new("Folder")
	maintenanceFolder.Name = "Maintenance"
	maintenanceFolder.Parent = station

	-- Maintenance Floor
	createPart(
		maintenanceFolder,
		"MaintenanceFloor",
		Vector3.new(35, 2, 35),
		CFrame.new(offset + Vector3.new(88, 0, 18)),
		Color3.fromRGB(48, 50, 52),
		Enum.Material.Concrete
	)
	createPart(maintenanceFolder, "MaintRoof", Vector3.new(37, 1.5, 37), CFrame.new(offset + Vector3.new(88, 14, 18)), Color3.fromRGB(30, 32, 35), Enum.Material.Metal)
	createPart(maintenanceFolder, "MaintEastWall", Vector3.new(2, 14, 35), CFrame.new(offset + Vector3.new(105, 7, 18)), Color3.fromRGB(38, 40, 44), Enum.Material.Brick)
	createPart(maintenanceFolder, "MaintNorthWall", Vector3.new(35, 14, 2), CFrame.new(offset + Vector3.new(88, 7, 35)), Color3.fromRGB(38, 40, 44), Enum.Material.Brick)

	createSign(maintenanceFolder, "MAINTENANCE & POWER GRID", CFrame.new(offset + Vector3.new(88, 11, 33.8)), Vector3.new(16, 2.5, 0.4), Enum.NormalId.Back)

	-- Main Electrical Breaker Board Frame
	local breakerBoard = createPart(
		maintenanceFolder,
		"BreakerBoard",
		Vector3.new(1.5, 8, 14),
		CFrame.new(offset + Vector3.new(103.5, 5, 18)),
		Color3.fromRGB(30, 32, 36),
		Enum.Material.Metal
	)

	-- 3 Fuse Sockets on Breaker Board
	local socketsFolder = Instance.new("Folder")
	socketsFolder.Name = "Sockets"
	socketsFolder.Parent = breakerBoard

	for i = 1, 3 do
		local zOffset = (i - 2) * 4
		local socketPart = createPart(
			socketsFolder,
			"FuseSocket_" .. tostring(i),
			Vector3.new(0.6, 2.2, 2.2),
			CFrame.new(offset + Vector3.new(102.5, 5, 18 + zOffset)),
			Color3.fromRGB(60, 65, 70),
			Enum.Material.Metal
		)

		local _indicator = createPart(
			socketPart,
			"IndicatorLight",
			Vector3.new(0.4, 0.4, 0.4),
			CFrame.new(offset + Vector3.new(102.1, 6.4, 18 + zOffset)),
			Color3.fromRGB(220, 40, 40),
			Enum.Material.Neon
		)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "InstallFusePrompt"
		prompt.ActionText = "Install Fuse"
		prompt.ObjectText = "Breaker Socket #" .. tostring(i)
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0.5
		prompt.Parent = socketPart
	end

	-- =========================================================================
	-- 4. AREA: CONTROL ROOM (Communication & Signaling Terminals)
	-- =========================================================================
	local controlFolder = Instance.new("Folder")
	controlFolder.Name = "ControlRoom"
	controlFolder.Parent = station

	-- Control Room Floor
	createPart(
		controlFolder,
		"ControlFloor",
		Vector3.new(35, 2, 35),
		CFrame.new(offset + Vector3.new(88, 0, -18)),
		Color3.fromRGB(44, 46, 50),
		Enum.Material.Concrete
	)
	createPart(controlFolder, "ControlRoof", Vector3.new(37, 1.5, 37), CFrame.new(offset + Vector3.new(88, 14, -18)), Color3.fromRGB(30, 32, 35), Enum.Material.Metal)
	createPart(controlFolder, "ControlEastWall", Vector3.new(2, 14, 35), CFrame.new(offset + Vector3.new(105, 7, -18)), Color3.fromRGB(38, 40, 44), Enum.Material.Brick)
	createPart(controlFolder, "ControlSouthWall", Vector3.new(35, 14, 2), CFrame.new(offset + Vector3.new(88, 7, -35)), Color3.fromRGB(38, 40, 44), Enum.Material.Brick)

	createSign(controlFolder, "COMMUNICATIONS & SIGNAL CONTROL", CFrame.new(offset + Vector3.new(88, 11, -33.8)), Vector3.new(18, 2.5, 0.4), Enum.NormalId.Front)

	-- 3 Signal Communication Terminal Consoles
	local terminalsFolder = Instance.new("Folder")
	terminalsFolder.Name = "Terminals"
	terminalsFolder.Parent = controlFolder

	for i = 1, 3 do
		local zOffset = (i - 2) * 8
		local desk = createPart(
			terminalsFolder,
			"TerminalDesk_" .. tostring(i),
			Vector3.new(3, 3, 5),
			CFrame.new(offset + Vector3.new(94, 2.5, -18 + zOffset)),
			Color3.fromRGB(35, 38, 42),
			Enum.Material.Metal
		)

		local monitor = createPart(
			desk,
			"MonitorScreen",
			Vector3.new(0.4, 2, 3),
			CFrame.new(offset + Vector3.new(94, 5, -18 + zOffset)),
			Color3.fromRGB(180, 40, 40),
			Enum.Material.Neon
		)

		local screenGui = Instance.new("SurfaceGui")
		screenGui.Face = Enum.NormalId.Left
		screenGui.CanvasSize = Vector2.new(300, 200)
		screenGui.Parent = monitor

		local screenLabel = Instance.new("TextLabel")
		screenLabel.Name = "TerminalStatus"
		screenLabel.Size = UDim2.fromScale(1, 1)
		screenLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		screenLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
		screenLabel.Font = Enum.Font.Code
		screenLabel.TextSize = 22
		screenLabel.Text = string.format("[RELAY #%d]\nOFFLINE\nREBOOT REQ", i)
		screenLabel.Parent = screenGui

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RebootSignalPrompt"
		prompt.ActionText = "Reboot Signal Relay"
		prompt.ObjectText = "Terminal #" .. tostring(i)
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 1.2
		prompt.Parent = desk
	end

	-- =========================================================================
	-- 5. AREA: CARGO STORAGE (Lost Cargo Crates & Heavy Shelving)
	-- =========================================================================
	local cargoFolder = Instance.new("Folder")
	cargoFolder.Name = "CargoStorage"
	cargoFolder.Parent = station

	-- Cargo Floor
	createPart(
		cargoFolder,
		"CargoFloor",
		Vector3.new(40, 2, 40),
		CFrame.new(offset + Vector3.new(42, 0, 55)),
		Color3.fromRGB(46, 44, 42),
		Enum.Material.Concrete
	)
	createPart(cargoFolder, "CargoRoof", Vector3.new(42, 1.5, 42), CFrame.new(offset + Vector3.new(42, 14, 55)), Color3.fromRGB(30, 32, 35), Enum.Material.Metal)
	createPart(cargoFolder, "CargoNorthWall", Vector3.new(40, 14, 2), CFrame.new(offset + Vector3.new(42, 7, 75)), Color3.fromRGB(38, 40, 44), Enum.Material.Brick)
	createPart(cargoFolder, "CargoEastWall", Vector3.new(2, 14, 40), CFrame.new(offset + Vector3.new(62, 7, 55)), Color3.fromRGB(38, 40, 44), Enum.Material.Brick)

	createSign(cargoFolder, "SECURED CARGO STORAGE", CFrame.new(offset + Vector3.new(42, 11, 73.8)), Vector3.new(16, 2.5, 0.4), Enum.NormalId.Back)

	-- Industrial Shelves in Cargo Area
	for z = 45, 65, 10 do
		createPart(cargoFolder, "CargoShelf", Vector3.new(12, 10, 3), CFrame.new(offset + Vector3.new(32, 6, z)), Color3.fromRGB(50, 52, 58), Enum.Material.Metal)
	end

	-- =========================================================================
	-- 6. AREA: UNDERGROUND TUNNEL (Subterranean High-Risk Route)
	-- =========================================================================
	local tunnelFolder = Instance.new("Folder")
	tunnelFolder.Name = "UndergroundTunnel"
	tunnelFolder.Parent = station

	-- Tunnel Floor running south from concourse
	createPart(
		tunnelFolder,
		"TunnelFloor",
		Vector3.new(18, 2, 60),
		CFrame.new(offset + Vector3.new(42, -4, -65)),
		Color3.fromRGB(34, 36, 40),
		Enum.Material.Slate
	)
	createPart(tunnelFolder, "TunnelCeiling", Vector3.new(20, 1.5, 62), CFrame.new(offset + Vector3.new(42, 4, -65)), Color3.fromRGB(25, 26, 30), Enum.Material.Concrete)
	createPart(tunnelFolder, "TunnelWestWall", Vector3.new(2, 9, 60), CFrame.new(offset + Vector3.new(32, 0, -65)), Color3.fromRGB(32, 34, 38), Enum.Material.Slate)
	createPart(tunnelFolder, "TunnelEastWall", Vector3.new(2, 9, 60), CFrame.new(offset + Vector3.new(52, 0, -65)), Color3.fromRGB(32, 34, 38), Enum.Material.Slate)

	-- Tunnel Emergency Red Warning Lights
	for z = -45, -85, -15 do
		local lamp = createPart(tunnelFolder, "EmergencyRedLamp", Vector3.new(0.8, 0.8, 0.8), CFrame.new(offset + Vector3.new(42, 3.2, z)), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Brightness = 0.9
		light.Color = Color3.fromRGB(255, 30, 30)
		light.Range = 18
		light.Shadows = true
		light.Parent = lamp
	end

	currentStation = station
	log:Info("Station architecture assembled for " .. stationDef.Name .. " with all 6 required zones.", { StationId = targetId })
	return station
end

function StationService.GetSpawnPosition(): Vector3
	local offset = GameConfig.World.ActiveStationOffset
	return offset + Vector3.new(0, 4, 10)
end

function StationService.IsInsideExtractionZone(position: Vector3): boolean
	local station = currentStation
	if not station or not station.Parent then
		local world = Workspace:FindFirstChild("World")
		local runtime = world and world:FindFirstChild("Runtime")
		station = runtime and runtime:FindFirstChild("ActiveStation") :: Model?
	end
	if not station then return false end
	local platform = station:FindFirstChild("Platform")
	if not platform then return false end
	local zone = platform:FindFirstChild("ExtractionZone") :: BasePart?
	if not zone then return false end

	local localPos = zone.CFrame:PointToObjectSpace(position)
	local halfSize = zone.Size / 2
	return math.abs(localPos.X) <= halfSize.X
		and math.abs(localPos.Y) <= halfSize.Y + 2
		and math.abs(localPos.Z) <= halfSize.Z
end

function StationService.UnloadStation()
	if currentStation then
		log:Info("Unloading Station 001 and cleaning all runtime instances...")
		currentStation:Destroy()
		currentStation = nil
	end

	local world = Workspace:FindFirstChild("World")
	if world then
		local runtime = world:FindFirstChild("Runtime")
		if runtime then
			runtime:ClearAllChildren()
		end
	end
end

return StationService
