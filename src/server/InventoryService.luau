--[[
	InventoryService - owns what "having relics" means.
	It never touches DataStores directly; it just mutates the cached data
	table that DataService loads and saves.
]]

local DataService = require(script.Parent.DataService)

local InventoryService = {}

-- Adds one copy of a relic. Returns the new count, or nil if the player's
-- data isn't loaded yet (roll results before load simply aren't recorded -
-- the roll cooldown makes this window tiny in practice).
function InventoryService.addRelic(player: Player, relicName: string): number?
	local data = DataService.get(player)
	if data == nil then
		warn(("InventoryService: %s rolled before their data loaded; relic not saved"):format(player.Name))
		return nil
	end
	local newCount = (data.inventory[relicName] or 0) + 1
	data.inventory[relicName] = newCount
	-- Permanent record for the collection index - never un-set, even if
	-- every copy is later merged away.
	data.discovered[relicName] = true
	return newCount
end

-- Set of every relic the player has ever found (for the collection index).
function InventoryService.getDiscovered(player: Player): { [string]: boolean }?
	local data = DataService.get(player)
	return data and data.discovered
end

-- Removes `amount` copies of a relic. Fails (returns false) if the player
-- doesn't own that many - it never lets a count go negative.
function InventoryService.removeRelic(player: Player, relicName: string, amount: number): boolean
	local data = DataService.get(player)
	if data == nil then
		return false
	end
	local owned = data.inventory[relicName] or 0
	if owned < amount then
		return false
	end
	local remaining = owned - amount
	-- Store nil instead of 0 so the inventory table only ever contains
	-- relics the player actually owns.
	data.inventory[relicName] = if remaining > 0 then remaining else nil
	return true
end

-- Read-only view for UI / merge logic later. Callers must not mutate it.
function InventoryService.getInventory(player: Player): { [string]: number }?
	local data = DataService.get(player)
	return data and data.inventory
end

return InventoryService
