--[[
	DuelUI - challenge prompt, small notice toasts, and (for now) a text
	duel result. The animated battle playback will replace the text
	result with the event script; this module handles the social flow.

	Entry-script contract:
	  DuelUI.onResponded(cb)   -> cb(accepted: boolean)
	  DuelUI.showPrompt(challengerName)
	  DuelUI.showNotice(text)
	  DuelUI.showResult(payload)  -- DuelService.DuelPayload shape
]]

local Players = game:GetService("Players")

local DuelUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PROMPT_TTL = 30

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DuelUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- ---------- notice toast ----------

local notice = Instance.new("TextLabel")
notice.Name = "Notice"
notice.AnchorPoint = Vector2.new(0.5, 0)
notice.Position = UDim2.new(0.5, 0, 0, 76)
notice.Size = UDim2.fromOffset(420, 30)
notice.BackgroundColor3 = Color3.fromRGB(35, 30, 25)
notice.BackgroundTransparency = 0.2
notice.Font = Enum.Font.Gotham
notice.TextSize = 15
notice.TextColor3 = Color3.fromRGB(240, 230, 210)
notice.Visible = false
notice.Parent = screenGui

local noticeCorner = Instance.new("UICorner")
noticeCorner.CornerRadius = UDim.new(0, 10)
noticeCorner.Parent = notice

local noticeShowId = 0

function DuelUI.showNotice(text: string)
	noticeShowId += 1
	local showId = noticeShowId
	notice.Text = text
	notice.Visible = true
	task.delay(3, function()
		if noticeShowId == showId then
			notice.Visible = false
		end
	end)
end

-- ---------- challenge prompt ----------

local prompt = Instance.new("Frame")
prompt.Name = "Prompt"
prompt.AnchorPoint = Vector2.new(0.5, 0)
prompt.Position = UDim2.new(0.5, 0, 0, 110)
prompt.Size = UDim2.fromOffset(360, 88)
prompt.BackgroundColor3 = Color3.fromRGB(35, 30, 25)
prompt.BackgroundTransparency = 0.1
prompt.Visible = false
prompt.Parent = screenGui

local promptCorner = Instance.new("UICorner")
promptCorner.CornerRadius = UDim.new(0, 12)
promptCorner.Parent = prompt

local promptText = Instance.new("TextLabel")
promptText.Position = UDim2.fromOffset(0, 8)
promptText.Size = UDim2.new(1, 0, 0, 28)
promptText.BackgroundTransparency = 1
promptText.Font = Enum.Font.GothamBold
promptText.TextSize = 16
promptText.TextColor3 = Color3.fromRGB(240, 230, 210)
promptText.Parent = prompt

local function makePromptButton(text: string, xScale: number, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(xScale, 0, 1, -10)
	button.Size = UDim2.fromOffset(140, 34)
	button.Text = text
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextColor3 = Color3.fromRGB(240, 230, 210)
	button.BackgroundColor3 = color
	button.Parent = prompt

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	return button
end

local acceptButton = makePromptButton("ACCEPT", 0.27, Color3.fromRGB(70, 130, 80))
local declineButton = makePromptButton("DECLINE", 0.73, Color3.fromRGB(140, 70, 55))

local respondedCallback: ((accepted: boolean) -> ())? = nil
local promptShowId = 0

function DuelUI.onResponded(callback: (accepted: boolean) -> ())
	respondedCallback = callback
end

function DuelUI.showPrompt(challengerName: string)
	promptShowId += 1
	local showId = promptShowId
	promptText.Text = ("%s challenges your camp!"):format(challengerName)
	prompt.Visible = true
	-- Auto-hide when the server-side challenge would expire anyway.
	task.delay(PROMPT_TTL, function()
		if promptShowId == showId then
			prompt.Visible = false
		end
	end)
end

local function respond(accepted: boolean)
	if not prompt.Visible then
		return
	end
	promptShowId += 1 -- cancels the auto-hide timer
	prompt.Visible = false
	if respondedCallback then
		respondedCallback(accepted)
	end
end

acceptButton.Activated:Connect(function()
	respond(true)
end)
declineButton.Activated:Connect(function()
	respond(false)
end)

-- ---------- duel result (text version, playback replaces this) ----------

function DuelUI.showResult(payload: {
	challengerName: string,
	targetName: string,
	winner: string,
	survivorsA: number,
	survivorsB: number,
})
	local iAmChallenger = payload.challengerName == player.Name
	local mySurvivors = if iAmChallenger then payload.survivorsA else payload.survivorsB
	local theirSurvivors = if iAmChallenger then payload.survivorsB else payload.survivorsA
	local opponent = if iAmChallenger then payload.targetName else payload.challengerName
	local mySide = if iAmChallenger then "A" else "B"

	local text
	if payload.winner == "draw" then
		text = ("Draw with %s! (%d-%d)"):format(opponent, mySurvivors, theirSurvivors)
	elseif payload.winner == mySide then
		text = ("You beat %s! (%d-%d)"):format(opponent, mySurvivors, theirSurvivors)
	else
		text = ("%s beat you. (%d-%d)"):format(opponent, mySurvivors, theirSurvivors)
	end
	DuelUI.showNotice(text)
end

return DuelUI
