--[[
	DataService — the ONLY module that talks to DataStoreService.

	Lifecycle it manages:
	  - load a player's data when they join (with retries)
	  - keep it cached in memory while they play (other services mutate the cache)
	  - save on leave, on server shutdown, and on an autosave timer

	Everything else (InventoryService etc.) just asks for the cached table
	via DataService.get() and mutates it — saving is this module's problem.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DataService = {}

-- Bump the "_v1" if the data format ever changes incompatibly — old data
-- stays untouched under the old name instead of being misread.
local STORE_NAME = "PlayerData_v1"
local KEY_PREFIX = "player_"
local MAX_RETRIES = 3

local store = DataStoreService:GetDataStore(STORE_NAME)

-- Bump SCHEMA_VERSION when the data shape changes in a way reconcile()'s
-- fill-in-missing-fields step can't handle on its own; the loaded value
-- tells future migration code exactly which shape it's holding.
local SCHEMA_VERSION = 1

export type PlayerData = {
	schemaVersion: number,
	inventory: { [string]: number }, -- relic name -> how many owned right now
	discovered: { [string]: boolean }, -- relic name -> ever found (survives merging away)
}

local function defaultData(): PlayerData
	-- Built fresh each call so two players never share the same table.
	return {
		schemaVersion = SCHEMA_VERSION,
		inventory = {},
		discovered = {},
	}
end

-- Fills in any top-level fields that exist in the default shape but are
-- missing from stored data. This is how old saves survive new features:
-- data saved before `discovered` existed gets an empty set added here
-- instead of crashing code that expects it.
local function reconcile(stored: any): PlayerData
	-- Saves written before schemaVersion existed are by definition the
	-- first schema. Stamp that BEFORE the generic fill-in below, so an old
	-- save can never be labeled with a newer version than its real shape
	-- (which would make future migration code skip it).
	if stored.schemaVersion == nil then
		stored.schemaVersion = 1
	end
	-- When SCHEMA_VERSION grows past 1, step-by-step migrations run here:
	-- if stored.schemaVersion == 1 then ... ; stored.schemaVersion = 2 ; end

	local default = defaultData()
	for key, defaultValue in default :: any do
		if stored[key] == nil then
			stored[key] = defaultValue
		end
	end
	-- Owning a relic implies having discovered it. This also migrates
	-- saves that predate `discovered` — their index starts from what
	-- they currently hold instead of empty.
	for relicName in stored.inventory do
		stored.discovered[relicName] = true
	end
	return stored
end

type Session = {
	data: PlayerData,
	-- If the load failed, we still give the player default data so they can
	-- play, but we must NEVER save it — saving would overwrite their real
	-- data with an empty inventory. This flag blocks all saves for the session.
	loadFailed: boolean,
}

local sessions: { [number]: Session } = {}

-- Runs fn up to MAX_RETRIES times with a short growing delay between tries.
-- DataStore calls fail routinely (throttling, outages), so every call goes
-- through this instead of a bare pcall.
local function withRetries(what: string, fn: () -> any): (boolean, any)
	local delaySeconds = 1
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(("DataService: %s failed (attempt %d/%d): %s"):format(what, attempt, MAX_RETRIES, tostring(result)))
		if attempt < MAX_RETRIES then
			task.wait(delaySeconds)
			delaySeconds *= 2
		end
	end
	return false, nil
end

local function keyFor(userId: number): string
	return KEY_PREFIX .. userId
end

local function load(player: Player)
	local ok, stored = withRetries("load " .. player.Name, function()
		return store:GetAsync(keyFor(player.UserId))
	end)

	local session: Session = {
		data = if stored ~= nil then reconcile(stored) else defaultData(),
		loadFailed = not ok,
	}
	sessions[player.UserId] = session

	if not ok then
		warn(("DataService: giving %s temporary default data; saving is disabled for this session"):format(player.Name))
	end
end

local function save(userId: number, playerName: string)
	local session = sessions[userId]
	if session == nil or session.loadFailed then
		return
	end
	withRetries("save " .. playerName, function()
		store:SetAsync(keyFor(userId), session.data)
	end)
end

-- Returns the player's live data table, or nil if it isn't loaded
-- (load still in progress, or they already left).
function DataService.get(player: Player): PlayerData?
	local session = sessions[player.UserId]
	return session and session.data
end

Players.PlayerAdded:Connect(load)
-- Players who joined before this script connected (possible in Studio).
for _, player in Players:GetPlayers() do
	task.spawn(load, player)
end

Players.PlayerRemoving:Connect(function(player)
	save(player.UserId, player.Name)
	sessions[player.UserId] = nil
end)

-- Autosave loop. task.spawn so requiring this module doesn't block forever.
task.spawn(function()
	while true do
		task.wait(Config.AutosaveInterval)
		for _, player in Players:GetPlayers() do
			save(player.UserId, player.Name)
		end
	end
end)

-- Last line of defense: when the server shuts down, PlayerRemoving isn't
-- guaranteed to have finished for everyone. BindToClose keeps the server
-- alive (up to 30s) until this returns.
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		save(player.UserId, player.Name)
	end
end)

return DataService
