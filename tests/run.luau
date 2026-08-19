--[[
	Unit tests, run with Lune (dev-only tool, not part of the game):
	    lune run tests/run.luau

	Game modules use Roblox-style requires (script.Parent.X) and the
	Color3 datatype, so a tiny loader below runs them with shims:
	`script` becomes a table of file paths, `require` loads those paths,
	and Color3 becomes a plain-table stand-in. Only pure logic modules
	are loadable this way — anything touching game services is exercised
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

test("out-of-range tickets are rejected", function()
	assert(not pcall(RelicUtil.rarityForTicket, 0), "ticket 0 should error")
	assert(not pcall(RelicUtil.rarityForTicket, RelicUtil.totalWeight() + 1), "ticket over max should error")
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

-- ---------- summary ----------

print(`\n{passes} passed, {failures} failed`)
process.exit(if failures == 0 then 0 else 1)
