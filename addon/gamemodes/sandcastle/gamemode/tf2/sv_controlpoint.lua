-- team_control_point. GMod's engine already has a class by this name, which
-- wins over a Lua entity of the same name, and it is inert: it shows its model
-- but keeps none of TF2's state. So the TF2 behaviour lives here, beside each
-- engine control point: its keyvalues and outputs are recorded as the map sets
-- them (sv_world.lua), its inputs are taken through AcceptInput, and its outputs
-- are fired from the recording. Behaviour follows CTeamControlPoint
-- (team_control_point.cpp) and CTFGameRules::TeamMayCapturePoint.

-- team_control_point.h spawnflags
local SF_HIDE_MODEL = 2
local DEFAULT_MODEL = "models/effects/cappoint_hologram.mdl"
local DEFAULT_WARN_SOUND = "ControlPoint.CaptureWarn"
-- The client's spam guard on the final-cap warning (C_BaseTeamObjectiveResource::ClientThink).
local WARN_INTERVAL = 5
local MAX_PREVIOUS_POINTS = 3

-- TF2's convar (tf_gamerules.cpp).
local caplinear = CreateConVar("tf_caplinear", "1", FCVAR_REPLICATED, "If set to 1, teams must capture control points linearly.")

local function State(ent)
	local kv = TF2.KeyValues(ent)
	if kv.owner == nil then
		kv.owner = tonumber(kv.point_default_owner) or TF2.TEAM_UNASSIGNED
		kv.locked = kv.point_start_locked == "1"
	end
	return kv
end

-- CTeamControlPoint::SetModel: the owning team's model, bodygroup 0 set to the
-- team, and skin 2 for neutral or team - 2 (0 RED, 1 BLU).
function TF2.ApplyPointModel(ent)
	local s = State(ent)
	local team = s.owner
	local model = s["team_model_" .. team]
	if not model or model == "" then model = DEFAULT_MODEL end
	if ent:GetModel() ~= model and util.IsValidModel(model) then ent:SetModel(model) end
	ent:SetBodygroup(0, team)
	ent:SetSkin(team == TF2.TEAM_UNASSIGNED and 2 or team - 2)
	if bit.band(tonumber(s.spawnflags) or 0, SF_HIDE_MODEL) ~= 0 then ent:SetNoDraw(true) end
end

function TF2.CapTeam(ent)
	return State(ent).owner
end

function TF2.PointLocked(ent)
	return State(ent).locked
end

-- The map's point_index. TF2 renumbers points 0..n-1 in this order
-- (CTeamControlPointMaster::FindControlPoints); TF2.PointRank gives that number.
function TF2.PointIndex(ent)
	return tonumber(State(ent).point_index) or 0
end

function TF2.PointGroup(ent)
	return tonumber(State(ent).point_group) or 0
end

function TF2.PointDefaultOwner(ent)
	return tonumber(State(ent).point_default_owner) or TF2.TEAM_UNASSIGNED
end

-- Every control point, ordered by index, with each one's rank.
function TF2.ControlPoints()
	local points = ents.FindByClass("team_control_point")
	local indices = {}
	for i, p in ipairs(points) do indices[i] = TF2.PointIndex(p) end
	local ranks = TF2.RoundsLib.Ranks(indices)
	local ordered, rankOf = {}, {}
	for i, p in ipairs(points) do
		ordered[ranks[i] + 1] = p
		rankOf[p] = ranks[i]
	end
	return ordered, rankOf
end

function TF2.PointRank(ent)
	local _, rankOf = TF2.ControlPoints()
	return rankOf[ent]
end

-- Owner changes ---------------------------------------------------------------------

local function CheckMasters()
	for _, master in ipairs(ents.FindByClass("team_control_point_master")) do
		if master:IsActive() then master:CheckWinConditions() end
	end
end

