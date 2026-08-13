local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local rollEvent = ReplicatedStorage:WaitForChild("RollEvent")

UserInputService.InputBegan:Connect(function(input, typing)
	if typing then return end
	if input.KeyCode == Enum.KeyCode.R then
		rollEvent:FireServer()
	end
end)

rollEvent.OnClientEvent:Connect(function(relic, rarityName)
	print("You salvaged:", relic, "-", rarityName, "!")
end)