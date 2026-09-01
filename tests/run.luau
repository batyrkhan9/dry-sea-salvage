--[[
	Unit tests, run with Lune (dev-only tool, not part of the game):
	    lune run tests/run.luau

	Game modules can't be required directly (Roblox-style requires and
	datatypes), so tests/loader.luau runs them with shims. Only pure
	logic modules are loadable this way - anything touching game
	services is exercised in Studio instead.
]]

local process = require("@lune/process")

local loadModule = require("./loader")

local Config = loadModule("src/shared/Config.luau", nil)
local RelicUtil = loadModule("src/shared/RelicUtil.luau", {
	Parent = { Config = "src/shared/Config.luau" },
})
local PlayerDataSchema = loadModule("src/server/PlayerDataSchema.luau", nil)
local BattleResolver = loadModule("src/shared/BattleResolver.luau", {
	Parent = { Config = "src/shared/Config.luau", RelicUtil = "src/shared/RelicUtil.luau" },
})

-- ---------- tiny test harness ----------

local passes = 0
local failures = 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passes += 1
		print(`  ok  {name}`)
	else
		failures += 1
		print(`FAIL  {name}`)
		print(`      {err}`)
	end
end

local function expectEqual(got: any, want: any, label: string?)
	if got ~= want then
		error(`{label or "value"}: expected {tostring(want)}, got {tostring(got)}`, 2)
	end
end

-- ---------- Config sanity ----------

test("weights sum to exactly 1000 (documented lottery size)", function()
	expectEqual(RelicUtil.totalWeight(), 1000)
end)

