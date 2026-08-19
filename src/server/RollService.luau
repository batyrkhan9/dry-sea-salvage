--[[
	RollService — all salvage-roll logic lives here.
	The entry script (init.server) only wires remotes to this module,
	so the "how rolling works" and the "how the network works" stay separate.

	The weighted-pick math itself lives in RelicUtil (pure, unit-tested);
	this module owns the randomness and the per-player cooldown.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local RelicUtil = require(ReplicatedStorage.Shared.RelicUtil)

local RollService = {}

-- Result shape the rest of the game consumes.
export type RollResult = {
	relic: string,
	rarityName: string,
}

-- os.clock() timestamp of each player's last roll, keyed by UserId.
-- Keyed by UserId (a plain number) rather than the Player instance so a
-- forgotten entry can never keep a Player object alive in memory.
local lastRollAt: { [number]: number } = {}

local function rollRelic(rarityName: string): string
	local pool = Config.Relics[rarityName]
	return pool[math.random(1, #pool)].name
end

-- Attempts a roll for the player. Returns the result, or nil if they're
-- still on cooldown (the caller decides what to tell the client).
function RollService.tryRoll(player: Player): RollResult?
	local now = os.clock()
	local last = lastRollAt[player.UserId]
	if last ~= nil and now - last < Config.RollCooldown then
		return nil
	end
	lastRollAt[player.UserId] = now

	local ticket = math.random(1, RelicUtil.totalWeight())
	local rarity = RelicUtil.rarityForTicket(ticket)
	local relic = rollRelic(rarity.name)
	return {
		relic = relic,
		rarityName = rarity.name,
	}
end

-- Drop cooldown entries when players leave so the table doesn't grow forever.
Players.PlayerRemoving:Connect(function(player)
	lastRollAt[player.UserId] = nil
end)

return RollService
