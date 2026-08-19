--[[
	MapBuilder - scatters part-built shipwrecks and debris across the
	seabed at server start, so the world isn't an empty plane.

	Placeholder art, deliberately: real ship models can replace these in
	Studio later. Everything is seeded RNG (Random.new(SEED)), so every
	server builds the IDENTICAL layout - it reads as a designed map, and
	a good wreck near spawn stays there for every player, every visit.

	These are visual constants, not gameplay tuning, so they live here
	rather than in shared Config.
]]

local MapBuilder = {}

local SEED = 1960 -- any fixed number works; changing it reshuffles the map
local WRECK_COUNT = 14
local DEBRIS_COUNT = 40
local MIN_RADIUS = 70 -- keep a clear area around spawn
local MAX_RADIUS = 450
local GROUND_Y = 0 -- top surface of the baseplate

local RUST_COLORS = {
	Color3.fromRGB(124, 78, 46),
	Color3.fromRGB(105, 64, 40),
	Color3.fromRGB(140, 94, 56),
	Color3.fromRGB(90, 60, 45),
}

local rng = Random.new(SEED)

local function makePart(props: { [string]: any }, parent: Instance?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CastShadow = true
	part.Material = Enum.Material.CorrodedMetal
	part.Color = RUST_COLORS[rng:NextInteger(1, #RUST_COLORS)]
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

-- One wreck: a hull box listing to one side, a bow wedge, a couple of
-- masts, and rib planks - sunk partway into the sand.
local function buildWreck(position: Vector3)
	local model = Instance.new("Model")
	model.Name = "Wreck"

	local length = rng:NextNumber(24, 46)
	local width = length * rng:NextNumber(0.22, 0.3)
	local height = length * rng:NextNumber(0.18, 0.26)
	-- List (side tilt) + slight pitch, like it settled into the seabed.
	local heading = rng:NextNumber(0, math.pi * 2)
	local list = rng:NextNumber(0.15, 0.5) * (rng:NextInteger(0, 1) == 0 and 1 or -1)
	local pitch = rng:NextNumber(-0.08, 0.08)
	-- Sink so between a third and two thirds of the hull is buried.
	local sink = height * rng:NextNumber(0.33, 0.66)

	local base = CFrame.new(position.X, GROUND_Y - sink + height / 2, position.Z)
		* CFrame.Angles(0, heading, 0)
		* CFrame.Angles(pitch, 0, list)

	local hull = makePart({
		Name = "Hull",
		Size = Vector3.new(width, height, length),
		CFrame = base,
	}, model)

	makePart({
		Name = "Bow",
		Size = Vector3.new(width, height, width),
		CFrame = base * CFrame.new(0, 0, -(length / 2 + width / 2 - 0.5)) * CFrame.Angles(0, math.pi / 4, 0),
	}, model)

	for i = 1, rng:NextInteger(1, 2) do
		local mastHeight = length * rng:NextNumber(0.5, 0.8)
		makePart({
			Name = "Mast",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(mastHeight, 1.2, 1.2),
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(86, 66, 48),
			-- Cylinders lie along X, so roll 90° to stand it up, then
			-- lean it with the ship's list plus its own random sag.
			CFrame = base
				* CFrame.new(0, height / 2 + mastHeight / 2 - 1, (i - 1.5) * length * 0.4)
				* CFrame.Angles(0, 0, math.pi / 2 + rng:NextNumber(-0.15, 0.15)),
		}, model)
	end

	for _ = 1, rng:NextInteger(2, 4) do
		makePart({
			Name = "Rib",
			Size = Vector3.new(0.8, height * rng:NextNumber(0.9, 1.4), 2),
			CFrame = base * CFrame.new(
				(rng:NextInteger(0, 1) == 0 and 1 or -1) * width / 2,
				rng:NextNumber(0, height * 0.3),
				rng:NextNumber(-length / 2, length / 2)
			) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.3, 0.3)),
		}, model)
	end

	model.PrimaryPart = hull
	return model
end

-- Small half-buried scrap: plates, crates, pipe bits.
local function buildDebris(position: Vector3)
	local size = Vector3.new(rng:NextNumber(1.5, 5), rng:NextNumber(0.8, 3), rng:NextNumber(1.5, 5))
	return makePart({
		Name = "Debris",
		Size = size,
		CFrame = CFrame.new(position.X, GROUND_Y - size.Y * rng:NextNumber(0.2, 0.5) + size.Y / 2, position.Z)
			* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.4, 0.4)),
	})
end

-- Ring placement: random angle + radius between MIN and MAX, so nothing
-- lands on spawn but wrecks surround the player in every direction.
local function ringPosition(): Vector3
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(MIN_RADIUS, MAX_RADIUS)
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

function MapBuilder.build()
	local folder = Instance.new("Folder")
	folder.Name = "GeneratedMap"

	for _ = 1, WRECK_COUNT do
		buildWreck(ringPosition()).Parent = folder
	end
	for _ = 1, DEBRIS_COUNT do
		buildDebris(ringPosition()).Parent = folder
	end

	folder.Parent = workspace
end

return MapBuilder
