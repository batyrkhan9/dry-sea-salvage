--[[
	RollUI - everything the player sees for rolling:
	  - the SALVAGE button (bottom center) with a cooldown countdown
	  - the result popup (center) tinted with the rarity's color

	All UI is built in code so it lives in git with everything else.
	The module exposes exactly two functions the entry script wires up:
	  RollUI.onRollRequested(callback)  -> called when the player wants to roll
	  RollUI.showResult(relic, rarityName)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local RelicUtil = require(ReplicatedStorage.Shared.RelicUtil)
local Sound = require(script.Parent.Sound)

local RollUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---------- building the static UI ----------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RollUI"
screenGui.ResetOnSpawn = false -- keep the UI through respawns
screenGui.Parent = playerGui

local salvageButton = Instance.new("TextButton")
salvageButton.Name = "SalvageButton"
salvageButton.AnchorPoint = Vector2.new(0.5, 1)
salvageButton.Position = UDim2.fromScale(0.5, 0.92)
salvageButton.Size = UDim2.fromOffset(220, 56)
salvageButton.Text = "SALVAGE"
salvageButton.Font = Enum.Font.GothamBold
salvageButton.TextSize = 24
salvageButton.TextColor3 = Color3.fromRGB(40, 30, 15)
salvageButton.BackgroundColor3 = Color3.fromRGB(230, 190, 100) -- sand yellow
salvageButton.AutoButtonColor = true
salvageButton.Parent = screenGui

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 12)
buttonCorner.Parent = salvageButton

-- Result popup: hidden by default, shown + tweened by showResult.
local popup = Instance.new("Frame")
popup.Name = "ResultPopup"
popup.AnchorPoint = Vector2.new(0.5, 0.5)
popup.Position = UDim2.fromScale(0.5, 0.4)
popup.Size = UDim2.fromOffset(320, 110)
popup.BackgroundColor3 = Color3.fromRGB(35, 30, 25)
popup.BackgroundTransparency = 0.15
popup.Visible = false
popup.Parent = screenGui

local popupCorner = Instance.new("UICorner")
popupCorner.CornerRadius = UDim.new(0, 14)
popupCorner.Parent = popup

-- Colored edge that carries the rarity color.
local popupStroke = Instance.new("UIStroke")
popupStroke.Thickness = 3
popupStroke.Parent = popup

local relicLabel = Instance.new("TextLabel")
relicLabel.Name = "RelicName"
relicLabel.AnchorPoint = Vector2.new(0.5, 0)
relicLabel.Position = UDim2.fromScale(0.5, 0.18)
relicLabel.Size = UDim2.fromScale(0.9, 0.4)
relicLabel.BackgroundTransparency = 1
relicLabel.Font = Enum.Font.GothamBold
relicLabel.TextScaled = true
relicLabel.TextColor3 = Color3.new(1, 1, 1)
relicLabel.Parent = popup

local rarityLabel = Instance.new("TextLabel")
rarityLabel.Name = "RarityName"
rarityLabel.AnchorPoint = Vector2.new(0.5, 0)
rarityLabel.Position = UDim2.fromScale(0.5, 0.58)
rarityLabel.Size = UDim2.fromScale(0.9, 0.28)
rarityLabel.BackgroundTransparency = 1
rarityLabel.Font = Enum.Font.Gotham
rarityLabel.TextScaled = true
rarityLabel.Parent = popup

-- Full-screen color flash used for high-tier pulls. Sits behind the popup
-- and ignores input (it's a Frame, not a button - frames don't sink clicks).
local flash = Instance.new("Frame")
flash.Name = "RarityFlash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 0
flash.Parent = screenGui

-- ---------- cooldown handling ----------

local onCooldown = false

-- Grays the button out and counts down its label, then restores it.
-- Client-side mirror of the server cooldown: purely cosmetic - the server
-- still rejects early requests even if this gets bypassed.
local function runCooldownDisplay()
	onCooldown = true
	salvageButton.AutoButtonColor = false
	salvageButton.BackgroundColor3 = Color3.fromRGB(120, 105, 80)

	-- task.wait returns the time actually waited (always a bit more than
	-- asked), so subtract that instead of the ideal 0.1 - otherwise the
	-- countdown drifts and re-enables the button late.
	local remaining = Config.RollCooldown
	while remaining > 0 do
		salvageButton.Text = ("SALVAGE (%d)"):format(math.ceil(remaining))
		remaining -= task.wait(0.1)
	end

	salvageButton.Text = "SALVAGE"
	salvageButton.BackgroundColor3 = Color3.fromRGB(230, 190, 100)
	salvageButton.AutoButtonColor = true
	onCooldown = false
end

-- ---------- public API ----------

local requestCallback: (() -> ())? = nil

function RollUI.onRollRequested(callback: () -> ())
	requestCallback = callback
end

-- Called from button click AND the R key, so both paths share the
-- cooldown check.
function RollUI.tryRequestRoll()
	if onCooldown then
		return
	end
	Sound.play(Config.Sounds.ButtonClick)
	task.spawn(runCooldownDisplay)
	if requestCallback then
		requestCallback()
	end
end

local currentShowId = 0 -- lets a new result cancel the previous popup's hide timer

function RollUI.showResult(relic: string, rarityName: string)
	currentShowId += 1
	local showId = currentShowId

	local color = RelicUtil.rarityColor(rarityName)
	-- 1 = Rust ... 6 = What the Sea Left; drives how hard the effects hit.
	local tier = RelicUtil.rarityIndex(rarityName) or 1

	relicLabel.Text = relic
	rarityLabel.Text = rarityName
	rarityLabel.TextColor3 = color
	popupStroke.Color = color

	Sound.play(Config.Sounds.RollResult[rarityName] or 0)

	-- Pop-in: start small and transparent, tween to full size. Higher
	-- tiers start smaller, so the same tween reads as a bigger "pop".
	popup.Visible = true
	local startScale = 1 - 0.1 * tier -- Rust 0.9x ... top tier 0.4x
	popup.Size = UDim2.fromOffset(320 * startScale, 110 * startScale)
	popup.BackgroundTransparency = 0.6
	local tweenIn = TweenService:Create(
		popup,
		TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(320, 110), BackgroundTransparency = 0.15 }
	)
	tweenIn:Play()

	-- Storm and up: flash the whole screen in the rarity color.
	if tier >= 4 then
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = 0.7
		TweenService:Create(
			flash,
			TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		):Play()
	end

	-- Ghost Ship and up: shake the popup for a moment.
	if tier >= 5 then
		task.spawn(function()
			local basePosition = popup.Position
			local elapsed = 0
			while elapsed < 0.45 do
				elapsed += task.wait()
				popup.Position = basePosition + UDim2.fromOffset(math.random(-4, 4), math.random(-4, 4))
			end
			popup.Position = basePosition
		end)
	end

	-- Hide after a moment - unless another roll replaced this popup already.
	task.delay(2.5, function()
		if currentShowId ~= showId then
			return
		end
		local tweenOut = TweenService:Create(
			popup,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)
		tweenOut:Play()
		tweenOut.Completed:Wait()
		if currentShowId == showId then
			popup.Visible = false
		end
	end)
end

salvageButton.Activated:Connect(RollUI.tryRequestRoll)

return RollUI
