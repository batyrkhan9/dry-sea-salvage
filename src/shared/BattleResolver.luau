--[[
	BattleResolver - the deterministic heart of camp duels. Pure logic,
	no Roblox APIs, unit-tested in Lune.

	resolve() takes both players' placed layouts and returns the outcome
	PLUS an ordered event script of every clash. The server trusts the
	outcome; the client plays the same events back as animations - so the
	fight kids watch is exactly the fight that was resolved.

	Rules (design: choices must dominate collection size):
	- Column by column, each side's front-most relic steps up (front =
	  higher cellZ, the row nearest the opponent).
	- A role that counters the other's role WINS outright, whatever the
	  rarity - the counter wheel is the core lesson.
	- No counter either way: higher EFFECTIVE TIER wins; equal tiers
	  exhaust both (mutual stalemate) so battles always end.
	- Scouts can't fight (they lose any clash against a combat role;
	  Scout vs Scout stalemates) but grant +1 effective tier to
	  orthogonally adjacent allies, counted from the starting layout.
	- Most survivors after all columns wins the battle.
]]

local Config = require(script.Parent.Config)
local RelicUtil = require(script.Parent.RelicUtil)

local BattleResolver = {}

export type PlacedRelic = {
	relicName: string,
	cellX: number,
	cellZ: number,
}

export type Side = "A" | "B"

export type ClashEvent = {
	kind: "clash",
	column: number,
	aRelic: PlacedRelic,
	bRelic: PlacedRelic,
	winner: Side | "none", -- "none" = mutual stalemate, both drop out
	reason: "counter" | "tier" | "scout" | "stalemate",
}

export type BattleResult = {
	winner: Side | "draw",
	survivorsA: number,
	survivorsB: number,
	events: { ClashEvent },
}

-- Effective tier = rarity index + number of orthogonally adjacent
-- friendly Scouts in the STARTING layout. Static on purpose: the bonus
-- is readable on the board before the fight, which is what makes scout
-- placement a plannable decision rather than a mid-battle surprise.
local function effectiveTiers(layout: { PlacedRelic }): { [PlacedRelic]: number }
	local scoutAt: { [string]: boolean } = {}
	for _, placed in layout do
		if RelicUtil.roleOf(placed.relicName) == "Scout" then
			scoutAt[placed.cellX .. "," .. placed.cellZ] = true
		end
	end

	local tiers: { [PlacedRelic]: number } = {}
	for _, placed in layout do
		local rarityName = RelicUtil.rarityOf(placed.relicName) :: string
		local tier = RelicUtil.rarityIndex(rarityName) :: number
		for _, offset in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			if scoutAt[(placed.cellX + offset[1]) .. "," .. (placed.cellZ + offset[2])] then
				tier += 1
			end
		end
		tiers[placed] = tier
	end
	return tiers
end

-- The column's units for one side, front-most (highest cellZ) first.
local function columnQueue(layout: { PlacedRelic }, column: number): { PlacedRelic }
	local queue = {}
	for _, placed in layout do
		if placed.cellX == column then
			table.insert(queue, placed)
		end
	end
	table.sort(queue, function(p, q)
		return p.cellZ > q.cellZ
	end)
	return queue
end

-- Decides one clash. Returns the winning side ("none" for stalemate)
-- and the reason, from A's perspective ordering.
local function decideClash(aRole: string, bRole: string, aTier: number, bTier: number): (Side | "none", string)
	local aIsScout = aRole == "Scout"
	local bIsScout = bRole == "Scout"
	if aIsScout and bIsScout then
		return "none", "stalemate"
	elseif aIsScout then
		return "B", "scout"
	elseif bIsScout then
		return "A", "scout"
	end

	if RelicUtil.roleCounters(aRole, bRole) then
		return "A", "counter"
	elseif RelicUtil.roleCounters(bRole, aRole) then
		return "B", "counter"
	end

	if aTier > bTier then
		return "A", "tier"
	elseif bTier > aTier then
		return "B", "tier"
	end
	return "none", "stalemate"
end

function BattleResolver.resolve(layoutA: { PlacedRelic }, layoutB: { PlacedRelic }): BattleResult
	local tiersA = effectiveTiers(layoutA)
	local tiersB = effectiveTiers(layoutB)

	local survivorsA = 0
	local survivorsB = 0
	local events: { ClashEvent } = {}

	for column = 1, Config.Camp.gridCells do
		local queueA = columnQueue(layoutA, column)
		local queueB = columnQueue(layoutB, column)

		-- Front units clash until one side's column is empty. Every
		-- clash removes at least one unit, so this always terminates.
		while #queueA > 0 and #queueB > 0 do
			local a = queueA[1]
			local b = queueB[1]
			local winner, reason = decideClash(
				RelicUtil.roleOf(a.relicName) :: string,
				RelicUtil.roleOf(b.relicName) :: string,
				tiersA[a],
				tiersB[b]
			)
			table.insert(events, {
				kind = "clash" :: "clash",
				column = column,
				aRelic = a,
				bRelic = b,
				winner = winner,
				reason = reason :: any,
			})
			if winner == "A" then
				table.remove(queueB, 1)
			elseif winner == "B" then
				table.remove(queueA, 1)
			else
				table.remove(queueA, 1)
				table.remove(queueB, 1)
			end
		end

		survivorsA += #queueA
		survivorsB += #queueB
	end

	local winner: Side | "draw" = "draw"
	if survivorsA > survivorsB then
		winner = "A"
	elseif survivorsB > survivorsA then
		winner = "B"
	end

	return {
		winner = winner,
		survivorsA = survivorsA,
		survivorsB = survivorsB,
		events = events,
	}
end

return BattleResolver
