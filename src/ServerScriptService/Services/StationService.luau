--!strict
-- StationService.luau
-- Authoritative level lifecycle manager for Station 001 and runtime cleanup

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local StationConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("StationConfig"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("Logger"))
local log = Logger.new("StationService")

local currentStation: Model? = nil

local StationService = {}

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

function StationService.Init()
	log:Info("Initializing StationService...")
end

-- Builds or clones Station 001 into Workspace.World.Runtime.ActiveStation
function StationService.LoadStation(stationId: string?): Model
	local targetId = stationId or StationConfig.DefaultStation
	StationService.UnloadStation()

	log:Info("Loading active station into runtime...", { StationId = targetId })

	local world = Workspace:WaitForChild("World")
	local runtime = world:WaitForChild("Runtime")

	local stationModel = Instance.new("Model")
	stationModel.Name = "ActiveStation"
	stationModel.Parent = runtime

	local stationOffset = GameConfig.World.ActiveStationOffset

	-- 1. Arrival & Extraction Platform
	local platformFolder = Instance.new("Folder")
	platformFolder.Name = "Platform"
	platformFolder.Parent = stationModel

	local platformDeck = createPart(
		platformFolder,
		"ExtractionDeck",
		Vector3.new(24, 2, 70),
		CFrame.new(stationOffset + Vector3.new(0, 0, 0)),
		Color3.fromRGB(50, 52, 58),
		Enum.Material.Concrete
	)
	stationModel.PrimaryPart = platformDeck

	-- Extraction Area Marker / Zone
	local extractionZone = createPart(
		platformFolder,
		"ExtractionZone",
		Vector3.new(20, 8, 24),
		CFrame.new(stationOffset + Vector3.new(0, 4, -18)),
		Color3.fromRGB(50, 200, 100),
		Enum.Material.ForceField
	)
	extractionZone.CanCollide = false
	extractionZone.Transparency = 0.85

	local extractionBill = Instance.new("BillboardGui")
	extractionBill.Name = "ExtractionSign"
	extractionBill.Size = UDim2.fromScale(6, 2)
	extractionBill.AlwaysOnTop = true
	extractionBill.Adornee = extractionZone
	extractionBill.Parent = extractionZone

	local extractionLabel = Instance.new("TextLabel")
	extractionLabel.Size = UDim2.fromScale(1, 1)
	extractionLabel.BackgroundTransparency = 1
	extractionLabel.TextColor3 = Color3.fromRGB(80, 255, 120)
	extractionLabel.Font = Enum.Font.GothamBold
	extractionLabel.TextSize = 22
	extractionLabel.Text = "EXTRACTION TRAIN DOOR"
	extractionLabel.Parent = extractionBill

	-- 2. Station Concourse & Corridors
	local concourseFolder = Instance.new("Folder")
	concourseFolder.Name = "Concourse"
	concourseFolder.Parent = stationModel

	createPart(
		concourseFolder,
		"ConcourseFloor",
		Vector3.new(50, 2, 60),
		CFrame.new(stationOffset + Vector3.new(35, 0, 0)),
		Color3.fromRGB(40, 42, 45),
		Enum.Material.Concrete
	)

	-- Concourse walls & roof
	createPart(concourseFolder, "NorthWall", Vector3.new(50, 14, 2), CFrame.new(stationOffset + Vector3.new(35, 7, 30)), Color3.fromRGB(35, 38, 40), Enum.Material.Brick)
	createPart(concourseFolder, "SouthWall", Vector3.new(50, 14, 2), CFrame.new(stationOffset + Vector3.new(35, 7, -30)), Color3.fromRGB(35, 38, 40), Enum.Material.Brick)
	createPart(concourseFolder, "EastWall", Vector3.new(2, 14, 60), CFrame.new(stationOffset + Vector3.new(60, 7, 0)), Color3.fromRGB(35, 38, 40), Enum.Material.Brick)
	createPart(concourseFolder, "ConcourseCeiling", Vector3.new(52, 2, 62), CFrame.new(stationOffset + Vector3.new(35, 14, 0)), Color3.fromRGB(30, 32, 35), Enum.Material.Metal)

	-- Dim flickering lights
	for z = -15, 15, 15 do
		local lightFixture = createPart(
			concourseFolder,
			"StationLamp",
			Vector3.new(1.2, 0.4, 1.2),
			CFrame.new(stationOffset + Vector3.new(35, 13.5, z)),
			Color3.fromRGB(240, 210, 140),
			Enum.Material.Neon
		)
		local light = Instance.new("PointLight")
		light.Brightness = 0.7
		light.Color = Color3.fromRGB(220, 180, 120)
		light.Range = 24
		light.Shadows = true
		light.Parent = lightFixture
	end

	-- 3. Objective & Loot Spawn Anchors
	local spawnsFolder = Instance.new("Folder")
	spawnsFolder.Name = "ObjectiveAnchors"
	spawnsFolder.Parent = stationModel

	local anchor1 = createPart(spawnsFolder, "Anchor_1", Vector3.new(2, 2, 2), CFrame.new(stationOffset + Vector3.new(25, 2, 18)), Color3.fromRGB(100, 100, 100), Enum.Material.SmoothPlastic)
	anchor1.Transparency = 1; anchor1.CanCollide = false
	local anchor2 = createPart(spawnsFolder, "Anchor_2", Vector3.new(2, 2, 2), CFrame.new(stationOffset + Vector3.new(48, 2, 0)), Color3.fromRGB(100, 100, 100), Enum.Material.SmoothPlastic)
	anchor2.Transparency = 1; anchor2.CanCollide = false
	local anchor3 = createPart(spawnsFolder, "Anchor_3", Vector3.new(2, 2, 2), CFrame.new(stationOffset + Vector3.new(25, 2, -18)), Color3.fromRGB(100, 100, 100), Enum.Material.SmoothPlastic)
	anchor3.Transparency = 1; anchor3.CanCollide = false

	currentStation = stationModel
	log:Info("Station 001 loaded successfully.")
	return stationModel
end

function StationService.GetSpawnPosition(): Vector3
	local stationOffset = GameConfig.World.ActiveStationOffset
	return stationOffset + Vector3.new(0, 4, 10)
end

function StationService.IsInsideExtractionZone(position: Vector3): boolean
	if not currentStation then return false end
	local platform = currentStation:FindFirstChild("Platform")
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
		log:Info("Unloading and cleaning runtime station instances...")
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