-- CTeamControlPoint::InternalSetOwner. makeSound marks a true capture by
-- players: the team's cap sound, OnOwnerChangedToTeam, the capture notice.
local function InternalSetOwner(ent, team, makeSound, activator)
	local s = State(ent)
	s.owner = team
	if makeSound then
		local sound = s["team_capsound_" .. team]
		if sound and sound ~= "" then ent:EmitSound(sound) end
	end
	TF2.ApplyPointModel(ent)
	activator = activator or ent
	if team == TF2.TEAM_UNASSIGNED then
		TF2.FireOutput(ent, "OnCapReset", activator)
	else
		TF2.FireOutput(ent, team == TF2.TEAM_RED and "OnCapTeam1" or "OnCapTeam2", activator)
	end
	if makeSound and team ~= TF2.TEAM_UNASSIGNED then
		TF2.FireOutput(ent, team == TF2.TEAM_RED and "OnOwnerChangedToTeam1" or "OnOwnerChangedToTeam2", activator)
		TF2.Announce(TF2.TeamName[team] .. " captured point " .. TF2.PointIndex(ent), team)
	end
	hook.Run("TF2PointCaptured", ent, team)
	CheckMasters()
end

-- CTeamControlPoint::HandleScoring: with score_style 1 each capture scores a
-- point, with the scored chime unless the capture wins the game (everyone
-- hears it on payload maps, only the team elsewhere).
local function HandleScoring(ent, capTeam)
	if TF2.ScorePerRound() or capTeam == TF2.TEAM_UNASSIGNED then return end
	team.AddScore(capTeam, 1)
	local master = TF2.Master()
	if not IsValid(master) or master:WouldNewOwnerWin(ent, capTeam) then return end
	local escort = #ents.FindByClass("team_train_watcher") > 0
	TF2.BroadcastSound(escort and TF2.TEAM_UNASSIGNED or capTeam, "Hud.EndRoundScored")
end

local function PointsMayBeCaptured()
	return not IsValid(TF2.Rules) or TF2.Rules:PointsMayBeCaptured()
end

-- CTeamControlPoint::SetOwner: a capture by players (a capture area).
function TF2.SetPointOwner(ent, team, activator)
	if not PointsMayBeCaptured() then return end
	HandleScoring(ent, team)
	InternalSetOwner(ent, team, true, activator)
end

-- CTeamControlPoint::ForceOwner: set by the game, no capture.
function TF2.ForcePointOwner(ent, team)
	InternalSetOwner(ent, team, false)
end

-- Locks ----------------------------------------------------------------------------------

-- CTeamControlPoint::InternalSetLocked: OnUnlocked fires whenever the point
-- is set unlocked, including at round start for a point that was never locked.
local function SetLocked(ent, locked)
	local s = State(ent)
	s.locked = locked
	if not locked then
		s.unlockAt = nil
		TF2.FireOutput(ent, "OnUnlocked", ent)
	end
end

local function SetUnlockTime(ent, seconds)
	if seconds <= 0 then
		SetLocked(ent, false)
		return
	end
	State(ent).unlockAt = CurTime() + seconds
end

-- CTeamControlPoint::UnlockThink: the timed unlock waits for the round to run.
timer.Create("tf2.controlpoint.unlock", 0.1, 0, function()
	if TF2.Active() and TF2.State() ~= TF2.STATE.RND_RUNNING then return end
	for _, ent in ipairs(ents.FindByClass("team_control_point")) do
		local at = TF2.KeyValues(ent).unlockAt
		if at and at < CurTime() then SetLocked(ent, false) end
	end
end)

-- CTeamControlPoint::InputRoundActivate, sent at every round start.
function TF2.PointRoundActivate(ent)
	local team = TF2.CapTeam(ent)
	if team == TF2.TEAM_RED then TF2.FireOutput(ent, "OnRoundStartOwnedByTeam1", ent) end
	if team == TF2.TEAM_BLUE then TF2.FireOutput(ent, "OnRoundStartOwnedByTeam2", ent) end
	TF2.ApplyPointModel(ent)
	SetLocked(ent, TF2.PointLocked(ent))
end

-- Who may capture ---------------------------------------------------------------------------

-- team_previouspoint_<team>_<n>, as ranks; -1 where unset or unknown.
local function PreviousPoints(ent, team, rankOf)
	local s = State(ent)
	local previous = {}
	for n = 0, MAX_PREVIOUS_POINTS - 1 do
		local point = TF2.FindByName(s["team_previouspoint_" .. team .. "_" .. n])
		previous[n + 1] = IsValid(point) and rankOf[point] or -1
	end
	return previous
end

