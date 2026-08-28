--[[
	Unit tests, run with Lune (dev-only tool, not part of the game):
	    lune run tests/run.luau

	Game modules use Roblox-style requires (script.Parent.X) and the
	Color3 datatype, so a tiny loader below runs them with shims:
	`script` becomes a table of file paths, `require` loads those paths,
	and Color3 becomes a plain-table stand-in. Only pure logic modules
	are loadable this way - anything touching game services is exercised
	in Studio instead.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

-- ---------- module loader ----------

-- Plain-table stand-in for Roblox's Color3. Tests only need identity
-- (which color came back), not real color math.
local Color3Stub = {
	fromRGB = function(r: number, g: number, b: number)
		return { R = r / 255, G = g / 255, B = b / 255 }
	end,
	new = function(r: number?, g: number?, b: number?)
		return { R = r or 0, G = g or 0, B = b or 0 }
	end,
}

local cache: { [string]: any } = {}

local function loadModule(path: string, scriptShim: any): any
	if cache[path] ~= nil then
		return cache[path]
	end
	local fn = luau.load(fs.readFile(path), {
		debugName = path,
		environment = {
			Color3 = Color3Stub,
			script = scriptShim,
			require = function(target: any)
				assert(type(target) == "string", `unmapped require in {path}`)
				return loadModule(target, nil)
			end,
		},
	})
	local result = fn()
	cache[path] = result
	return result
end

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

test("every relic has a valid role", function()
	local validRoles = { Breaker = true, Guard = true, Trap = true, Scout = true }
	for _, pool in Config.Relics do
		for _, relic in pool do
			assert(validRoles[relic.role], `{relic.name} has invalid role {tostring(relic.role)}`)
			expectEqual(RelicUtil.roleOf(relic.name), relic.role, relic.name)
		end
	end
	expectEqual(RelicUtil.roleOf("Not A Relic"), nil)
end)

test("counter wheel is a clean 3-cycle over combat roles", function()
	-- Breaker -> Guard -> Trap -> Breaker, nothing counters itself,
	-- Scout stays outside the wheel entirely.
	expectEqual(RelicUtil.roleCounters("Breaker", "Guard"), true)
	expectEqual(RelicUtil.roleCounters("Guard", "Trap"), true)
	expectEqual(RelicUtil.roleCounters("Trap", "Breaker"), true)
	for role, beats in Config.RoleCounters do
		assert(role ~= beats, `{role} counters itself`)
		assert(role ~= "Scout" and beats ~= "Scout", "Scout must stay off the wheel")
		expectEqual(RelicUtil.roleCounters(beats, role), false, `{beats} must not counter {role} back`)
	end
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
-- Roles used below (from Config): Rusty Chain=Breaker, Bent Anchor=Guard,
-- Torn Net=Trap (all Rust); Ship Bell=Scout (Salt); Figurehead=Guard
-- (Tide); Lightning Mast=Breaker (Storm).

local function at(relicName: string, x: number, z: number)
	return { relicName = relicName, cellX = x, cellZ = z }
end

test("a counter beats a much rarer relic", function()
	local result = BattleResolver.resolve({ at("Torn Net", 1, 6) }, { at("Lightning Mast", 1, 6) })
	expectEqual(result.winner, "A")
	expectEqual(result.events[1].reason, "counter")
	expectEqual(result.survivorsA, 1)
	expectEqual(result.survivorsB, 0)
end)

test("same role falls back to tier; equal tiers stalemate out", function()
	local byTier = BattleResolver.resolve({ at("Bent Anchor", 1, 6) }, { at("Figurehead", 1, 6) })
	expectEqual(byTier.winner, "B")
	expectEqual(byTier.events[1].reason, "tier")

	local stalemate = BattleResolver.resolve({ at("Bent Anchor", 1, 6) }, { at("Bent Anchor", 1, 6) })
	expectEqual(stalemate.winner, "draw")
	expectEqual(stalemate.events[1].winner, "none")
	expectEqual(stalemate.survivorsA, 0)
end)

test("an adjacent scout flips an equal-tier clash", function()
	local result = BattleResolver.resolve(
		{ at("Bent Anchor", 1, 6), at("Ship Bell", 2, 6) },
		{ at("Bent Anchor", 1, 6) }
	)
	expectEqual(result.winner, "A")
	expectEqual(result.events[1].reason, "tier", "scout bonus should decide the tie")
	expectEqual(result.survivorsA, 2, "anchor and uncontested scout both survive")
end)

test("scouts lose any clash against a combat role", function()
	local result = BattleResolver.resolve({ at("Ship Bell", 1, 6) }, { at("Rusty Chain", 1, 6) })
	expectEqual(result.winner, "B")
	expectEqual(result.events[1].reason, "scout")
end)

test("marching order: front row first, left to right within a row", function()
	-- Brass Telescope (Breaker, Tide) fells A's Guard by counter and
	-- A's Breaker by tier, so each fighter steps up in queue order:
	-- Anchor (row 6, x2), Chain (row 6, x5), then Net (row 5).
	local result = BattleResolver.resolve(
		{ at("Torn Net", 4, 5), at("Bent Anchor", 2, 6), at("Rusty Chain", 5, 6) },
		{ at("Brass Telescope", 1, 6) }
	)
	expectEqual(result.events[1].aRelic.relicName, "Bent Anchor")
	expectEqual(result.events[2].aRelic.relicName, "Rusty Chain")
	expectEqual(result.events[3].aRelic.relicName, "Torn Net")
	-- ...and the Trap finally catches the Breaker.
	expectEqual(result.winner, "A")
end)

test("every relic fights until one army is wiped", function()
	local result = BattleResolver.resolve(
		{ at("Bent Anchor", 1, 6), at("Bent Anchor", 2, 6), at("Bent Anchor", 3, 6) },
		{ at("Figurehead", 1, 6) }
	)
	-- One higher-tier Guard grinds through all three: every A relic
	-- appears in the event log, nobody sits out.
	expectEqual(#result.events, 3)
	expectEqual(result.winner, "B")
	expectEqual(result.survivorsA, 0)
	expectEqual(result.survivorsB, 1)
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
	end
end)

-- ---------- summary ----------

print(`\n{passes} passed, {failures} failed`)
process.exit(if failures == 0 then 0 else 1)
