--[[
	PlayerDataSchema - the SHAPE of a player's save and how old saves get
	upgraded to it. Pure data logic, no Roblox APIs, so it's unit-testable
	outside Studio. DataService owns WHEN to load/save; this owns WHAT.
]]

local PlayerDataSchema = {}

-- Bump SCHEMA_VERSION when the data shape changes in a way reconcile()'s
-- fill-in-missing-fields step can't handle on its own; the loaded value
-- tells future migration code exactly which shape it's holding.
PlayerDataSchema.SCHEMA_VERSION = 1

export type PlayerData = {
	schemaVersion: number,
	inventory: { [string]: number }, -- relic name -> how many owned right now
	discovered: { [string]: boolean }, -- relic name -> ever found (survives merging away)
}

function PlayerDataSchema.defaultData(): PlayerData
	-- Built fresh each call so two players never share the same table.
	return {
		schemaVersion = PlayerDataSchema.SCHEMA_VERSION,
		inventory = {},
		discovered = {},
	}
end

-- Fills in any top-level fields that exist in the default shape but are
-- missing from stored data. This is how old saves survive new features:
-- data saved before `discovered` existed gets an empty set added here
-- instead of crashing code that expects it.
function PlayerDataSchema.reconcile(stored: any): PlayerData
	-- Saves written before schemaVersion existed are by definition the
	-- first schema. Stamp that BEFORE the generic fill-in below, so an old
	-- save can never be labeled with a newer version than its real shape
	-- (which would make future migration code skip it).
	if stored.schemaVersion == nil then
		stored.schemaVersion = 1
	end
	-- When SCHEMA_VERSION grows past 1, step-by-step migrations run here:
	-- if stored.schemaVersion == 1 then ... ; stored.schemaVersion = 2 ; end

	local default = PlayerDataSchema.defaultData()
	for key, defaultValue in default :: any do
		if stored[key] == nil then
			stored[key] = defaultValue
		end
	end
	-- Owning a relic implies having discovered it. This also migrates
	-- saves that predate `discovered` - their index starts from what
	-- they currently hold instead of empty.
	for relicName in stored.inventory do
		stored.discovered[relicName] = true
	end
	return stored
end

return PlayerDataSchema
