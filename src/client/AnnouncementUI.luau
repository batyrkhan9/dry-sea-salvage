--[[
	AnnouncementUI - the server-wide rare-pull banner.
	Slides down from the top edge, holds, slides back up.

	Announcements are queued: if two players hit rare pulls back to back,
	the second banner waits for the first instead of overwriting it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local RelicUtil = require(ReplicatedStorage.Shared.RelicUtil)
local Sound = require(script.Parent.Sound)

local AnnouncementUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HOLD_SECONDS = 4
local SLIDE_SECONDS = 0.4
local HIDDEN_POS = UDim2.new(0.5, 0, 0, -70) -- parked above the screen edge
local SHOWN_POS = UDim2.new(0.5, 0, 0, 20)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AnnouncementUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = HIDDEN_POS
banner.Size = UDim2.fromOffset(520, 54)
banner.BackgroundColor3 = Color3.fromRGB(35, 30, 25)
banner.BackgroundTransparency = 0.1
banner.Visible = false
banner.Parent = screenGui

local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 12)
bannerCorner.Parent = banner

local bannerStroke = Instance.new("UIStroke")
bannerStroke.Thickness = 2
bannerStroke.Parent = banner

local bannerText = Instance.new("TextLabel")
bannerText.Size = UDim2.new(1, -24, 1, 0)
bannerText.Position = UDim2.fromOffset(12, 0)
bannerText.BackgroundTransparency = 1
bannerText.Font = Enum.Font.GothamBold
bannerText.TextScaled = true
bannerText.Parent = banner

local textSizeConstraint = Instance.new("UITextSizeConstraint")
textSizeConstraint.MaxTextSize = 20
textSizeConstraint.Parent = bannerText

-- ---------- queue ----------

type Announcement = {
	playerName: string,
	relic: string,
	rarityName: string,
}

local queue: { Announcement } = {}
local showing = false

local function showNext()
	local nextUp = table.remove(queue, 1)
	if nextUp == nil then
		showing = false
		return
	end
	showing = true

	local color = RelicUtil.rarityColor(nextUp.rarityName)
	bannerText.Text = ("%s salvaged %s - %s!"):format(nextUp.playerName, nextUp.relic, nextUp.rarityName)
	bannerText.TextColor3 = color
	bannerStroke.Color = color

	Sound.play(Config.Sounds.Announcement)

	banner.Visible = true
	banner.Position = HIDDEN_POS
	local slideIn = TweenService:Create(
		banner,
		TweenInfo.new(SLIDE_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = SHOWN_POS }
	)
	slideIn:Play()
	slideIn.Completed:Wait()

	task.wait(HOLD_SECONDS)

	local slideOut = TweenService:Create(
		banner,
		TweenInfo.new(SLIDE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = HIDDEN_POS }
	)
	slideOut:Play()
	slideOut.Completed:Wait()
	banner.Visible = false

	-- Chain straight into the next queued announcement, if any.
	showNext()
end

function AnnouncementUI.show(playerName: string, relic: string, rarityName: string)
	table.insert(queue, { playerName = playerName, relic = relic, rarityName = rarityName })
	if not showing then
		-- task.spawn because showNext blocks (tweens + hold) and the
		-- caller is usually a RemoteEvent handler that shouldn't stall.
		task.spawn(showNext)
	end
end

return AnnouncementUI
