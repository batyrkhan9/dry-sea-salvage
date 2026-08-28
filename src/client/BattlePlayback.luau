--[[
	BattlePlayback - animates a duel's event script so players SEE why
	each clash went the way it did (the counter wheel teaching itself).

	The stage is built at the map center from LOCAL parts - every client
	plays the same server-resolved script, so what you watch is exactly
	what was scored. Flow per clash: both crates slide to the middle of
	their column, a caption explains the outcome, losers sink into the
	sand, the winner slides back. Then the camera returns and the
	onFinished callback fires (init.client routes it to the result text).

	If a payload arrives while a playback is running, the animation is
	skipped for it (onFinished still fires) - no queueing complexity.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local RelicUtil = require(ReplicatedStorage.Shared.RelicUtil)

local BattlePlayback = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GROUND_Y = 0
local COLUMN_SPACING = 8 -- studs between columns on the stage
local ROW_SPACING = 6 -- studs between ranks behind the front line
local FRONT_GAP = 10 -- distance from mid-line to each side's front rank
local CRATE = 4 -- crate edge length

-- ---------- caption overlay ----------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BattlePlayback"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local caption = Instance.new("TextLabel")
caption.AnchorPoint = Vector2.new(0.5, 0)
caption.Position = UDim2.new(0.5, 0, 0, 60)
caption.Size = UDim2.fromOffset(560, 34)
caption.BackgroundColor3 = Color3.fromRGB(35, 30, 25)
caption.BackgroundTransparency = 0.15
caption.Font = Enum.Font.GothamBold
caption.TextSize = 17
caption.TextColor3 = Color3.fromRGB(240, 230, 210)
caption.Visible = false
caption.Parent = screenGui

local captionCorner = Instance.new("UICorner")
captionCorner.CornerRadius = UDim.new(0, 10)
captionCorner.Parent = caption

-- ---------- crate building ----------

type PlacedRelic = { relicName: string, cellX: number, cellZ: number }

-- Key a relic by its home cell so events can find its crate.
local function keyOf(side: string, relic: PlacedRelic): string
	return ("%s_%d_%d"):format(side, relic.cellX, relic.cellZ)
end

-- Stage slot for a relic. Side A fights toward +Z, side B toward -Z;
-- higher cellZ = closer to the front for both (mirrored).
local function slotCFrame(side: string, relic: PlacedRelic): CFrame
	local x = (relic.cellX - (Config.Camp.gridCells + 1) / 2) * COLUMN_SPACING
	local depth = FRONT_GAP + (Config.Camp.gridCells - relic.cellZ) * ROW_SPACING
	local z = if side == "A" then -depth else depth
	return CFrame.new(x, GROUND_Y + CRATE / 2, z)
end

local function buildCrate(side: string, relic: PlacedRelic, folder: Folder): Part
	local rarityName = RelicUtil.rarityOf(relic.relicName) or "?"
	local crate = Instance.new("Part")
	crate.Name = keyOf(side, relic)
	crate.Anchored = true
	crate.CanCollide = false
	crate.Size = Vector3.new(CRATE, CRATE, CRATE)
	crate.CFrame = slotCFrame(side, relic)
	crate.Material = Enum.Material.Metal
	crate.Color = RelicUtil.rarityColor(rarityName)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(130, 20)
	billboard.StudsOffset = Vector3.new(0, CRATE / 2 + 1, 0)
	billboard.MaxDistance = 250
	billboard.Parent = crate

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(240, 230, 210)
	label.TextStrokeTransparency = 0.5
	label.Text = relic.relicName
	label.Parent = billboard

	crate.Parent = folder
	return crate
end

-- ---------- clash captions ----------

-- How each winning role deals with its countered role - the caption
-- leads with the RULE so the wheel teaches itself.
local COUNTER_VERBS = {
	["Breaker"] = "BREAKER smashes GUARD",
	["Guard"] = "GUARD outlasts TRAP",
	["Trap"] = "TRAP catches BREAKER",
}

local function describe(event: any): string
	local aName = event.aRelic.relicName
	local bName = event.bRelic.relicName

	if event.reason == "counter" then
		local winName = if event.winner == "A" then aName else bName
		local loseName = if event.winner == "A" then bName else aName
		local winRole = RelicUtil.roleOf(winName) or "?"
		return ("%s! %s takes down %s."):format(COUNTER_VERBS[winRole] or "COUNTER", winName, loseName)
	elseif event.reason == "scout" then
		local scoutName = if event.winner == "A" then bName else aName
		return ("%s is a SCOUT - scouts support, they don't fight!"):format(scoutName)
	elseif event.reason == "tier" then
		local winName = if event.winner == "A" then aName else bName
		local loseName = if event.winner == "A" then bName else aName
		return ("No counter either way - %s wins on higher tier over %s."):format(winName, loseName)
	end
	return ("%s and %s are dead even - both exhaust!"):format(aName, bName)
end

-- ---------- playback ----------

local function tweenTo(part: Part, cframe: CFrame, seconds: number)
	local tween = TweenService:Create(
		part,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = cframe }
	)
	tween:Play()
	tween.Completed:Wait()
end

local function sink(part: Part)
	TweenService:Create(
		part,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = part.CFrame * CFrame.new(0, -CRATE - 1, 0), Transparency = 1 }
	):Play()
	task.delay(0.7, function()
		part:Destroy()
	end)
