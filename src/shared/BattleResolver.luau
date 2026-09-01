--[[
	BattleResolver - the deterministic heart of camp duels. Pure logic,
	no Roblox APIs, unit-tested in Lune.

	resolve() takes both players' placed layouts and returns the outcome
	PLUS an ordered event script of every clash. The server trusts the
	outcome; the client plays the same events back as animations - so the
	fight kids watch is exactly the fight that was scored.

	Combat model - STATS + ATTRITION, nothing is an auto-win:
	- Armies fight in marching order: front row first (higher cellZ),
	  left to right within a row. Front fighters clash 1v1.
	- A clash is simultaneous blows, round by round (hp -= enemy atk),
	  until one or both drop. Whoever survives CARRIES its damage into
	  its next clash - attrition is the strategy's currency.
	- Trap archetype: strikes first ONCE at the start of each clash it
	  fights (ambush) - if that kills, no blow comes back.
	- Scout auras BRACE: a relic's starting HP is base + the aura of
	  every orthogonally adjacent friendly Scout, counted from the
	  starting layout, so support value is readable on the board before
	  the fight. (HP, not ATK, on purpose: bonus ATK is wasted as
	  overkill against cheap units; bonus HP always has to be chewed
	  through, so bracing pays consistently.)
	- The army left standing wins; a mutual final clash can draw.
	Fairness lives outside this module: armies must fit the hard deploy
	budget (Config.Duel.budget), enforced at placement and re-checked at
	challenge time.
]]

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
	aRelic: PlacedRelic,
	bRelic: PlacedRelic,
	-- Stats as they entered this clash (after auras / earlier damage).
	aHpStart: number,
	bHpStart: number,
	aAtk: number,
	bAtk: number,
	ambushBy: Side | "both" | "none", -- who got a free first strike
	rounds: number, -- simultaneous exchanges after any ambush
	aHpEnd: number, -- 0 = died in this clash
	bHpEnd: number,
	winner: Side | "none", -- "none" = both dropped
}

export type BattleResult = {
	winner: Side | "draw",
	survivorsA: number,
	survivorsB: number,
	events: { ClashEvent },
}

type Fighter = {
	placed: PlacedRelic,
	hp: number,
	atk: number,
	isTrap: boolean,
}

-- Builds fighters with aura-adjusted ATK from the starting layout.
local function buildFighters(layout: { PlacedRelic }): { Fighter }
	local auraAt: { [string]: number } = {}
	for _, placed in layout do
		local def = RelicUtil.defOf(placed.relicName)
		if def and def.aura then
			auraAt[placed.cellX .. "," .. placed.cellZ] = def.aura
		end
	end

	local fighters: { Fighter } = {}
	for _, placed in layout do
		local def = RelicUtil.defOf(placed.relicName) :: any
		local hp = def.hp
		for _, offset in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			hp += auraAt[(placed.cellX + offset[1]) .. "," .. (placed.cellZ + offset[2])] or 0
		end
		table.insert(fighters, {
			placed = placed,
			hp = hp,
			atk = def.atk,
			isTrap = def.role == "Trap",
		})
	end

	-- Marching order: front row first (higher cellZ), left to right.
	table.sort(fighters, function(p, q)
		if p.placed.cellZ ~= q.placed.cellZ then
			return p.placed.cellZ > q.placed.cellZ
		end
		return p.placed.cellX < q.placed.cellX
	end)
	return fighters
end

-- Starting (aura-braced) HP for every relic in a layout, keyed by
-- "cellX_cellZ". The battle playback uses this so HP bars show braced
-- values from the first frame, identical to what the resolver fought with.
function BattleResolver.startingHp(layout: { PlacedRelic }): { [string]: number }
	local byCell: { [string]: number } = {}
	for _, fighter in buildFighters(layout) do
		byCell[fighter.placed.cellX .. "_" .. fighter.placed.cellZ] = fighter.hp
	end
	return byCell
end

function BattleResolver.resolve(layoutA: { PlacedRelic }, layoutB: { PlacedRelic }): BattleResult
	local queueA = buildFighters(layoutA)
	local queueB = buildFighters(layoutB)
	local events: { ClashEvent } = {}

	while #queueA > 0 and #queueB > 0 do
		local a = queueA[1]
		local b = queueB[1]

		local aHpStart, bHpStart = a.hp, b.hp

		-- Ambush: traps strike once before the exchange. Two traps
		-- ambush each other simultaneously.
		local ambushBy: "A" | "B" | "both" | "none" = "none"
		if a.isTrap and b.isTrap then
			ambushBy = "both"
			a.hp -= b.atk
			b.hp -= a.atk
		elseif a.isTrap then
			ambushBy = "A"
			b.hp -= a.atk
		elseif b.isTrap then
			ambushBy = "B"
			a.hp -= b.atk
		end

		-- Simultaneous rounds until someone (or both) drop. Each round
		-- strictly reduces total hp, so this always terminates.
		local rounds = 0
		while a.hp > 0 and b.hp > 0 do
			rounds += 1
			a.hp -= b.atk
			b.hp -= a.atk
		end

		local aDead = a.hp <= 0
		local bDead = b.hp <= 0
		local winner: "A" | "B" | "none" = "none"
		if aDead and not bDead then
			winner = "B"
		elseif bDead and not aDead then
			winner = "A"
		end

		table.insert(events, {
			kind = "clash" :: "clash",
			aRelic = a.placed,
			bRelic = b.placed,
			aHpStart = aHpStart,
			bHpStart = bHpStart,
			aAtk = a.atk,
			bAtk = b.atk,
			ambushBy = ambushBy,
			rounds = rounds,
			aHpEnd = math.max(a.hp, 0),
			bHpEnd = math.max(b.hp, 0),
			winner = winner,
		})

		if aDead then
			table.remove(queueA, 1)
		end
		if bDead then
			table.remove(queueB, 1)
		end
	end

	local winner: Side | "draw" = "draw"
	if #queueA > 0 then
		winner = "A"
	elseif #queueB > 0 then
		winner = "B"
	end

	return {
		winner = winner,
		survivorsA = #queueA,
		survivorsB = #queueB,
		events = events,
	}
end

return BattleResolver
