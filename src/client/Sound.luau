--[[
	Sound — one tiny helper so UI modules never build Sound instances
	themselves. Ids come from Config.Sounds; an id of 0 means "no sound
	chosen yet" and is silently skipped, so the game works fine before
	any audio has been picked.
]]

local SoundService = game:GetService("SoundService")

local Sound = {}

function Sound.play(assetId: number, volume: number?)
	if assetId == 0 then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. assetId
	sound.Volume = volume or 0.5
	sound.Parent = SoundService
	sound:Play()
	-- Clean up when done; the extra delay is a fallback in case Ended
	-- never fires (e.g. a bad/moderated asset id).
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(15, function()
		if sound.Parent ~= nil then
			sound:Destroy()
		end
	end)
end

return Sound
