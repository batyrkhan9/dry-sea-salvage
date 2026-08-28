--[[
	Client entry point. Like the server entry: glue only.
	Connects remotes to UI modules in both directions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local RollUI = require(script.RollUI)
local InventoryUI = require(script.InventoryUI)
local CollectionUI = require(script.CollectionUI)
local AnnouncementUI = require(script.AnnouncementUI)

local rollEvent = ReplicatedStorage:WaitForChild("RollEvent")
local announceEvent = ReplicatedStorage:WaitForChild("AnnounceEvent")
local mergeFunction = ReplicatedStorage:WaitForChild("MergeFunction")
local placeFunction = ReplicatedStorage:WaitForChild("PlaceFunction")
local inventoryChangedEvent = ReplicatedStorage:WaitForChild("InventoryChangedEvent")
local getInventoryFunction = ReplicatedStorage:WaitForChild("GetInventoryFunction")
local getCollectionFunction = ReplicatedStorage:WaitForChild("GetCollectionFunction")

-- UI wants to roll -> ask the server
RollUI.onRollRequested(function()
	rollEvent:FireServer()
end)

-- Server answered a roll -> show the popup, update any open panels
rollEvent.OnClientEvent:Connect(function(relic, rarityName, rollsUntilPity)
	RollUI.showResult(relic, rarityName)
	RollUI.setPityStatus(rollsUntilPity)
	InventoryUI.refreshIfOpen()
	CollectionUI.refreshIfOpen()
end)

-- Index panel asks for the discovered set -> fetch from the server
CollectionUI.onCollectionRequested(function()
	return getCollectionFunction:InvokeServer()
end)

-- Relics panel asks for the inventory -> fetch from the server
InventoryUI.onInventoryRequested(function()
	return getInventoryFunction:InvokeServer()
end)

-- Relics panel asks to merge -> server decides; reuse the roll popup
-- for the reveal, then refresh the panel to show new counts
InventoryUI.onMergeRequested(function(relicName)
	local result = mergeFunction:InvokeServer(relicName)
	if result ~= nil then
		RollUI.showResult(result.relic, result.rarityName)
	end
	InventoryUI.refreshIfOpen()
	CollectionUI.refreshIfOpen() -- a merge can discover a new relic too
end)

-- Relics panel asks to deploy a relic -> server places it at camp
InventoryUI.onPlaceRequested(function(relicName)
	placeFunction:InvokeServer(relicName)
	InventoryUI.refreshIfOpen() -- the placed copy left the inventory
end)

-- Server says our inventory changed without us asking (crate pickup at
-- camp) -> refresh the panel so counts aren't stale
inventoryChangedEvent.OnClientEvent:Connect(function()
	InventoryUI.refreshIfOpen()
end)

-- Someone on the server pulled something rare -> banner for everyone
announceEvent.OnClientEvent:Connect(function(playerName, relic, rarityName)
	AnnouncementUI.show(playerName, relic, rarityName)
end)

-- Keyboard shortcut: R rolls, sharing the same cooldown gate as the button.
UserInputService.InputBegan:Connect(function(input, typing)
	if typing then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		RollUI.tryRequestRoll()
	end
end)
