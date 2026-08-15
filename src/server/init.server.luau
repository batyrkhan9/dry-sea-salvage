--[[
	Server entry point. Creates remotes and wires them to service modules.
	Keep logic out of this file — it should only glue things together.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RollService = require(script.RollService)

local rollEvent = Instance.new("RemoteEvent")
rollEvent.Name = "RollEvent"
rollEvent.Parent = ReplicatedStorage

rollEvent.OnServerEvent:Connect(function(player)
	local result = RollService.tryRoll(player)
	if result == nil then
		-- On cooldown — silently ignore. The client will get its own
		-- cooldown UI later; the server just refuses to be spammed.
		return
	end
	print(player.Name, "salvaged:", result.relic, "(" .. result.rarityName .. ")")
	rollEvent:FireClient(player, result.relic, result.rarityName)
end)