test("every rarity has a non-empty relic pool, and no orphan pools", function()
	local rarityNames = {}
	for _, rarity in Config.Rarities do
		rarityNames[rarity.name] = true
		local pool = Config.Relics[rarity.name]
		assert(pool ~= nil and #pool > 0, `rarity {rarity.name} has no relics`)
	end
	for poolName in Config.Relics do
		assert(rarityNames[poolName], `relic pool {poolName} matches no rarity`)
	end
end)

test("relic names are globally unique", function()
	local seen = {}
	for _, pool in Config.Relics do
		for _, relic in pool do
			assert(not seen[relic.name], `duplicate relic name: {relic.name}`)
			seen[relic.name] = true
		end
	end
end)

test("tiers are ordered from most to least common", function()
	-- Lots of logic (merge direction, index layout) assumes this order.
	for i = 2, #Config.Rarities do
		local prev, cur = Config.Rarities[i - 1], Config.Rarities[i]
		assert(cur.weight < prev.weight, `{cur.name} should be rarer than {prev.name}`)
	end
end)

test("rarityColor falls back to white for unknown names", function()
	local color = RelicUtil.rarityColor("Not A Rarity")
	expectEqual(color.R, 1)
	expectEqual(color.G, 1)
	expectEqual(color.B, 1)
end)

test("merge cost is at least 2", function()
	assert(Config.MergeCost >= 2, "merging fewer than 2 copies makes no sense")
end)

-- ---------- RelicUtil: weighted roll mapping ----------

test("every ticket band maps to its rarity (first and last ticket)", function()
	local passed = 0
	for _, rarity in Config.Rarities do
		local first = passed + 1
		local last = passed + rarity.weight
		expectEqual(RelicUtil.rarityForTicket(first).name, rarity.name, `ticket {first}`)
		expectEqual(RelicUtil.rarityForTicket(last).name, rarity.name, `ticket {last}`)
		passed = last
	end
end)

test("all 1000 tickets: each tier is hit exactly its weight's worth", function()
	local hits = {}
	for ticket = 1, RelicUtil.totalWeight() do
		local name = RelicUtil.rarityForTicket(ticket).name
		hits[name] = (hits[name] or 0) + 1
	end
	for _, rarity in Config.Rarities do
		expectEqual(hits[rarity.name], rarity.weight, rarity.name)
	end
end)

test("out-of-range tickets are rejected", function()
	assert(not pcall(RelicUtil.rarityForTicket, 0), "ticket 0 should error")
	assert(not pcall(RelicUtil.rarityForTicket, RelicUtil.totalWeight() + 1), "ticket over max should error")
end)

test("minTicketForRarity marks exact band starts", function()
	expectEqual(RelicUtil.minTicketForRarity(Config.Rarities[1].name), 1)
	for i, rarity in Config.Rarities do
		local min = RelicUtil.minTicketForRarity(rarity.name)
		expectEqual(RelicUtil.rarityForTicket(min).name, rarity.name, `band start of {rarity.name}`)
		if i > 1 then
			local before = RelicUtil.rarityForTicket(min - 1).name
			expectEqual(before, Config.Rarities[i - 1].name, `ticket before {rarity.name}`)
		end
	end
	expectEqual(RelicUtil.minTicketForRarity("Nonsense"), nil)
end)

test("pity config points at a real rarity with a sane threshold", function()
	assert(RelicUtil.rarityIndex(Config.Pity.minRarityName) ~= nil, "minRarityName must exist")
	assert(Config.Pity.threshold >= 1, "threshold must be positive")
end)

-- ---------- RelicUtil: lookups ----------

test("rarityOf maps relics to their tier, nil for unknown", function()
	expectEqual(RelicUtil.rarityOf("Bent Anchor"), "Rust")
	expectEqual(RelicUtil.rarityOf("The Key"), "What the Sea Left")
	expectEqual(RelicUtil.rarityOf("Definitely Not A Relic"), nil)
end)

test("nextRarityName climbs the ladder and stops at the top", function()
	expectEqual(RelicUtil.nextRarityName("Rust"), "Salt")
	expectEqual(RelicUtil.nextRarityName("Ghost Ship"), "What the Sea Left")
	expectEqual(RelicUtil.nextRarityName("What the Sea Left"), nil)
	expectEqual(RelicUtil.nextRarityName("Nonsense"), nil)
end)

test("isMergeable: known non-top relics only", function()
	expectEqual(RelicUtil.isMergeable("Phantom Wheel"), true)
	expectEqual(RelicUtil.isMergeable("The Key"), false, "top tier can't merge")
	expectEqual(RelicUtil.isMergeable("Definitely Not A Relic"), false)
end)

-- ---------- duel roles ----------

test("every relic has a valid role and sane stats", function()
	local validRoles = { Breaker = true, Guard = true, Trap = true, Scout = true }
	for _, pool in Config.Relics do
		for _, relic in pool do
			assert(validRoles[relic.role], `{relic.name} has invalid role {tostring(relic.role)}`)
			expectEqual(RelicUtil.roleOf(relic.name), relic.role, relic.name)
			assert(relic.hp > 0, `{relic.name} needs positive hp`)
			assert(relic.atk >= 0, `{relic.name} needs non-negative atk`)
			assert(relic.cost > 0, `{relic.name} needs positive cost`)
			if relic.role == "Scout" then
				assert(relic.aura and relic.aura > 0, `scout {relic.name} needs an aura`)
			else
				expectEqual(relic.aura, nil, `{relic.name}: only scouts carry auras`)
			end
		end
	end
	expectEqual(RelicUtil.roleOf("Not A Relic"), nil)
end)

test("armyCost sums deploy costs; unknown names count 0", function()
	expectEqual(RelicUtil.armyCost({}), 0)
	expectEqual(
		RelicUtil.armyCost({
			{ relicName = "Bent Anchor" }, -- 2
			{ relicName = "The Key" }, -- 10
			{ relicName = "Not A Relic" }, -- 0
		}),
		12
	)
end)

test("combat roles are all reachable in the common tiers (Rust..Tide)", function()
	-- No strategy should be locked behind rare pulls: each combat role
	-- must exist on at least one relic in the three common tiers.
	local found = {}
	for _, tier in { "Rust", "Salt", "Tide" } do
		for _, relic in Config.Relics[tier] do
			found[relic.role] = true
		end
	end
	for _, role in { "Breaker", "Guard", "Trap", "Scout" } do
		assert(found[role], `role {role} missing from common tiers`)
	end
end)

-- ---------- PlayerDataSchema ----------

test("defaultData has current schema version and fresh tables", function()
	local a = PlayerDataSchema.defaultData()
	local b = PlayerDataSchema.defaultData()
	expectEqual(a.schemaVersion, PlayerDataSchema.SCHEMA_VERSION)
	assert(a.inventory ~= b.inventory, "defaults must not share tables between players")
end)

test("reconcile fills missing fields on an empty record", function()
	local data = PlayerDataSchema.reconcile({})
	expectEqual(data.schemaVersion, 1)
	assert(type(data.inventory) == "table", "inventory filled in")
	assert(type(data.discovered) == "table", "discovered filled in")
	assert(type(data.campRelics) == "table", "campRelics filled in")
	expectEqual(data.duelRecord.wins, 0, "duelRecord filled in")
end)

test("reconcile keeps an existing duel record", function()
	local data = PlayerDataSchema.reconcile({
		duelRecord = { wins = 5, losses = 2, streak = 3 },
	})
	expectEqual(data.duelRecord.wins, 5)
	expectEqual(data.duelRecord.streak, 3)
end)

test("reconcile stamps version-less saves as schema 1, not current", function()
	-- If SCHEMA_VERSION ever moves past 1, a version-less (= v1-shaped)
	-- save must still be labeled 1 so migrations run for it.
	local data = PlayerDataSchema.reconcile({ inventory = { ["Ship Bell"] = 2 } })
	expectEqual(data.schemaVersion, 1)
end)

test("reconcile seeds discovered from owned relics", function()
	local data = PlayerDataSchema.reconcile({ inventory = { ["Ship Bell"] = 2 } })
	expectEqual(data.discovered["Ship Bell"], true)
end)

test("reconcile preserves existing data untouched", function()
	local data = PlayerDataSchema.reconcile({
		schemaVersion = 1,
		inventory = { ["Torn Net"] = 3 },
		discovered = { ["Old Compass"] = true },
	})
	expectEqual(data.inventory["Torn Net"], 3)
	expectEqual(data.discovered["Old Compass"], true, "already-discovered kept")
	expectEqual(data.discovered["Torn Net"], true, "owned implies discovered")
end)

-- ---------- BattleResolver ----------
-- Stats used below (from Config): Bent Anchor 8hp/2atk, Torn Net 3/3
-- (Trap), Rusty Chain 4/4, Ship Bell 3/1 aura 1 (Scout), Bottle Message
-- 4/4 (Trap), Figurehead 14/3, Phantom Wheel 26/6.

local function at(relicName: string, x: number, z: number)
	return { relicName = relicName, cellX = x, cellZ = z }
end

test("attrition: simultaneous rounds until one drops", function()
	local result = BattleResolver.resolve({ at("Figurehead", 1, 6) }, { at("Rusty Chain", 1, 6) })
	-- 14/3 vs 4/4: round 1 -> 10 vs 1, round 2 -> 6 vs dead.
	local clash = result.events[1]
	expectEqual(clash.rounds, 2)
	expectEqual(clash.winner, "A")
	expectEqual(clash.aHpEnd, 6)
	expectEqual(clash.bHpEnd, 0)
	expectEqual(clash.ambushBy, "none")
	expectEqual(result.winner, "A")
end)

test("survivors carry damage into their next clash", function()
	local result = BattleResolver.resolve(
		{ at("Phantom Wheel", 1, 6) },
		{ at("Rusty Chain", 1, 6), at("Rusty Chain", 2, 6), at("Rusty Chain", 3, 6) }
	)
	-- 26hp wheel one-shots each 4hp chain but takes 4 per clash:
	-- enters clash 3 at 18hp, leaves at 14.
	expectEqual(#result.events, 3)
	expectEqual(result.events[3].aHpStart, 18)
	expectEqual(result.events[3].aHpEnd, 14)
	expectEqual(result.winner, "A")
	expectEqual(result.survivorsB, 0)
end)

test("mutual knockout in the final clash is a draw", function()
	local result = BattleResolver.resolve({ at("Rusty Chain", 1, 6) }, { at("Rusty Chain", 1, 6) })
	expectEqual(result.events[1].winner, "none")
	expectEqual(result.winner, "draw")
	expectEqual(result.survivorsA, 0)
	expectEqual(result.survivorsB, 0)
end)

test("trap ambush strikes first; a killing ambush takes no damage back", function()
	local result = BattleResolver.resolve({ at("Black Flag", 1, 6) }, { at("Rusty Chain", 1, 6) })
	-- Flag's 6 atk ambush kills the 4hp chain before any exchange.
	local clash = result.events[1]
	expectEqual(clash.ambushBy, "A")
	expectEqual(clash.rounds, 0)
	expectEqual(clash.winner, "A")
	expectEqual(clash.aHpEnd, 7, "unhurt after a clean ambush")

	-- Two traps ambush each other simultaneously: 3/3 vs 4/4 - the
	-- bigger trap survives the exchange of ambushes.
	local trapDuel = BattleResolver.resolve({ at("Torn Net", 1, 6) }, { at("Bottle Message", 1, 6) })
	expectEqual(trapDuel.events[1].ambushBy, "both")
	expectEqual(trapDuel.events[1].winner, "B")
end)

test("scout aura braces adjacent allies with bonus HP", function()
	local result = BattleResolver.resolve(
		{ at("Bent Anchor", 1, 6), at("Ship Bell", 2, 6) },
		{ at("Bent Anchor", 1, 6) }
	)
	-- Braced anchor enters at 11 HP (8 + aura 3) and outlasts the
	-- otherwise-even mirror grind.
	expectEqual(result.events[1].aHpStart, 11)
	expectEqual(result.events[1].bHpStart, 8)
	expectEqual(result.events[1].winner, "A")
	expectEqual(result.survivorsA, 2, "anchor and uncontested scout both survive")
end)

test("marching order: front row first, left to right; whole army fights", function()
	local result = BattleResolver.resolve(
		{ at("Torn Net", 4, 5), at("Bent Anchor", 2, 6), at("Rusty Chain", 5, 6) },
		{ at("Phantom Wheel", 1, 6) }
	)
	expectEqual(result.events[1].aRelic.relicName, "Bent Anchor")
	expectEqual(result.events[2].aRelic.relicName, "Rusty Chain")
	expectEqual(result.events[3].aRelic.relicName, "Torn Net")
	expectEqual(#result.events, 3, "nobody sits out")
	expectEqual(result.winner, "B")
end)

test("resolution is deterministic", function()
	local layoutA = { at("Bent Anchor", 1, 6), at("Torn Net", 2, 5), at("Ship Bell", 2, 6) }
	local layoutB = { at("Rusty Chain", 1, 6), at("Figurehead", 2, 6) }
	local first = BattleResolver.resolve(layoutA, layoutB)
	local second = BattleResolver.resolve(layoutA, layoutB)
	expectEqual(first.winner, second.winner)
	expectEqual(#first.events, #second.events)
	for i, event in first.events do
		expectEqual(event.winner, second.events[i].winner, `event {i}`)
		expectEqual(event.aHpEnd, second.events[i].aHpEnd, `event {i} hp`)
	end
end)

-- ---------- summary ----------

print(`\n{passes} passed, {failures} failed`)
process.exit(if failures == 0 then 0 else 1)
