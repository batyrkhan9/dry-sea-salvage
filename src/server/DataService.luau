--[[
	DataService - the ONLY module that talks to DataStoreService.

	Lifecycle it manages:
	  - load a player's data when they join (with retries)
	  - keep it cached in memory while they play (other services mutate the cache)
	  - save on leave, on server shutdown, and on an autosave timer

	Everything else (InventoryService etc.) just asks for the cached table
	via DataService.get() and mutates it - saving is this module's problem.

	Session locking: the same account can be in two servers at once (rejoin
	race, teleports, a stuck server). Without a lock, whichever server saves
	last silently overwrites the other's progress. So every record carries a
	_lock (server id + timestamp): a server only loads a record it can lock,
	refreshes the lock on autosave, and releases it on the final save. A
	second server seeing a fresh foreign lock gets a read-only session
	instead of the power to destroy data. Stale locks (crashed server that
	never released) expire after LOCK_TIMEOUT.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerDataSchema = require(script.Parent.PlayerDataSchema)

local defaultData = PlayerDataSchema.defaultData
local reconcile = PlayerDataSchema.reconcile

local DataService = {}

-- Bump the "_v1" if the data format ever changes incompatibly - old data
-- stays untouched under the old name instead of being misread.
local STORE_NAME = "PlayerData_v1"
local KEY_PREFIX = "player_"
local MAX_RETRIES = 3

-- game.JobId uniquely identifies a live server but is "" in Studio, so
-- fall back to a GUID there (each playtest counts as its own "server").
local SERVER_ID = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)

-- A lock is stale once its owner has missed two autosaves (plus slack for
-- retries) - the owner is either dead or about to release anyway.
local LOCK_TIMEOUT = Config.AutosaveInterval * 2 + 30

-- How many times to re-attempt taking a lock held by another server.
-- Covers the common race: rejoining while the old server is still
-- finishing the leave-save that releases the lock.
local LOCK_ATTEMPTS = 3
local LOCK_RETRY_DELAY = 3

local store = DataStoreService:GetDataStore(STORE_NAME)

type Lock = { id: string, at: number }

local function isHeldByOther(lock: Lock?): boolean
	return lock ~= nil and lock.id ~= SERVER_ID and os.time() - lock.at < LOCK_TIMEOUT
end

export type PlayerData = PlayerDataSchema.PlayerData

type Session = {
	data: PlayerData,
	-- If the load failed, we still give the player default data so they can
	-- play, but we must NEVER save it - saving would overwrite their real
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
	local ok, stored
	local lockedOut = false

	-- Outer loop: re-attempt when the record is LOCKED (not an error -
	-- usually the player's previous server finishing its leave-save).
	-- withRetries inside handles actual API failures.
	for attempt = 1, LOCK_ATTEMPTS do
		lockedOut = false
		ok, stored = withRetries("load " .. player.Name, function()
			return store:UpdateAsync(keyFor(player.UserId), function(record)
				if record ~= nil and isHeldByOther(record._lock) then
					lockedOut = true
					return nil -- returning nil aborts the write
				end
				record = record or {} -- brand-new player
				record._lock = { id = SERVER_ID, at = os.time() } :: Lock
				return record
			end)
		end)
		if not lockedOut then
			break
		end
		if attempt < LOCK_ATTEMPTS then
			task.wait(LOCK_RETRY_DELAY)
		end
	end

	local session: Session
	if ok and not lockedOut then
		-- The lock is bookkeeping, not gameplay data - strip it so the
		-- rest of the game never sees it. It gets re-attached on save.
		stored._lock = nil
		session = { data = reconcile(stored), loadFailed = false }
	else
		session = { data = defaultData(), loadFailed = true }
		if lockedOut then
			warn(("DataService: %s's data is locked by another server; read-only session"):format(player.Name))
		else
			warn(
				("DataService: giving %s temporary default data; saving is disabled for this session"):format(
					player.Name
				)
			)
		end
	end
	sessions[player.UserId] = session
end

-- isFinal: the player is gone (leave/shutdown), so release the lock;
-- otherwise (autosave) refresh its timestamp to show we're alive.
local function save(userId: number, playerName: string, isFinal: boolean)
	local session = sessions[userId]
	if session == nil or session.loadFailed then
		return
	end
	withRetries("save " .. playerName, function()
		return store:UpdateAsync(keyFor(userId), function(record)
			-- Paranoia guard: if another server somehow holds a fresh
			-- lock (ours expired as stale), we no longer own this data -
			-- abort rather than overwrite their live session.
			if record ~= nil and isHeldByOther(record._lock) then
				warn(("DataService: lost lock on %s's data; skipping save"):format(playerName))
				return nil
			end
			local out: any = session.data
			out._lock = if isFinal then nil else { id = SERVER_ID, at = os.time() }
			return out
		end)
	end)
	-- Keep the cached copy free of lock bookkeeping between saves.
	local cached: any = session.data
	cached._lock = nil
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
	save(player.UserId, player.Name, true) -- final: releases the lock
	sessions[player.UserId] = nil
end)

-- Autosave loop. task.spawn so requiring this module doesn't block forever.
task.spawn(function()
	while true do
		task.wait(Config.AutosaveInterval)
		for _, player in Players:GetPlayers() do
			save(player.UserId, player.Name, false) -- refreshes the lock
		end
	end
end)

-- Last line of defense: when the server shuts down, PlayerRemoving isn't
-- guaranteed to have finished for everyone. BindToClose keeps the server
-- alive (up to 30s) until this returns.
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		save(player.UserId, player.Name, true)
	end
end)

return DataService
