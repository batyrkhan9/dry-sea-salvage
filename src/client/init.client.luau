--[[
	Client entry point. Like the server entry: glue only.
	Connects remotes to UI modules in both directions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local RollUI = require(script.RollUI)
local InventoryUI = require(script.InventoryUI)

local rollEvent = ReplicatedStorage:WaitForChild("RollEvent")
local mergeFunction = ReplicatedStorage:WaitForChild("MergeFunction")
local getInventoryFunction = ReplicatedStorage:WaitForChild("GetInventoryFunction")

-- UI wants to roll -> ask the server
RollUI.onRollRequested(function()
	rollEvent:FireServer()
end)

-- Server answered a roll -> show the popup, update the relics panel
rollEvent.OnClientEvent:Connect(function(relic, rarityName)
	RollUI.showResult(relic, rarityName)
	InventoryUI.refreshIfOpen()
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
