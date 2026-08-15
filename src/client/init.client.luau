--[[
	Client entry point. Like the server entry: glue only.
	Connects the roll remote to the UI module in both directions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local RollUI = require(script.RollUI)

local rollEvent = ReplicatedStorage:WaitForChild("RollEvent")

-- UI wants to roll -> ask the server
RollUI.onRollRequested(function()
	rollEvent:FireServer()
end)

-- Server answered -> show the popup
rollEvent.OnClientEvent:Connect(function(relic, rarityName)
	RollUI.showResult(relic, rarityName)
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
