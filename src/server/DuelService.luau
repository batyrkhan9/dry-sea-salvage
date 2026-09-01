--[[
	DuelService - the challenge flow for camp duels.

	Lifecycle: challenger clicks an opponent's camp sign ->
	challenge() validates and stores a pending challenge -> the target
	gets a prompt -> respond() either resolves the battle (both players
	receive the same event script for playback) or notifies a decline.
	Pending challenges expire after CHALLENGE_TTL seconds.

	Like the other services this module owns logic only; init.server
	provides the senders that talk to clients.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BattleResolver = require(ReplicatedStorage.Shared.BattleResolver)
local RelicUtil = require(ReplicatedStorage.Shared.RelicUtil)
local DataService = require(script.Parent.DataService)

local DuelService = {}

local CHALLENGE_TTL = 30

export type DuelPayload = {
	challengerName: string,
	targetName: string,
	winner: "A" | "B" | "draw", -- A = challenger, B = target
	survivorsA: number,
	survivorsB: number,
	events: { BattleResolver.ClashEvent },
	-- Full starting armies, so playback can stage EVERY relic (a relic
	-- that never clashes still stands on the field).
	layoutA: { BattleResolver.PlacedRelic },
	layoutB: { BattleResolver.PlacedRelic },
}

type Pending = {
	challengerUserId: number,
	expiresAt: number,
}

-- One pending challenge per TARGET; a new challenge to the same target
-- replaces an expired one but not a live one.
local pendingByTargetId: { [number]: Pending } = {}

-- Called for each participant after a duel changes their record, so the
-- camp sign can refresh. Wired to CampService by init.server.
local recordUpdated: ((player: Player) -> ())? = nil

function DuelService.setRecordUpdatedListener(listener: (player: Player) -> ())
	recordUpdated = listener
end

local sendPrompt: ((target: Player, challengerName: string) -> ())? = nil
local sendNotice: ((player: Player, text: string) -> ())? = nil
local sendResult: ((player: Player, payload: DuelPayload) -> ())? = nil

function DuelService.setPromptSender(sender: (target: Player, challengerName: string) -> ())
	sendPrompt = sender
end

function DuelService.setNoticeSender(sender: (player: Player, text: string) -> ())
	sendNotice = sender
end

function DuelService.setResultSender(sender: (player: Player, payload: DuelPayload) -> ())
	sendResult = sender
end

local function notice(player: Player, text: string)
	if sendNotice then
		sendNotice(player, text)
	end
end

-- A player's army = their placed relics. The reason distinguishes WHY
-- a camp can't fight, so notices can say something actionable ("over
-- budget" happens to layouts saved before the budget existed).
local function armyOf(player: Player): ({ BattleResolver.PlacedRelic }?, "empty" | "budget" | nil)
	local data = DataService.get(player)
	if data == nil or #data.campRelics == 0 then
		return nil, "empty"
	end
	if RelicUtil.armyCost(data.campRelics) > Config.Duel.budget then
		return nil, "budget"
	end
	return data.campRelics, nil
end

local CANT_FIGHT_SELF = {
	empty = "Deploy relics at your camp first!",
	budget = ("Your camp is over the %d-point deploy budget - pick some relics up."):format(Config.Duel.budget),
}

local CANT_FIGHT_OTHER = {
	empty = "%s has no relics deployed to fight.",
	budget = "%s's camp is over the deploy budget right now.",
}

-- Challenger clicked the target's camp sign.
function DuelService.challenge(challenger: Player, target: Player)
	if challenger == target then
		return -- clicking your own sign does nothing (for now)
	end
	local _, challengerProblem = armyOf(challenger)
	if challengerProblem ~= nil then
		notice(challenger, CANT_FIGHT_SELF[challengerProblem])
		return
	end
	local _, targetProblem = armyOf(target)
	if targetProblem ~= nil then
		notice(challenger, CANT_FIGHT_OTHER[targetProblem]:format(target.Name))
		return
	end

	local existing = pendingByTargetId[target.UserId]
	if existing ~= nil and os.clock() < existing.expiresAt then
		notice(challenger, ("%s already has a pending challenge."):format(target.Name))
		return
	end

	pendingByTargetId[target.UserId] = {
		challengerUserId = challenger.UserId,
		expiresAt = os.clock() + CHALLENGE_TTL,
	}
	if sendPrompt then
		sendPrompt(target, challenger.Name)
	end
	notice(challenger, ("Challenge sent to %s!"):format(target.Name))
end

-- The target answered their prompt.
function DuelService.respond(target: Player, accepted: boolean)
	local pending = pendingByTargetId[target.UserId]
	if pending == nil then
		return
	end
	pendingByTargetId[target.UserId] = nil

	local challenger = Players:GetPlayerByUserId(pending.challengerUserId)
	if challenger == nil then
		notice(target, "The challenger left.")
		return
	end
	if os.clock() >= pending.expiresAt then
		notice(target, "That challenge expired.")
		notice(challenger, ("%s took too long to answer."):format(target.Name))
		return
	end
	if not accepted then
		notice(challenger, ("%s declined your challenge."):format(target.Name))
		return
	end

	-- Re-validate armies at accept time: things may have moved since.
	local challengerArmy = armyOf(challenger)
	local targetArmy = armyOf(target)
	if challengerArmy == nil or targetArmy == nil then
		notice(challenger, "Duel cancelled: a camp has no relics deployed.")
		notice(target, "Duel cancelled: a camp has no relics deployed.")
		return
	end

	local result = BattleResolver.resolve(challengerArmy, targetArmy)

	-- Honor stakes: wins/losses/streak on the save. Draws change nothing.
	if result.winner ~= "draw" then
		local winnerPlayer = if result.winner == "A" then challenger else target
		local loserPlayer = if result.winner == "A" then target else challenger
		local winnerData = DataService.get(winnerPlayer)
		local loserData = DataService.get(loserPlayer)
		if winnerData ~= nil then
			winnerData.duelRecord.wins += 1
			winnerData.duelRecord.streak += 1
		end
		if loserData ~= nil then
			loserData.duelRecord.losses += 1
			loserData.duelRecord.streak = 0
		end
		if recordUpdated then
			recordUpdated(winnerPlayer)
			recordUpdated(loserPlayer)
		end
	end

	local payload: DuelPayload = {
		challengerName = challenger.Name,
		targetName = target.Name,
		winner = result.winner,
		survivorsA = result.survivorsA,
		survivorsB = result.survivorsB,
		events = result.events,
		layoutA = challengerArmy,
		layoutB = targetArmy,
	}
	print(
		("duel: %s vs %s -> %s (%d-%d)"):format(
			challenger.Name,
			target.Name,
			tostring(result.winner),
			result.survivorsA,
			result.survivorsB
		)
	)
	if sendResult then
		sendResult(challenger, payload)
		sendResult(target, payload)
	end
end

-- Forget pending challenges involving players who leave.
Players.PlayerRemoving:Connect(function(player)
	pendingByTargetId[player.UserId] = nil
	for targetId, pending in pendingByTargetId do
		if pending.challengerUserId == player.UserId then
			pendingByTargetId[targetId] = nil
		end
	end
end)

return DuelService
