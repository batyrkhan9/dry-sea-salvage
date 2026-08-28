--[[
	Server entry point. Creates remotes and wires them to service modules.
	Keep logic out of this file - it should only glue things together.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RollService = require(script.RollService)
local InventoryService = require(script.InventoryService)
local MergeService = require(script.MergeService)
local PlacementService = require(script.PlacementService)
local CampService = require(script.CampService)
require(script.DataService) -- starts load/save lifecycle on require
require(script.MapBuilder).build() -- scatter the wrecks before players spawn

-- Client asks for a roll; server answers on the same event.
local rollEvent = Instance.new("RemoteEvent")
rollEvent.Name = "RollEvent"
rollEvent.Parent = ReplicatedStorage

-- Client asks to merge a relic; returns the merge result (or nil).
local mergeFunction = Instance.new("RemoteFunction")
mergeFunction.Name = "MergeFunction"
mergeFunction.Parent = ReplicatedStorage

-- Client asks to deploy a relic on its camp plot; returns the placement.
local placeFunction = Instance.new("RemoteFunction")
placeFunction.Name = "PlaceFunction"
placeFunction.Parent = ReplicatedStorage

-- Client asks which cells of its plot are occupied (for placement UI).
local getCampRelicsFunction = Instance.new("RemoteFunction")
getCampRelicsFunction.Name = "GetCampRelicsFunction"
getCampRelicsFunction.Parent = ReplicatedStorage

-- Client asks for its current inventory (for the relics panel).
local getInventoryFunction = Instance.new("RemoteFunction")
getInventoryFunction.Name = "GetInventoryFunction"
getInventoryFunction.Parent = ReplicatedStorage

-- Server -> one client: your inventory changed outside a request you made
-- (currently: picking a relic crate back up at camp).
local inventoryChangedEvent = Instance.new("RemoteEvent")
inventoryChangedEvent.Name = "InventoryChangedEvent"
inventoryChangedEvent.Parent = ReplicatedStorage

CampService.setPickupListener(function(player)
	inventoryChangedEvent:FireClient(player)
end)

-- Server -> ALL clients: someone pulled a top-tier relic.
local announceEvent = Instance.new("RemoteEvent")
announceEvent.Name = "AnnounceEvent"
announceEvent.Parent = ReplicatedStorage

-- Fires the server-wide banner if this rarity is announcement-worthy.
local function maybeAnnounce(player, relic: string, rarityName: string)
	if Config.AnnounceRarities[rarityName] then
		announceEvent:FireAllClients(player.Name, relic, rarityName)
	end
end

-- Client asks which relics it has ever discovered (for the index).
local getCollectionFunction = Instance.new("RemoteFunction")
getCollectionFunction.Name = "GetCollectionFunction"
getCollectionFunction.Parent = ReplicatedStorage

rollEvent.OnServerEvent:Connect(function(player)
	local result = RollService.tryRoll(player)
	if result == nil then
		-- On cooldown - silently ignore. The client shows its own
		-- cooldown UI; the server just refuses to be spammed.
		return
	end
	local count = InventoryService.addRelic(player, result.relic)
	print(player.Name, "salvaged:", result.relic, "(" .. result.rarityName .. ") - now owns", count or "?")
	rollEvent:FireClient(player, result.relic, result.rarityName, result.rollsUntilPity)
	maybeAnnounce(player, result.relic, result.rarityName)
end)

mergeFunction.OnServerInvoke = function(player, relicName)
	local result, reason = MergeService.tryMerge(player, relicName)
	if result == nil then
		-- Legit players can only trigger "not enough copies"-type reasons
		-- through UI bugs; log it and tell the client "no".
		warn(("merge rejected for %s: %s"):format(player.Name, reason or "?"))
		return nil
	end
	print(player.Name, "merged into:", result.relic, "(" .. result.rarityName .. ")")
	maybeAnnounce(player, result.relic, result.rarityName)
	return result
end

getCampRelicsFunction.OnServerInvoke = function(player)
	return PlacementService.getCampRelics(player)
end

placeFunction.OnServerInvoke = function(player, relicName, cellX, cellZ)
	-- Cell comes from the placement UI; nil falls back to first-free
	-- (kept as the server-side safety net, and for any older client).
	local placed, reason = PlacementService.tryPlace(player, relicName, cellX, cellZ)
	if placed == nil then
		warn(("placement rejected for %s: %s"):format(player.Name, reason or "?"))
		return nil
	end
	CampService.showPlacement(player, placed)
	print(player.Name, "deployed:", placed.relicName)
	return placed
end

getInventoryFunction.OnServerInvoke = function(player)
	-- Remotes serialize tables by copy, so the client can't mutate our data.
	return InventoryService.getInventory(player) or {}
end

getCollectionFunction.OnServerInvoke = function(player)
	return InventoryService.getDiscovered(player) or {}
end
