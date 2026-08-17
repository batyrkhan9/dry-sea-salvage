--[[
	MergeService — server-side merge rules.
	Rule: Config.MergeCost copies of the SAME relic -> one random relic
	from the next rarity tier up. Top tier can't merge.

	tryMerge takes raw client input, so every step validates before
	anything is deducted.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RelicUtil = require(ReplicatedStorage.Shared.RelicUtil)
local InventoryService = require(script.Parent.InventoryService)

local MergeService = {}

export type MergeResult = {
	relic: string,
	rarityName: string,
}

-- Attempts to merge `relicName` for the player.
-- Returns the new relic on success, or (nil, reason) on failure.
-- The reason string is for server logs, not for showing to players.
function MergeService.tryMerge(player: Player, relicName: unknown): (MergeResult?, string?)
	-- Client input: could be anything. Reject non-strings before using it.
	if typeof(relicName) ~= "string" then
		return nil, "relic name is not a string"
	end

	local rarityName = RelicUtil.rarityOf(relicName)
	if rarityName == nil then
		return nil, "unknown relic: " .. relicName
	end

	local nextRarity = RelicUtil.nextRarityName(rarityName)
	if nextRarity == nil then
		return nil, "top-tier relic can't merge"
	end

	local inventory = InventoryService.getInventory(player)
	if inventory == nil then
		return nil, "player data not loaded"
	end
	if (inventory[relicName] or 0) < Config.MergeCost then
		return nil, "not enough copies"
	end

	-- All checks passed — now mutate. Remove first, then add, so a bug in
	-- the add path can never leave the player with cost NOT paid.
	local removed = InventoryService.removeRelic(player, relicName, Config.MergeCost)
	if not removed then
		return nil, "failed to remove copies"
	end

	local pool = Config.Relics[nextRarity]
	local newRelic = pool[math.random(1, #pool)]
	InventoryService.addRelic(player, newRelic)

	return {
		relic = newRelic,
		rarityName = nextRarity,
	}
end

return MergeService
