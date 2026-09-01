--[[
	Battle balance simulator - runs the REAL BattleResolver over
	archetype armies and random armies, then reports who beats whom.
	Deterministic and pure, so thousands of battles cost nothing:
	    lune run tools/balance.luau

	Combat is stats + attrition under a hard deploy budget, so the
	questions this answers are:
	1. Archetype matrix - do hand-built budget-legal builds (swarms,
	   walls, big-ticket teams, scout cores) have a healthy meta, or
	   does one build dominate?
	2. Monte Carlo - across random budget-legal armies, does any role or
	   tier over-win, and does quantity beat quality (or vice versa)?
]]

local loadModule = require("../tests/loader")

local Config = loadModule("src/shared/Config.luau", nil)
local RelicUtil = loadModule("src/shared/RelicUtil.luau", {
	Parent = { Config = "src/shared/Config.luau" },
})
local BattleResolver = loadModule("src/shared/BattleResolver.luau", {
	Parent = { Config = "src/shared/Config.luau", RelicUtil = "src/shared/RelicUtil.luau" },
})

type PlacedRelic = { relicName: string, cellX: number, cellZ: number }

local BUDGET = Config.Duel.budget

-- Lays out an army front-to-back: fills row 6 left to right, then row
-- 5, etc. Scout-containing builds should order scouts to land adjacent.
local function formation(relicNames: { string }): { PlacedRelic }
	local army = {}
	for i, relicName in relicNames do
		local row = 6 - math.floor((i - 1) / Config.Camp.gridCells)
		local col = ((i - 1) % Config.Camp.gridCells) + 1
		table.insert(army, { relicName = relicName, cellX = col, cellZ = row })
	end
	return army
end

local function rep(relicName: string, count: number): { string }
	local names = {}
	for _ = 1, count do
		table.insert(names, relicName)
	end
	return names
end

local archetypes: { { name: string, army: { PlacedRelic } } } = {
	{ name = "ChainSwarm", army = formation(rep("Rusty Chain", 10)) }, -- 10x glass 2pt
	{ name = "AnchorWall", army = formation(rep("Bent Anchor", 10)) }, -- 10x tank 2pt
	{ name = "TrapLine", army = formation(rep("Torn Net", 10)) }, -- 10x ambush 2pt
	{
		name = "BigThree", -- 8 + 6 + 6 = 20: three monsters
		army = formation({ "Phantom Wheel", "Lightning Mast", "Black Flag" }),
	},
	{
		name = "Balanced", -- 4+4+3+3+2+2+2 = 20: mid-tier spread
		army = formation({
			"Figurehead",
			"Brass Telescope",
			"Old Compass",
			"Bottle Message",
			"Rusty Chain",
			"Rusty Chain",
			"Bent Anchor",
		}),
	},
	{
		name = "ScoutCore", -- scouts placed to touch 3 fighters each, 20pt
		-- Bell at (2,6) buffs (1,6), (3,6), (2,5); bell at (4,5) buffs
		-- (4,6), (3,5). Fighters: compasses front, chains behind.
		army = {
			{ relicName = "Old Compass", cellX = 1, cellZ = 6 },
			{ relicName = "Ship Bell", cellX = 2, cellZ = 6 },
			{ relicName = "Old Compass", cellX = 3, cellZ = 6 },
			{ relicName = "Rusty Chain", cellX = 4, cellZ = 6 },
			{ relicName = "Rusty Chain", cellX = 2, cellZ = 5 },
			{ relicName = "Ship Bell", cellX = 4, cellZ = 5 },
			{ relicName = "Rusty Chain", cellX = 3, cellZ = 5 },
		},
	},
}

-- Sanity: every archetype must be budget-legal.
for _, archetype in archetypes do
	local cost = RelicUtil.armyCost(archetype.army)
	assert(cost <= BUDGET, `{archetype.name} is over budget ({cost}/{BUDGET})`)
end

print(("== Archetype matrix, budget %d (row = challenger/A) =="):format(BUDGET))
local header = "              "
for _, col in archetypes do
	header ..= ("%-13s"):format(col.name)