-- CTFGameRules::TeamMayCapturePoint, plus the capture area's own tests: the
-- team does not own the point, and with mini-rounds the point is in play.
function TF2.TeamCanCapPoint(point, team)
	if team ~= TF2.TEAM_RED and team ~= TF2.TEAM_BLUE then return false end
	if TF2.CapTeam(point) == team then return false end
	local master = TF2.Master()
	local mini = IsValid(master) and master:PlayingMiniRounds()
	if mini and not master:IsInRound(point) then return false end

	local ordered, rankOf = TF2.ControlPoints()
	local owners, bases = {}, {}
	for rank, p in ipairs(ordered) do
		owners[rank - 1] = TF2.CapTeam(p)
		bases[rank] = { index = rank - 1, defaultOwner = TF2.PointDefaultOwner(p) }
	end
	return TF2.RoundsLib.TeamMayCapturePoint({
		caplinear = caplinear:GetBool(),
		index = rankOf[point],
		team = team,
		locked = TF2.PointLocked(point),
		previous = PreviousPoints(point, team, rankOf),
		playingMiniRounds = mini,
		owners = owners,
		count = #ordered,
		base = TF2.RoundsLib.BaseControlPoint(team, bases),
	})
end

-- A team started capturing (CTeamControlPoint::CaptureStart, with what the
-- client does on it: C_TFObjectiveResource::SetCappingTeam's "our point is
-- being contested", or the final-cap warning for point_warn_on_cap 1).
function TF2.PointCaptureStarted(point, team)
	local s = State(point)
	local warn = tonumber(s.point_warn_on_cap) or TF2.RoundsLib.CP_WARN.NORMAL
	if warn == TF2.RoundsLib.CP_WARN.NORMAL and team ~= TF2.TEAM_UNASSIGNED then
		local line = s.owner ~= TF2.TEAM_UNASSIGNED and "Announcer.ControlPointContested" or "Announcer.ControlPointContested_Neutral"
		TF2.SoundTo(TF2.PlayersNotOn(team), line)
	elseif warn == TF2.RoundsLib.CP_WARN.FINALCAP and CurTime() > (s.lastWarn or -math.huge) + WARN_INTERVAL then
		s.lastWarn = CurTime()
		local sound = s.point_warn_sound
		if not sound or sound == "" then sound = DEFAULT_WARN_SOUND end
		TF2.SoundTo(TF2.PlayersNotOn(team), sound)
	end
	hook.Run("TF2PointCaptureStarted", point, team)
end

-- The team that blocked a capture (CTeamControlPoint::CaptureBlocked): the
-- HUD's "defended" notice, only for points with a print name.
function TF2.PointCaptureBlocked(point, team)
	local name = State(point).point_printname
	if name and name ~= "" then
		TF2.RoundNotice(TF2.TeamName[team] .. " defended " .. name, team)
	end
	hook.Run("TF2PointCaptureBlocked", point, team)
end

-- Inputs ------------------------------------------------------------------------------------

local INPUTS = {
	-- CTeamControlPoint::InputSetOwner: a sounding capture only when a player sent it.
	setowner = function(ent, value, activator, caller)
		local team = tonumber(value) or 0
		if TF2.CapTeam(ent) == team or not PointsMayBeCaptured() then return end
		HandleScoring(ent, team)
		InternalSetOwner(ent, team, IsValid(caller) and caller:IsPlayer(), activator)
	end,
	setlocked = function(ent, value) SetLocked(ent, (tonumber(value) or 0) > 0) end,
	setunlocktime = function(ent, value) SetUnlockTime(ent, tonumber(value) or 0) end,
	hidemodel = function(ent) ent:SetNoDraw(true) end,
	showmodel = function(ent) ent:SetNoDraw(false) end,
	roundactivate = function(ent) TF2.PointRoundActivate(ent) end,
}

hook.Add("AcceptInput", "tf2.controlpoint", function(ent, input, activator, caller, value)
	if ent:GetClass() ~= "team_control_point" then return end
	local handler = INPUTS[string.lower(input)]
	if not handler then return end
	handler(ent, value, activator, caller)
	return true
end)

-- Show each point in its owner's colours as soon as the map (or a round reset)
-- has spawned, not only once the round goes active.
local function ApplyAll()
	for _, ent in ipairs(ents.FindByClass("team_control_point")) do
		TF2.ApplyPointModel(ent)
	end
end
hook.Add("InitPostEntity", "tf2.controlpoint", ApplyAll)
hook.Add("PostCleanupMap", "tf2.controlpoint", ApplyAll)
