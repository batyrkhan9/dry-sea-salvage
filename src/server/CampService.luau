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
local RelicUtil = require(ReplicatedStorage.Shared.RelicUtil)
local DataService = require(script.Parent.DataService)
local PlacementService = require(script.Parent.PlacementService)
local PlayerDataSchema = require(script.Parent.PlayerDataSchema)

type CampRelic = PlayerDataSchema.CampRelic

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

-- Called with the player whenever they pick a relic back up by clicking
-- its crate. The entry script uses this to tell that player's client the
-- inventory changed - without it the relics panel goes stale, because
-- crate clicks never pass through a client-initiated remote.
local pickupListener: ((player: Player) -> ())? = nil

function CampService.setPickupListener(listener: (player: Player) -> ())
	pickupListener = listener
end

-- Called with (clicker, plotOwner) when anyone clicks a camp sign.
-- init.server routes this into DuelService. Declared BEFORE the plot
-- builder below so its click handler captures this local as an upvalue.
local signClickListener: ((clicker: Player, owner: Player) -> ())? = nil

function CampService.setSignClickListener(listener: (clicker: Player, owner: Player) -> ())
	signClickListener = listener
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

	-- FRONT LINE marker: the high-cellZ edge (far side from spawn) is
	-- where the army marches from in duels - row 6 fights first. A neon
	-- strip plus label makes the marching order readable on the board.
	local frontStrip = Instance.new("Part")
	frontStrip.Name = "FrontStrip"
	frontStrip.Anchored = true
	frontStrip.CanCollide = false
	frontStrip.Size = Vector3.new(size, 0.25, 1)
	frontStrip.CFrame = origin * CFrame.new(0, 0.45, size / 2 - 0.5)
	frontStrip.Material = Enum.Material.Neon
	frontStrip.Color = Color3.fromRGB(200, 120, 70)
	frontStrip.Transparency = 0.3
	frontStrip.Parent = model

	local frontBillboard = Instance.new("BillboardGui")
	frontBillboard.Size = UDim2.fromOffset(130, 20)
	frontBillboard.StudsOffset = Vector3.new(0, 1.6, 0)
	frontBillboard.MaxDistance = 90
	frontBillboard.Parent = frontStrip

	local frontLabel = Instance.new("TextLabel")
	frontLabel.Size = UDim2.fromScale(1, 1)
	frontLabel.BackgroundTransparency = 1
	frontLabel.Font = Enum.Font.GothamBold
	frontLabel.TextScaled = true
	frontLabel.TextColor3 = Color3.fromRGB(230, 150, 90)
	frontLabel.TextStrokeTransparency = 0.5
	frontLabel.Text = "FRONT - fights first"
	frontLabel.Parent = frontBillboard

	-- Camp sign at the front edge: names the plot AND is the duel
	-- button - other players click it to challenge this camp.
	local signPost = Instance.new("Part")
	signPost.Name = "SignPost"
	signPost.Anchored = true
	signPost.Size = Vector3.new(0.8, 4, 0.8)
	signPost.CFrame = origin * CFrame.new(0, 2, -size / 2 - 1.5)
	signPost.Material = Enum.Material.Wood
	signPost.Color = POST_WOOD
	signPost.Parent = model

	local sign = Instance.new("Part")
	sign.Name = "SignBoard"
	sign.Anchored = true
	sign.Size = Vector3.new(4.5, 2.2, 0.4)
	sign.CFrame = origin * CFrame.new(0, 4.4, -size / 2 - 1.5)
	sign.Material = Enum.Material.WoodPlanks
	sign.Color = POST_WOOD
	sign.Parent = model

	local signClick = Instance.new("ClickDetector")
	signClick.MaxActivationDistance = 32
	signClick.Parent = sign
	signClick.MouseClick:Connect(function(clicker)
		if signClickListener then
			signClickListener(clicker, player)
		end
	end)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(200, 36)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
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

-- ---------- placed relic visuals ----------

-- World CFrame of a grid cell's center, sitting on the plot floor.
local function cellCFrame(origin: CFrame, cellX: number, cellZ: number): CFrame
	local half = (Config.Camp.gridCells + 1) / 2
	return origin * CFrame.new((cellX - half) * Config.Camp.cellSize, 0.4, (cellZ - half) * Config.Camp.cellSize)
end

-- Placeholder deployed-relic visual: a rarity-colored crate with a name
-- tag. Clicking your own crate picks it back up (returns to inventory).
local function buildRelicVisual(player: Player, plot: Plot, placed: CampRelic)
	-- Guard against double-builds: a placement made in the window
	-- between data load and restorePlacements' next poll would otherwise
	-- get a crate from BOTH paths (showPlacement and the restorer).
	if plot.model:FindFirstChild(("Relic_%d_%d"):format(placed.cellX, placed.cellZ)) then
		return
	end
	local rarityName = RelicUtil.rarityOf(placed.relicName) or "?"
	local size = Config.Camp.cellSize * 0.65

	local crate = Instance.new("Part")
	crate.Name = ("Relic_%d_%d"):format(placed.cellX, placed.cellZ)
	crate.Anchored = true
	crate.Size = Vector3.new(size, size, size)
	crate.CFrame = cellCFrame(plot.origin, placed.cellX, placed.cellZ) * CFrame.new(0, size / 2, 0)
	crate.Material = Enum.Material.Metal
	crate.Color = RelicUtil.rarityColor(rarityName)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(140, 22)
	billboard.StudsOffset = Vector3.new(0, size / 2 + 1.2, 0)
	billboard.MaxDistance = 80
	billboard.Parent = crate

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(240, 230, 210)
	label.TextStrokeTransparency = 0.5
	label.Text = placed.relicName
	label.Parent = billboard

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 24
	click.Parent = crate
	click.MouseClick:Connect(function(clicker)
		-- Only the plot owner can pick their relics back up.
		if clicker ~= player then
			return
		end
		if PlacementService.tryRemove(player, placed.cellX, placed.cellZ) ~= nil then
			crate:Destroy()
			if pickupListener then
				pickupListener(player)
			end
		end
	end)

	-- Parented to the plot model so releasePlot cleans these up for free.
	crate.Parent = plot.model
end

-- Builds the visual for a fresh placement (called after tryPlace).
function CampService.showPlacement(player: Player, placed: CampRelic)
	local plot = plotsByUserId[player.UserId]
	if plot ~= nil then
		buildRelicVisual(player, plot, placed)
	end
end

-- Rebuild every saved placement once the player's data arrives. Data
-- loads async (DataStore call), so poll briefly rather than racing it.
local function restorePlacements(player: Player, plot: Plot)
	local waited = 0
	while DataService.get(player) == nil do
		if player.Parent == nil or waited > 30 then
			return
		end
		waited += task.wait(0.5)
	end
	if plotsByUserId[player.UserId] ~= plot then
		return -- player left and rejoined while we waited
	end
	local data = DataService.get(player)
	if data == nil then
		return
	end
	for _, placed in data.campRelics do
		buildRelicVisual(player, plot, placed)
	end
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

	local plot: Plot = {
		index = index,
		origin = origin,
		model = model,
	}
	plotsByUserId[player.UserId] = plot
	task.spawn(restorePlacements, player, plot)
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