end
print(header)
for _, rowType in archetypes do
	local cells = ("%-14s"):format(rowType.name)
	for _, colType in archetypes do
		local result = BattleResolver.resolve(rowType.army, colType.army)
		local mark
		if result.winner == "A" then
			mark = ("WIN %d-%d"):format(result.survivorsA, result.survivorsB)
		elseif result.winner == "B" then
			mark = ("lose %d-%d"):format(result.survivorsA, result.survivorsB)
		else
			mark = "draw"
		end
		cells ..= ("%-13s"):format(mark)
	end
	print(cells)
end

-- ---------- Monte Carlo: random budget-legal armies ----------

math.randomseed(1960)

local allRelics: { string } = {}
for _, pool in Config.Relics do
	for _, relic in pool do
		table.insert(allRelics, relic.name)
	end
end
table.sort(allRelics) -- deterministic order regardless of table iteration

-- Random army: keep drawing affordable relics until nothing fits.
local function randomArmy(): { PlacedRelic }
	local names = {}
	local remaining = BUDGET
	while true do
		local affordable = {}
		for _, relicName in allRelics do
			local def = RelicUtil.defOf(relicName) :: any
			if def.cost <= remaining then
				table.insert(affordable, relicName)
			end
		end
		if #affordable == 0 then
			break
		end
		local pick = affordable[math.random(#affordable)]
		table.insert(names, pick)
		remaining -= (RelicUtil.defOf(pick) :: any).cost
	end
	-- Random open cells for placement.
	local cells = {}
	for z = 1, Config.Camp.gridCells do
		for x = 1, Config.Camp.gridCells do
			table.insert(cells, { x, z })
		end
	end
	for i = #cells, 2, -1 do
		local j = math.random(i)
		cells[i], cells[j] = cells[j], cells[i]
	end
	local army = {}
	for i, relicName in names do
		table.insert(army, { relicName = relicName, cellX = cells[i][1], cellZ = cells[i][2] })
	end
	return army
end

local BATTLES = 4000

local roleWins: { [string]: number } = {}
local roleAppearances: { [string]: number } = {}
local winnerUnits = 0
local loserUnits = 0
local decided = 0
local draws = 0

for _ = 1, BATTLES do
	local armyA = randomArmy()
	local armyB = randomArmy()
	local result = BattleResolver.resolve(armyA, armyB)

	if result.winner == "draw" then
		draws += 1
	else
		decided += 1
		local winnerArmy = if result.winner == "A" then armyA else armyB
		local loserArmy = if result.winner == "A" then armyB else armyA
		winnerUnits += #winnerArmy
		loserUnits += #loserArmy
		for _, relic in winnerArmy do
			local role = RelicUtil.roleOf(relic.relicName) :: string
			roleWins[role] = (roleWins[role] or 0) + 1
			roleAppearances[role] = (roleAppearances[role] or 0) + 1
		end
		for _, relic in loserArmy do
			local role = RelicUtil.roleOf(relic.relicName) :: string
			roleAppearances[role] = (roleAppearances[role] or 0) + 1
		end
	end
end

print("")
print(("== Monte Carlo: %d random budget-%d battles (seeded) =="):format(BATTLES, BUDGET))
print(("draws: %d (%.1f%%)"):format(draws, draws / BATTLES * 100))
print(
	("avg army size: winners %.2f vs losers %.2f (gap = quantity vs quality signal)"):format(
		winnerUnits / math.max(decided, 1),
		loserUnits / math.max(decided, 1)
	)
)
print("share of winning-army slots held by each role (vs its appearance rate):")
for _, role in { "Breaker", "Guard", "Trap", "Scout" } do
	local wins = roleWins[role] or 0
	local appearances = roleAppearances[role] or 0
	print(
		("  %-8s %.1f%% of its appearances were on winning armies (%d appearances)"):format(
			role,
			wins / math.max(appearances, 1) * 100,
			appearances
		)
	)
end
