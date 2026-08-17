--[[
	RollService — all salvage-roll logic lives here.
	The entry script (init.server) only wires remotes to this module,
	so the "how rolling works" and the "how the network works" stay separate.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)

local RollService = {}

-- Result shape the rest of the game consumes.
export type RollResult = {
	relic: string,
	rarityName: string,
}

-- Sum the weights once at startup instead of on every roll.
local totalWeight = 0
for _, rarity in Config.Rarities do
	totalWeight += rarity.weight
end

-- os.clock() timestamp of each player's last roll, keyed by UserId.
-- Keyed by UserId (a plain number) rather than the Player instance so a
-- forgotten entry can never keep a Player object alive in memory.
local lastRollAt: { [number]: number } = {}

local function rollRarity()
	local ticket = math.random(1, totalWeight)
	local passed = 0
	for _, rarity in Config.Rarities do
		passed += rarity.weight
		if ticket <= passed then
			return rarity
		end
	end
	-- Unreachable: ticket is always <= totalWeight. error() instead of
	-- returning nil so a config mistake fails loudly, not silently.
	error("rollRarity fell through — check Config.Rarities weights")
end

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

	local rarity = rollRarity()
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
