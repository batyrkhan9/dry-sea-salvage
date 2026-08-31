--[[
	Battle balance simulator - runs the REAL BattleResolver over
	archetype armies and random armies, then reports who beats whom.
	Because resolution is deterministic and pure, this runs thousands of
	battles in a second with no Roblox involved:
	    lune run tools/balance.luau

	Two reports:
	1. Archetype matrix - hand-built armies (mono-role walls, mixed
	   lines, scout-backed formations) round-robin, exact results.
	2. Monte Carlo - seeded random armies, tallying how a layout's role
	   mix correlates with winning. Checks for degenerate "just spam X"
	   strategies.
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

-- ---------- archetype armies (Rust tier only, so role - not rarity -
-- is what's being measured; scouts are Salt, noted where used) ----------

local function line(relicName: string, count: number, row: number): { PlacedRelic }
	local army = {}
	for x = 1, count do
		table.insert(army, { relicName = relicName, cellX = x, cellZ = row })
	end
	return army
end

local function concat(...: { PlacedRelic }): { PlacedRelic }
	local out = {}
	for _, list in { ... } do
		for _, relic in list do
			table.insert(out, relic)
		end
	end
	return out
end

local archetypes: { { name: string, army: { PlacedRelic } } } = {
	{ name = "AllBreaker", army = line("Rusty Chain", 6, 6) },
	{ name = "AllGuard", army = line("Bent Anchor", 6, 6) },
	{ name = "AllTrap", army = line("Torn Net", 6, 6) },
	{
		name = "MixedLine", -- B,G,T repeating across the front
		army = {
			{ relicName = "Rusty Chain", cellX = 1, cellZ = 6 },
			{ relicName = "Bent Anchor", cellX = 2, cellZ = 6 },
			{ relicName = "Torn Net", cellX = 3, cellZ = 6 },
			{ relicName = "Rusty Chain", cellX = 4, cellZ = 6 },
			{ relicName = "Bent Anchor", cellX = 5, cellZ = 6 },
			{ relicName = "Torn Net", cellX = 6, cellZ = 6 },
		},
	},
	{
		name = "GuardScouts", -- 4 guards front, 2 scouts tucked behind
		army = concat(line("Bent Anchor", 4, 6), {
			{ relicName = "Ship Bell", cellX = 1, cellZ = 5 },
			{ relicName = "Ship Bell", cellX = 2, cellZ = 5 },
		}),
	},
	{
		name = "TrapScouts", -- 4 traps front, 2 scouts tucked behind
		army = concat(line("Torn Net", 4, 6), {
			{ relicName = "Ship Bell", cellX = 1, cellZ = 5 },
			{ relicName = "Ship Bell", cellX = 2, cellZ = 5 },
		}),
	},
}

print("== Archetype matrix (row = challenger/A, col = target/B) ==")
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

-- ---------- Monte Carlo: random armies ----------

math.randomseed(1960)

-- All relic names with their roles, for random army construction.
local allRelics: { string } = {}
for _, pool in Config.Relics do
	for _, relic in pool do
		table.insert(allRelics, relic.name)
	end
end
table.sort(allRelics) -- deterministic order regardless of table iteration

local function randomArmy(size: number): { PlacedRelic }
	local cells = {}
	for z = 1, Config.Camp.gridCells do
		for x = 1, Config.Camp.gridCells do
			table.insert(cells, { x, z })
		end
	end
	-- Fisher-Yates so placements never collide.
	for i = #cells, 2, -1 do
		local j = math.random(i)
		cells[i], cells[j] = cells[j], cells[i]
	end
	local army = {}
	for i = 1, size do
		table.insert(army, {
			relicName = allRelics[math.random(#allRelics)],
			cellX = cells[i][1],
			cellZ = cells[i][2],
		})
	end
	return army
end

local BATTLES = 4000
local ARMY_SIZE = 6

local roleWins: { [string]: number } = {}
local roleAppearances: { [string]: number } = {}
local draws = 0

for _ = 1, BATTLES do
	local armyA = randomArmy(ARMY_SIZE)
	local armyB = randomArmy(ARMY_SIZE)
	local result = BattleResolver.resolve(armyA, armyB)

	if result.winner == "draw" then
		draws += 1
	else
		local winnerArmy = if result.winner == "A" then armyA else armyB
		local loserArmy = if result.winner == "A" then armyB else armyA
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
print(("== Monte Carlo: %d random %dv%d battles (seeded) =="):format(BATTLES, ARMY_SIZE, ARMY_SIZE))
print(("draws: %d (%.1f%%)"):format(draws, draws / BATTLES * 100))
print("share of winning-army slots held by each role (25% = neutral):")
for _, role in { "Breaker", "Guard", "Trap", "Scout" } do
	local wins = roleWins[role] or 0
	local appearances = roleAppearances[role] or 0
	print(
		("  %-8s %.1f%% of winner slots (appeared %d times)"):format(
			role,
			wins / math.max(appearances, 1) * 100,
			appearances
		)
	)
end
