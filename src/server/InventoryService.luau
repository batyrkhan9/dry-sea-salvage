--[[
	InventoryService — owns what "having relics" means.
	It never touches DataStores directly; it just mutates the cached data
	table that DataService loads and saves.
]]

local DataService = require(script.Parent.DataService)

local InventoryService = {}

-- Adds one copy of a relic. Returns the new count, or nil if the player's
-- data isn't loaded yet (roll results before load simply aren't recorded —
-- the roll cooldown makes this window tiny in practice).
function InventoryService.addRelic(player: Player, relicName: string): number?
	local data = DataService.get(player)
	if data == nil then
		warn(("InventoryService: %s rolled before their data loaded; relic not saved"):format(player.Name))
		return nil
	end
	local newCount = (data.inventory[relicName] or 0) + 1
	data.inventory[relicName] = newCount
	return newCount
end

-- Read-only view for UI / merge logic later. Callers must not mutate it.
function InventoryService.getInventory(player: Player): { [string]: number }?
	local data = DataService.get(player)
	return data and data.inventory
end

return InventoryService
