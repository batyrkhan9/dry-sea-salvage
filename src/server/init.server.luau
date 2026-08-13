local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

-- create the event the client uses to ask for a roll
local rollEvent = Instance.new("RemoteEvent")
rollEvent.Name = "RollEvent"
rollEvent.Parent = ReplicatedStorage

-- add up all the weights once
local totalWeight = 0
for _, rarity in Config.Rarities do
	totalWeight += rarity.weight
end

local function rollRarity()
	local ticket = math.random(1, totalWeight)
	local passed = 0
	for _, rarity in Config.Rarities do
		passed += rarity.weight
		if ticket <= passed then
			return rarity
		end
	end
end

local function rollRelic(rarityName)
	local pool = Config.Relics[rarityName]
	return pool[math.random(1, #pool)]
end

rollEvent.OnServerEvent:Connect(function(player)
	local rarity = rollRarity()
	local relic = rollRelic(rarity.name)
	print(player.Name, "salvaged:", relic, "(" .. rarity.name .. ")")
	rollEvent:FireClient(player, relic, rarity.name)
end)