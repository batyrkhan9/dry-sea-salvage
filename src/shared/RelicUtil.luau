--[[
	RelicUtil - pure lookup helpers over Config, no state, no side effects.
	Shared because both the server (validating merges) and the client
	(deciding which MERGE buttons to show) need the same answers.
]]

local Config = require(script.Parent.Config)

local RelicUtil = {}

-- Build reverse lookups once at require time.
local rarityIndexByName: { [string]: number } = {}
for index, rarity in Config.Rarities do
	rarityIndexByName[rarity.name] = index
end

local rarityNameByRelic: { [string]: string } = {}
for rarityName, relics in Config.Relics do
	for _, relic in relics do
		rarityNameByRelic[relic.name] = rarityName
	end
end

-- The rarity a relic belongs to, or nil for unknown names (important on the
-- server: relic names can arrive from the client and must not be trusted).
function RelicUtil.rarityOf(relicName: string): string?
	return rarityNameByRelic[relicName]
end

-- Position of a rarity in the tier ladder (1 = most common), or nil.
function RelicUtil.rarityIndex(rarityName: string): number?
	return rarityIndexByName[rarityName]
end

-- The next tier up from the given rarity, or nil if it's the top tier.
function RelicUtil.nextRarityName(rarityName: string): string?
	local index = rarityIndexByName[rarityName]
	if index == nil or index >= #Config.Rarities then
		return nil
	end
	return Config.Rarities[index + 1].name
end

-- True if this relic can be merged at all (known relic, not top tier).
function RelicUtil.isMergeable(relicName: string): boolean
	local rarityName = rarityNameByRelic[relicName]
	return rarityName ~= nil and RelicUtil.nextRarityName(rarityName) ~= nil
end

local roleByRelic: { [string]: string } = {}
for _, relics in Config.Relics do
	for _, relic in relics do
		roleByRelic[relic.name] = relic.role
	end
end

-- The duel role of a relic, or nil for unknown names.
function RelicUtil.roleOf(relicName: string): string?
	return roleByRelic[relicName]
end

-- True if `roleA` counters (beats) `roleB` on the wheel. Scouts counter
-- nothing and are countered by nothing - their value is support.
function RelicUtil.roleCounters(roleA: string, roleB: string): boolean
	return Config.RoleCounters[roleA] == roleB
end

-- Sum of all rarity weights (the lottery's total ticket count).
local totalWeight = 0
for _, rarity in Config.Rarities do
	totalWeight += rarity.weight
end

function RelicUtil.totalWeight(): number
	return totalWeight
end

-- Maps a lottery ticket (1..totalWeight) to its rarity. Pure - the caller
-- brings the randomness - which is what makes the odds unit-testable.
function RelicUtil.rarityForTicket(ticket: number)
	assert(ticket >= 1 and ticket <= totalWeight, "ticket out of range")
	local passed = 0
	for _, rarity in Config.Rarities do
		passed += rarity.weight
		if ticket <= passed then
			return rarity
		end
	end
	-- Unreachable: the assert above guarantees a tier is hit.
	error("rarityForTicket fell through - check Config.Rarities weights")
end

-- The first lottery ticket belonging to this rarity's band (tickets are
-- laid out in Config.Rarities order). Rolling a ticket in
-- [minTicketForRarity(X), totalWeight] guarantees rarity X or better,
-- which is how the pity system forces a rare without changing the
-- relative odds inside the rare band. Nil for unknown names.
function RelicUtil.minTicketForRarity(rarityName: string): number?
	local below = 0
	for _, rarity in Config.Rarities do
		if rarity.name == rarityName then
			return below + 1
		end
		below += rarity.weight
	end
	return nil
end

-- The display color of a rarity (white fallback for unknown names).
function RelicUtil.rarityColor(rarityName: string): Color3
	local index = rarityIndexByName[rarityName]
	if index == nil then
		return Color3.new(1, 1, 1)
	end
	return Config.Rarities[index].color
end

return RelicUtil