end

local finishedCallback: ((payload: any) -> ())? = nil

function BattlePlayback.onFinished(callback: (payload: any) -> ())
	finishedCallback = callback
end

local playing = false

function BattlePlayback.play(payload: {
	challengerName: string,
	targetName: string,
	winner: string,
	survivorsA: number,
	survivorsB: number,
	events: { any },
})
	if playing then
		-- A second duel resolved mid-playback: skip its animation.
		if finishedCallback then
			finishedCallback(payload)
		end
		return
	end
	playing = true

	task.spawn(function()
		local stage = Instance.new("Folder")
		stage.Name = "BattleStage"
		stage.Parent = Workspace

		-- Stage BOTH full armies in their board formations - relics that
		-- never clash still stand on the field (and survive visibly).
		local crates: { [string]: Part } = {}
		for _, relic in payload.layoutA do
			crates[keyOf("A", relic)] = buildCrate("A", relic, stage)
		end
		for _, relic in payload.layoutB do
			crates[keyOf("B", relic)] = buildCrate("B", relic, stage)
		end

		-- Camera: hold a side view of the stage for the whole battle.
		local camera = Workspace.CurrentCamera
		local savedCameraType = camera.CameraType
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(Vector3.new(-70, 55, 0), Vector3.new(0, GROUND_Y + 2, 0))

		caption.Text = ("%s vs %s!"):format(payload.challengerName, payload.targetName)
		caption.Visible = true
		task.wait(1.2)

		for _, event in payload.events do
			local aCrate = crates[keyOf("A", event.aRelic)]
			local bCrate = crates[keyOf("B", event.bRelic)]
			if aCrate == nil or bCrate == nil then
				continue
			end

			-- Front fighters meet at the center of the field.
			local aMeet = CFrame.new(0, GROUND_Y + CRATE / 2, -CRATE / 2 - 0.6)
			local bMeet = CFrame.new(0, GROUND_Y + CRATE / 2, CRATE / 2 + 0.6)
			local aHome = aCrate.CFrame
			local bHome = bCrate.CFrame
			task.spawn(tweenTo, aCrate, aMeet, 0.45)
			tweenTo(bCrate, bMeet, 0.45)

			caption.Text = describe(event)
			task.wait(1.1)

			if event.winner == "A" then
				sink(bCrate)
				crates[keyOf("B", event.bRelic)] = nil
				tweenTo(aCrate, aHome, 0.4)
			elseif event.winner == "B" then
				sink(aCrate)
				crates[keyOf("A", event.aRelic)] = nil
				tweenTo(bCrate, bHome, 0.4)
			else
				sink(aCrate)
				sink(bCrate)
				crates[keyOf("A", event.aRelic)] = nil
				crates[keyOf("B", event.bRelic)] = nil
				task.wait(0.5)
			end
			task.wait(0.25)
		end

		task.wait(0.8)
		caption.Visible = false
		stage:Destroy()
		camera.CameraType = savedCameraType
		playing = false

		if finishedCallback then
			finishedCallback(payload)
		end
	end)
end

return BattlePlayback
