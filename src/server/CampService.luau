--[[
	CampService - assigns each player a camp plot for the session and
	builds its visual footprint (floor slab, corner posts, name sign).

	Plots are session-scoped in v2 step 1: you get one on join, it's freed
	on leave. What's PLACED on the plot will persist in the save (step 2);
	the plot location itself doesn't need to, since it's just "a spot in
	this server".

	Plot indices are handed out lowest-free-first, arranged in a ring
	around spawn, inside the wreck-free zone MapBuilder leaves open.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CampService = {}

local GROUND_Y = 0 -- top surface of the baseplate, matches MapBuilder

local SAND_FLOOR = Color3.fromRGB(214, 186, 132)
local POST_WOOD = Color3.fromRGB(96, 74, 52)

type Plot = {
	index: number,
	origin: CFrame, -- center of the plot floor, facing spawn
	model: Model,
}

local plotsByUserId: { [number]: Plot } = {}
local takenIndices: { [number]: boolean } = {}

local function lowestFreeIndex(): number?
	for i = 1, Config.Camp.plotCount do
		if not takenIndices[i] then
			return i
		end
	end
	return nil
end

-- Center CFrame for plot slot i, positioned on the ring and rotated so
-- the plot's "front" looks back toward spawn.
local function plotOrigin(index: number): CFrame
	local angle = (index - 1) / Config.Camp.plotCount * math.pi * 2
	local x = math.cos(angle) * Config.Camp.plotRingRadius
	local z = math.sin(angle) * Config.Camp.plotRingRadius
	return CFrame.lookAt(Vector3.new(x, GROUND_Y, z), Vector3.new(0, GROUND_Y, 0))
end

local function buildPlotModel(player: Player, origin: CFrame): Model
	local size = Config.Camp.plotSize
	local model = Instance.new("Model")
	model.Name = ("Plot_%s"):format(player.Name)

	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(size, 0.4, size)
	floor.CFrame = origin * CFrame.new(0, 0.2, 0)
	floor.Material = Enum.Material.WoodPlanks
	floor.Color = SAND_FLOOR
	floor.Parent = model

	-- Corner posts mark the plot bounds without walling it off.
	for _, corner in { Vector2.new(-1, -1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(1, 1) } do
		local post = Instance.new("Part")
		post.Name = "Post"
		post.Anchored = true
		post.Size = Vector3.new(1, 5, 1)
		post.CFrame = origin * CFrame.new(corner.X * (size / 2 - 0.5), 2.5, corner.Y * (size / 2 - 0.5))
		post.Material = Enum.Material.Wood
		post.Color = POST_WOOD
		post.Parent = model
	end

	-- Floating name sign over the front edge so plots are recognizable.
	local sign = Instance.new("Part")
	sign.Name = "SignAnchor"
	sign.Anchored = true
	sign.Transparency = 1
	sign.CanCollide = false
	sign.Size = Vector3.new(1, 1, 1)
	sign.CFrame = origin * CFrame.new(0, 7, -size / 2)
	sign.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(200, 36)
	billboard.MaxDistance = 200
	billboard.AlwaysOnTop = false
	billboard.Parent = sign

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.fromRGB(240, 230, 210)
	nameLabel.TextStrokeTransparency = 0.5
	nameLabel.Text = ("%s's Camp"):format(player.Name)
	nameLabel.Parent = billboard

	model.PrimaryPart = floor
	return model
end

-- The plot's center CFrame, for placement math later. Nil if the player
-- somehow has no plot (server past plotCount players).
function CampService.getPlotOrigin(player: Player): CFrame?
	local plot = plotsByUserId[player.UserId]
	return plot and plot.origin
end

local function assignPlot(player: Player)
	local index = lowestFreeIndex()
	if index == nil then
		-- More players than plots: playable, just no camp. Roblox server
		-- size should be set to plotCount so this stays theoretical.
		warn(("CampService: no free plot for %s"):format(player.Name))
		return
	end
	takenIndices[index] = true

	local origin = plotOrigin(index)
	local model = buildPlotModel(player, origin)
	model.Parent = workspace

	plotsByUserId[player.UserId] = {
		index = index,
		origin = origin,
		model = model,
	}
end

local function releasePlot(player: Player)
	local plot = plotsByUserId[player.UserId]
	if plot == nil then
		return
	end
	plot.model:Destroy()
	takenIndices[plot.index] = nil
	plotsByUserId[player.UserId] = nil
end

Players.PlayerAdded:Connect(assignPlot)
for _, player in Players:GetPlayers() do
	task.spawn(assignPlot, player)
end
Players.PlayerRemoving:Connect(releasePlot)

return CampService
