-- Round plumbing shared by tf_gamerules, team_round_timer and the control
-- point entities: the rules from lib_rounds, the HUD timer (what TF2 keeps in
-- CBaseTeamObjectiveResource::m_iTimerToShowInHUD), setup and overtime flags,
-- the current mini-round, and the team switch.
AddCSLuaFile("lib_rounds.lua")
TF2.RoundsLib = include("lib_rounds.lua")

local L = TF2.RoundsLib

-- teamplay_round_timer.cpp
local overtimeNag = CreateConVar("tf_overtime_nag", "0", FCVAR_NOTIFY, "Announcer overtime nag.")

-- Sounds to a chosen set of players, as TF2 plays them to each client's
-- local player (tf2.sound is received by cl_announcer.lua).
function TF2.SoundTo(players, name)
	if #players == 0 then return end
	net.Start("tf2.sound")
	net.WriteString(name)
	net.Send(players)
end

-- Every player not on the given team (spectators included), as the client's
-- "local player's team != capping team" test selects them.
function TF2.PlayersNotOn(team)
	local list = {}
	for _, ply in ipairs(player.GetAll()) do
		if ply:Team() ~= team then list[#list + 1] = ply end
	end
	return list
end

-- Setup and overtime ------------------------------------------------------------------

-- CTeamplayRoundBasedRules::SetSetup: every timer entering or leaving setup sets it.
function TF2.SetSetup(inSetup)
	SetGlobal2Bool("tf2.setup", inSetup)
end

function TF2.InSetup()
	return GetGlobal2Bool("tf2.setup", false)
end

-- CTeamplayRoundBasedRules::SetOvertime; train watchers hear it through the
-- TF2Overtime hook (the SDK sends them OnStartOvertime).
function TF2.SetOvertime(overtime)
	if GetGlobal2Bool("tf2.overtime", false) == overtime then return end
	SetGlobal2Bool("tf2.overtime", overtime)
	hook.Run("TF2Overtime", overtime)
end

function TF2.InOvertime()
	return GetGlobal2Bool("tf2.overtime", false)
end

-- The overtime nag (tf_overtime_nag): a coin flip each second.
local nextNag = 0
function TF2.OvertimeNag()
	if not overtimeNag:GetBool() or CurTime() <= nextNag then return end
	nextNag = CurTime() + 1
	if math.random(0, 1) > 0 then TF2.BroadcastSound(TF2.TEAM_UNASSIGNED, "Game.Overtime") end
end

-- CTeamplayRoundBasedRules::TimerMayExpire: a pushed cart holds the clock.
function TF2.TimerMayExpire()
	for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
		if not watcher:TimerMayExpire() then return false end
	end
	return true
end

-- The HUD timer -------------------------------------------------------------------------

local TIMER_KEYS = { "tf2.timer.show", "tf2.timer.paused", "tf2.timer.setup" }

local function ClearTimerKeys()
	for _, key in ipairs(TIMER_KEYS) do SetGlobal2Bool(key, false) end
end

-- CTeamRoundTimer::SetActiveTimer: newly (or nil) becomes the timer shown in
-- the HUD; other enabled, shown timers stop showing.
function TF2.SetActiveTimer(newly)
	local timers = ents.FindByClass("team_round_timer")
	local infos, newlyIndex = {}, nil
	for i, t in ipairs(timers) do
		infos[i] = { enabled = not t.disabled, show = t.showInHud == 1 }
		if t == newly then newlyIndex = i end
	end
	local chosen, hide = L.ChooseActiveTimer(infos, newlyIndex)
	for _, i in ipairs(hide) do timers[i].showInHud = 0 end
	TF2.HudTimer = chosen and timers[chosen] or nil
	if TF2.HudTimer then TF2.HudTimer:Publish() else ClearTimerKeys() end
end

function TF2.IsHudTimer(timer)
	return TF2.HudTimer == timer
end

-- CTeamRoundTimer::Activate for every timer, after the map (or a full reset) spawns.
function TF2.ActivateTimers()
	TF2.HudTimer = nil
	ClearTimerKeys()
	for _, t in ipairs(ents.FindByClass("team_round_timer")) do
		if t.showInHud == 1 then TF2.SetActiveTimer(t) end
	end
end

-- Without tf_gamerules nothing sends RoundSpawn, so timers run from map spawn.
hook.Add("InitPostEntity", "tf2.rounds", function()
	TF2.ActivateTimers()
	if TF2.Active() then return end
	for _, t in ipairs(ents.FindByClass("team_round_timer")) do t:RoundSpawn() end
end)

-- Control point master and mini-rounds -----------------------------------------------

-- g_hControlPointMasters[0]
function TF2.Master()
	return ents.FindByClass("team_control_point_master")[1] or NULL
end

function TF2.PlayingMiniRounds()
	local master = TF2.Master()
	return IsValid(master) and master:PlayingMiniRounds()
end

function TF2.CurrentRound()
	local master = TF2.Master()
	if not IsValid(master) then return NULL end
	return master:CurrentRound()
end

function TF2.PartialCapPointsRate()
	local master = TF2.Master()
	return IsValid(master) and master.partialCapRate or 0
end

-- CTeamplayRoundBasedRules::ShouldScorePerRound (score_style 0).
function TF2.ScorePerRound()
	local master = TF2.Master()
	return not (IsValid(master) and master:ScorePerCapture())
end

-- Team switch ----------------------------------------------------------------------------

-- Every RED player to BLU and every BLU player to RED (HandleSwitchTeams,
-- game_forcerespawn's ForceRespawnSwitchTeams). Scores are the caller's.
function TF2.SwitchTeams()
	for _, ply in ipairs(player.GetAll()) do
		local team = TF2.TeamOf(ply)
		if team ~= TF2.TEAM_UNASSIGNED then TF2.SetPlayerTeam(ply, TF2.EnemyOf(team)) end
	end
end

function TF2.SwapTeamScores()
	local red, blu = team.GetScore(TF2.TEAM_RED), team.GetScore(TF2.TEAM_BLUE)
	team.SetScore(TF2.TEAM_RED, blu)
	team.SetScore(TF2.TEAM_BLUE, red)
end

-- A round notice for the HUD (teamplay_capture_blocked and the like).
util.AddNetworkString("tf2.round.notice")
function TF2.RoundNotice(text, team)
	net.Start("tf2.round.notice")
	net.WriteString(text)
	net.WriteUInt(team, 2)
	net.Broadcast()
end
