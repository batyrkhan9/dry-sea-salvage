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
local PlacementUI = require(script.PlacementUI)
local DuelUI = require(script.DuelUI)
local BattlePlayback = require(script.BattlePlayback)

local rollEvent = ReplicatedStorage:WaitForChild("RollEvent")
local announceEvent = ReplicatedStorage:WaitForChild("AnnounceEvent")
local mergeFunction = ReplicatedStorage:WaitForChild("MergeFunction")
local placeFunction = ReplicatedStorage:WaitForChild("PlaceFunction")
local getCampRelicsFunction = ReplicatedStorage:WaitForChild("GetCampRelicsFunction")
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

-- Relics panel asks what's deployed (for the budget readout)
InventoryUI.onCampRequested(function()
	return getCampRelicsFunction:InvokeServer()
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

-- Relics panel asks to deploy a relic -> enter cell-picking mode with
-- the current occupancy so only free cells light up
InventoryUI.onPlaceRequested(function(relicName)
	local taken = getCampRelicsFunction:InvokeServer()
	PlacementUI.enter(relicName, taken)
	InventoryUI.refresh() -- re-arm the PLACE button (it disarms on click)
end)

-- A green cell was clicked -> ask the server to place there
PlacementUI.onCellChosen(function(relicName, cellX, cellZ)
	placeFunction:InvokeServer(relicName, cellX, cellZ)
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

-- Duel flow: prompts, notices, and results come from the server; the
-- accept/decline answer goes back.
local duelPromptEvent = ReplicatedStorage:WaitForChild("DuelPromptEvent")
local duelNoticeEvent = ReplicatedStorage:WaitForChild("DuelNoticeEvent")
local duelResultEvent = ReplicatedStorage:WaitForChild("DuelResultEvent")
local duelRespondEvent = ReplicatedStorage:WaitForChild("DuelRespondEvent")

duelPromptEvent.OnClientEvent:Connect(function(challengerName)
	DuelUI.showPrompt(challengerName)
end)
duelNoticeEvent.OnClientEvent:Connect(function(text)
	DuelUI.showNotice(text)
end)
-- A duel resolved -> animate the event script, then show the scoreline
duelResultEvent.OnClientEvent:Connect(function(payload)
	BattlePlayback.play(payload)
end)
BattlePlayback.onFinished(function(payload)
	DuelUI.showResult(payload)
end)
DuelUI.onResponded(function(accepted)
	duelRespondEvent:FireServer(accepted)
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
