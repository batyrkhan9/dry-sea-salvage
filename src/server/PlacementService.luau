--[[
	PlacementService - the rules for deploying relics onto camp plots.

	A relic is either in the inventory or deployed, never both: placing
	consumes one inventory copy, removing returns it. This keeps merge
	math honest (deployed copies can't be merged) and gives placement
	real weight.

	Like MergeService, tryPlace takes raw client input and validates
	everything before mutating. CampService owns the visuals; this module
	owns the data.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RelicUtil = require(ReplicatedStorage.Shared.RelicUtil)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local PlayerDataSchema = require(script.Parent.PlayerDataSchema)

local PlacementService = {}

export type CampRelic = PlayerDataSchema.CampRelic

local function cellTaken(campRelics: { CampRelic }, cellX: number, cellZ: number): boolean
	for _, placed in campRelics do
		if placed.cellX == cellX and placed.cellZ == cellZ then
			return true
		end
	end
	return false
end

-- First free cell scanning row by row, or nil when the plot is full.
local function firstFreeCell(campRelics: { CampRelic }): (number?, number?)
	for z = 1, Config.Camp.gridCells do
		for x = 1, Config.Camp.gridCells do
			if not cellTaken(campRelics, x, z) then
				return x, z
			end
		end
	end
	return nil, nil
end

local function isValidCell(value: unknown): boolean
	return typeof(value) == "number" and value == math.floor(value :: number)
end

-- Places one copy of `relicName` on the player's plot. Cell may be nil
-- (server picks the first free one) - the cell-picking UI arrives later.
-- Returns the placement on success, or (nil, reason) for server logs.
function PlacementService.tryPlace(
	player: Player,
	relicName: unknown,
	cellX: unknown,
	cellZ: unknown
): (CampRelic?, string?)
	if typeof(relicName) ~= "string" then
		return nil, "relic name is not a string"
	end
	if RelicUtil.rarityOf(relicName) == nil then
		return nil, "unknown relic: " .. relicName
	end

	local data = DataService.get(player)
	if data == nil then
		return nil, "player data not loaded"
	end

	local x, z
	if cellX == nil and cellZ == nil then
		x, z = firstFreeCell(data.campRelics)
		if x == nil then
			return nil, "plot is full"
		end
	else
		if not (isValidCell(cellX) and isValidCell(cellZ)) then
			return nil, "cell is not an integer pair"
		end
		x, z = cellX :: number, cellZ :: number
		if x < 1 or x > Config.Camp.gridCells or z < 1 or z > Config.Camp.gridCells then
			return nil, "cell out of bounds"
		end
		if cellTaken(data.campRelics, x, z) then
			return nil, "cell already occupied"
		end
	end

	-- Deploy budget: the army's total cost is hard-capped for everyone.
	local def = RelicUtil.defOf(relicName) :: any
	if RelicUtil.armyCost(data.campRelics) + def.cost > Config.Duel.budget then
		return nil, "over deploy budget"
	end

	-- Consume the inventory copy FIRST; a failure here costs nothing.
	if not InventoryService.removeRelic(player, relicName, 1) then
		return nil, "relic not in inventory"
	end

	local placed: CampRelic = { relicName = relicName, cellX = x :: number, cellZ = z :: number }
	table.insert(data.campRelics, placed)
	return placed
end

-- The player's current placements (for the placement UI). Remotes copy
-- tables on serialize, so handing out the live list is safe at the edge.
function PlacementService.getCampRelics(player: Player): { CampRelic }
	local data = DataService.get(player)
	return if data ~= nil then data.campRelics else {}
end

-- Removes whatever is at the cell and returns it to the inventory.
-- Returns the removed placement, or nil if the cell was empty.
function PlacementService.tryRemove(player: Player, cellX: number, cellZ: number): CampRelic?
	local data = DataService.get(player)
	if data == nil then
		return nil
	end
	for i, placed in data.campRelics do
		if placed.cellX == cellX and placed.cellZ == cellZ then
			table.remove(data.campRelics, i)
			InventoryService.addRelic(player, placed.relicName)
			return placed
		end
	end
	return nil
end

return PlacementService
