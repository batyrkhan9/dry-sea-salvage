local Config = {}

-- seconds a player must wait between salvage rolls (enforced on the server)
Config.RollCooldown = 2

-- seconds between automatic saves of each player's data
Config.AutosaveInterval = 120

-- how many copies of the same relic it takes to merge into the next tier
Config.MergeCost = 3

-- weight = how many "tickets" this rarity has in the lottery
Config.Rarities = {
	{ name = "Rust",       weight = 500, color = Color3.fromRGB(150, 90, 50) },
	{ name = "Salt",       weight = 300, color = Color3.fromRGB(230, 230, 220) },
	{ name = "Tide",       weight = 140, color = Color3.fromRGB(80, 160, 200) },
	{ name = "Storm",      weight = 50,  color = Color3.fromRGB(90, 80, 160) },
	{ name = "Ghost Ship", weight = 9,   color = Color3.fromRGB(180, 255, 220) },
	{ name = "What the Sea Left", weight = 1, color = Color3.fromRGB(255, 215, 120) },
}

Config.Relics = {
	["Rust"] = { "Bent Anchor", "Torn Net", "Rusty Chain" },
	["Salt"] = { "Ship Bell", "Old Compass", "Bottle Message" },
	["Tide"] = { "Figurehead", "Captain's Log", "Brass Telescope" },
	["Storm"] = { "Lightning Mast", "Black Flag" },
	["Ghost Ship"] = { "Phantom Wheel" },
	["What the Sea Left"] = { "The Key" },
}

return Config