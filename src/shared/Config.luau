local Config = {}

-- seconds a player must wait between salvage rolls (enforced on the server)
Config.RollCooldown = 2

-- seconds between automatic saves of each player's data
Config.AutosaveInterval = 120

-- how many copies of the same relic it takes to merge into the next tier
Config.MergeCost = 3

-- camp plots: every player gets one while they're in the server. Plots sit
-- in a ring just inside the wreck-free zone around spawn (MapBuilder keeps
-- wrecks 70+ studs out). The grid is for relic placement: gridCells x
-- gridCells cells, each cellSize studs, must fit inside plotSize.
Config.Camp = {
	plotCount = 8, -- also the effective max players per server for v2
	-- ring must keep neighbors apart: 8 plots at radius 90 sit ~69 studs
	-- apart, giving real breathing room past the 36-stud plot width (and
	-- the ring + half a plot stays inside MapBuilder's wreck-free zone)
	plotRingRadius = 90,
	plotSize = 36,
	gridCells = 6,
	cellSize = 6,
}

-- pity system: after `threshold` rolls without hitting `minRarityName` or
-- better, the next roll is guaranteed to land in that rare band (still
-- weighted fairly within the band). Bad luck always has a floor.
Config.Pity = {
	threshold = 90,
	minRarityName = "Storm",
}

-- rarities (by name) whose pulls get announced to the whole server
Config.AnnounceRarities = {
	["Ghost Ship"] = true,
	["What the Sea Left"] = true,
}

-- sound asset ids ("rbxassetid://<number>"). 0 = no sound yet, playback
-- is skipped. Fill these in from the Toolbox (Audio tab, filter
-- "Unrestricted") when you find sounds you like.
Config.Sounds = {
	RollResult = { -- played when the result popup appears, keyed by rarity
		["Rust"] = 0,
		["Salt"] = 0,
		["Tide"] = 0,
		["Storm"] = 0,
		["Ghost Ship"] = 0,
		["What the Sea Left"] = 0,
	},
	ButtonClick = 0, -- any UI button press
	Announcement = 0, -- server-wide rare-pull banner
}

-- weight = how many "tickets" this rarity has in the lottery
Config.Rarities = {
	{ name = "Rust", weight = 500, color = Color3.fromRGB(150, 90, 50) },
	{ name = "Salt", weight = 300, color = Color3.fromRGB(230, 230, 220) },
	{ name = "Tide", weight = 140, color = Color3.fromRGB(80, 160, 200) },
	{ name = "Storm", weight = 50, color = Color3.fromRGB(90, 80, 160) },
	{ name = "Ghost Ship", weight = 9, color = Color3.fromRGB(180, 255, 220) },
	{ name = "What the Sea Left", weight = 1, color = Color3.fromRGB(255, 215, 120) },
}

-- Duel combat is pure stats under a hard deploy budget - no counter
-- wheel, nothing is an auto-win. Roles are stat ARCHETYPES only:
--   Guard   = tank: high HP, modest ATK, grinds enemies down
--   Breaker = damage: high ATK, fragile
--   Trap    = ambusher: strikes first once per clash, then trades
--   Scout   = support: weak fighter, but BRACES orthogonally adjacent
--             allies: each gains +aura bonus HP at battle start (HP
--             never overkills, so the bonus always pays its way)
export type Role = "Breaker" | "Guard" | "Trap" | "Scout"

-- The hard deploy cap, identical for every player, forever. Fairness
-- lives here: collections buy OPTIONS under the cap, never raw power.
Config.Duel = {
	budget = 20,
}

-- Each relic is a table (not a bare string) on purpose: gameplay fields
-- ride along with no save migration needed - saves only ever store
-- relic NAMES, never these tables.
export type RelicDef = {
	name: string,
	role: Role,
	hp: number,
	atk: number,
	cost: number,
	aura: number?, -- Scout only: bonus HP granted to adjacent allies
}

-- Stat table. Tuning intent (verified by tools/balance.luau):
-- cost scales with tier; raw stats scale a bit FASTER than cost so
-- rares feel special, but cheap relics stay competitive per point in
-- numbers - quantity vs quality must be a genuine choice under the
-- budget cap, never a solved question.
Config.Relics = {
	["Rust"] = { -- cost 2
		{ name = "Bent Anchor", role = "Guard", hp = 8, atk = 2, cost = 2 },
		{ name = "Torn Net", role = "Trap", hp = 3, atk = 2, cost = 2 },
		{ name = "Rusty Chain", role = "Breaker", hp = 4, atk = 4, cost = 2 },
	},
	["Salt"] = { -- cost 3
		{ name = "Ship Bell", role = "Scout", hp = 6, atk = 1, cost = 3, aura = 3 },
		{ name = "Old Compass", role = "Breaker", hp = 6, atk = 5, cost = 3 },
		{ name = "Bottle Message", role = "Trap", hp = 4, atk = 3, cost = 3 },
	},
	["Tide"] = { -- cost 4
		{ name = "Figurehead", role = "Guard", hp = 14, atk = 3, cost = 4 },
		{ name = "Captain's Log", role = "Scout", hp = 8, atk = 2, cost = 4, aura = 4 },
		{ name = "Brass Telescope", role = "Breaker", hp = 7, atk = 7, cost = 4 },
	},
	["Storm"] = { -- cost 6
		{ name = "Lightning Mast", role = "Breaker", hp = 10, atk = 10, cost = 6 },
		{ name = "Black Flag", role = "Trap", hp = 7, atk = 6, cost = 6 },
	},
	["Ghost Ship"] = { -- cost 8
		{ name = "Phantom Wheel", role = "Guard", hp = 26, atk = 6, cost = 8 },
	},
	["What the Sea Left"] = { -- cost 10
		{ name = "The Key", role = "Scout", hp = 12, atk = 4, cost = 10, aura = 5 },
	},
} :: { [string]: { RelicDef } }

return Config
