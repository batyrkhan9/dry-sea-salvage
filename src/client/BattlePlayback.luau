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
local BattleResolver = require(ReplicatedStorage.Shared.BattleResolver)

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

-- HP cards by crate key, so clashes can update the bars.
type HpCard = {
	fill: Frame,
	hpText: TextLabel,
	maxHp: number,
}
local cards: { [string]: HpCard } = {}

local HP_GREEN = Color3.fromRGB(110, 200, 110)
local HP_RED = Color3.fromRGB(200, 90, 70)

local function setCardHp(card: HpCard, hp: number)
	local fraction = math.clamp(hp / card.maxHp, 0, 1)
	card.fill.Size = UDim2.fromScale(fraction, 1)
	card.fill.BackgroundColor3 = if fraction > 0.35 then HP_GREEN else HP_RED
	card.hpText.Text = ("%d/%d"):format(hp, card.maxHp)
end

-- Builds the always-readable overhead card: name, live HP bar, ATK.
local function buildCard(crate: Part, relic: PlacedRelic, startHp: number)
	local def = RelicUtil.defOf(relic.relicName)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(150, 54)
	billboard.StudsOffset = Vector3.new(0, CRATE / 2 + 2.2, 0)
	billboard.AlwaysOnTop = true -- readable at battle-camera distance
	billboard.Parent = crate

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromScale(1, 0.38)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.fromRGB(240, 230, 210)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Text = relic.relicName
	nameLabel.Parent = billboard

	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.fromScale(0.1, 0.42)
	barBack.Size = UDim2.fromScale(0.8, 0.26)
	barBack.BackgroundColor3 = Color3.fromRGB(30, 26, 22)
	barBack.BorderSizePixel = 0
	barBack.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = HP_GREEN
	fill.BorderSizePixel = 0
	fill.Parent = barBack

	local hpText = Instance.new("TextLabel")
	hpText.Size = UDim2.fromScale(1, 1)
	hpText.BackgroundTransparency = 1
	hpText.Font = Enum.Font.GothamBold
	hpText.TextScaled = true
	hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpText.TextStrokeTransparency = 0.2
	hpText.Parent = barBack

	local atkLabel = Instance.new("TextLabel")
	atkLabel.Position = UDim2.fromScale(0, 0.7)
	atkLabel.Size = UDim2.fromScale(1, 0.3)
	atkLabel.BackgroundTransparency = 1
	atkLabel.Font = Enum.Font.Gotham
	atkLabel.TextScaled = true
	atkLabel.TextColor3 = Color3.fromRGB(230, 190, 100)
	atkLabel.TextStrokeTransparency = 0.4
	atkLabel.Text = ("ATK %d"):format(if def then def.atk else 0)
	atkLabel.Parent = billboard

	local card: HpCard = { fill = fill, hpText = hpText, maxHp = math.max(startHp, 1) }
	setCardHp(card, startHp)
	return card
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
	crate.Parent = folder
	return crate
end

-- ---------- clash captions ----------

-- Captions narrate the arithmetic so the trade-offs teach themselves.
local function describe(event: any): string
	local aName = event.aRelic.relicName
	local bName = event.bRelic.relicName

	if event.winner == "none" then
		return ("%s and %s take each other down!"):format(aName, bName)
	end
	local winName = if event.winner == "A" then aName else bName
	local loseName = if event.winner == "A" then bName else aName
	local winHp = if event.winner == "A" then event.aHpEnd else event.bHpEnd
	if event.rounds == 0 then
		return ("Ambush! %s springs first - %s falls before it can strike back!"):format(winName, loseName)
	end
	local opener = if event.ambushBy ~= "none" then "Ambush, then a brawl: " else ""
	return ("%s%s falls after %d blows - %s stands with %d HP left."):format(
		opener,
		loseName,
		event.rounds,
		winName,
		winHp
	)
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
		table.clear(cards) -- drop card refs from any previous battle
		local stage = Instance.new("Folder")
		stage.Name = "BattleStage"
		stage.Parent = Workspace

		-- Stage BOTH full armies in their board formations - relics that
		-- never clash still stand on the field (and survive visibly).
		-- HP cards start at aura-braced values, same as the resolver.
		local bracedA = BattleResolver.startingHp(payload.layoutA)
		local bracedB = BattleResolver.startingHp(payload.layoutB)
		local crates: { [string]: Part } = {}
		for _, relic in payload.layoutA do
			local crate = buildCrate("A", relic, stage)
			crates[keyOf("A", relic)] = crate
			cards[keyOf("A", relic)] = buildCard(crate, relic, bracedA[relic.cellX .. "_" .. relic.cellZ] or 1)
		end
		for _, relic in payload.layoutB do
			local crate = buildCrate("B", relic, stage)
			crates[keyOf("B", relic)] = crate
			cards[keyOf("B", relic)] = buildCard(crate, relic, bracedB[relic.cellX .. "_" .. relic.cellZ] or 1)
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

			-- Update both bars to the clash outcome BEFORE anyone sinks,
			-- so the fatal blow is visible on the card.
			local aCard = cards[keyOf("A", event.aRelic)]
			local bCard = cards[keyOf("B", event.bRelic)]
			if aCard then
				setCardHp(aCard, event.aHpEnd)
			end
			if bCard then
				setCardHp(bCard, event.bHpEnd)
			end
			task.wait(0.35)

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
