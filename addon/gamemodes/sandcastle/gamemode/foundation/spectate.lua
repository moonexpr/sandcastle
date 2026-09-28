-- Pure rules of TF2's observer: death phases, mode cycling, valid targets and
-- target cycling (tf_player.cpp, player.cpp). No GMod globals: sv_spectate.lua
-- turns entities into the plain descriptors used here.
--
-- Modes are named, not numbered: "fixed", "in_eye", "chase", "roaming".
-- Target descriptors: { id, kind = "player"|"point"|"entity", team,
--   alive, deathTime (players), enabled, associatedTeam (points), train (entities) }.
-- Viewer: { id, team }. Rules: { forcecamera, teamWin, now }.
local ipairs = ipairs
module(...)

TEAM_SPECTATOR = 1
FIRST_GAME_TEAM = 2

-- mp_forcecamera values (shareddefs.h OBS_ALLOW_*)
FORCE_ALL = 0
FORCE_TEAM = 1
FORCE_NONE = 2

TIMES = {
	deathAnim = 2.0,         -- TF_DEATH_ANIMATION_TIME
	freezeTravel = 0.4,      -- spec_freeze_traveltime
	freezeTime = 4.0,        -- spec_freeze_time
	abortGrace = 0.5,        -- CTFPlayer::AttemptToExitFreezeCam
	freezeSoundLength = 0.3, -- StateThinkDYING's TFPlayer.FreezeCam lead
	watchDead = 3.0,         -- DEATH_ANIMATION_TIME (baseplayer_shared.h)
}

local function FreezeEnd(deathTime)
	return deathTime + TIMES.deathAnim + TIMES.freezeTravel + TIMES.freezeTime
end

-- CTFPlayer::StateThinkDYING: deathcam for the death animation, then the
-- freezecam on the killer, then observing. Without a killer the deathcam
-- holds until the freezecam would have ended, since nobody respawns earlier.
function DeathPhase(now, deathTime, hasKiller, aborted)
	if not deathTime or aborted then return "observer" end
	if now < deathTime + TIMES.deathAnim then return "deathcam" end
	if now >= FreezeEnd(deathTime) then return "observer" end
	return hasKiller and "freezecam" or "deathcam"
end

function CanAbortFreezeCam(now, deathTime)
	return now >= deathTime + TIMES.deathAnim + TIMES.freezeTravel + TIMES.abortGrace
end

function FreezeSoundTime(deathTime)
	return deathTime + TIMES.deathAnim + TIMES.freezeTravel - TIMES.freezeSoundLength
end

-- spec_mode steps IN_EYE -> CHASE -> (POI) -> ROAMING -> IN_EYE, and
-- CTFPlayer::SetObserverMode turns ROAMING into IN_EYE for team players.
local NEXT = { fixed = "in_eye", in_eye = "chase", chase = "roaming", roaming = "in_eye" }
function NextMode(mode, isSpectator)
	local nextMode = NEXT[mode]
	if nextMode == "roaming" and not isSpectator then return "in_eye" end
	return nextMode
end

-- The mode the camera shows for a target kind. Roaming stays roaming (it
-- starts from the target). An observer point is a fixed camera
-- (C_BasePlayer::CalcChaseCamView treats a model-less target so); only
-- players can be watched in-eye (CTFPlayer::ValidateCurrentObserverTarget);
-- without a target the view holds still (ValidateCurrentObserverTarget, TF_DLL).
function ViewMode(mode, kind)
	if mode == "roaming" then return "roaming" end
	if kind == "point" or kind == nil then return "fixed" end
	if kind == "entity" and mode ~= "chase" then return "chase" end
	return mode
end

-- CObserverPoint::CanUseObserverPoint (without the mini-round check).
local function CanUsePoint(viewer, point, rules)
	if not point.enabled then return false end
	if point.associatedTeam and rules.forcecamera == FORCE_TEAM and not rules.teamWin
		and point.associatedTeam ~= viewer.team and viewer.team >= FIRST_GAME_TEAM then
		return false
	end
	return true
end

local function ForceCameraAllows(viewer, targetTeam, rules)
	if rules.forcecamera == FORCE_TEAM then return targetTeam == viewer.team end
	return rules.forcecamera == FORCE_ALL
end

-- CTFPlayer::IsValidObserverTarget, non-player branch.
local function ValidEntity(viewer, target, rules)
	if target.kind == "point" and not CanUsePoint(viewer, target, rules) then return false end
	if target.train and rules.teamWin then return false end
	if viewer.team == TEAM_SPECTATOR then return true end
	if target.team == 0 and rules.forcecamera ~= FORCE_NONE then return true end
	return ForceCameraAllows(viewer, target.team, rules)
end

-- CBasePlayer::IsValidObserverTarget: live players, or the recently dead.
local function ValidPlayer(viewer, target, rules)
	if not target.alive then
		if not target.deathTime or rules.now > target.deathTime + TIMES.watchDead then return false end
	end
	if viewer.team == TEAM_SPECTATOR then return true end
	return ForceCameraAllows(viewer, target.team, rules)
end

function IsValidTarget(viewer, target, rules)
	if not target or target.id == viewer.id then return false end
	if target.kind == "player" then return ValidPlayer(viewer, target, rules) end
	return ValidEntity(viewer, target, rules)
end

-- CTFPlayer::FindNextObserverTarget over the observable list. current is the
-- index of the present target or nil; returns an index or nil.
function FindNext(list, current, reverse, valid)
	local n = #list
	if n == 0 then return nil end
	local dir = reverse and -1 or 1
	local start = ((current or (reverse and 1 or 0)) - 1 + dir) % n + 1
	local i = start
	repeat
		if valid(list[i]) then return i end
		i = (i - 1 + dir) % n + 1
	until i == start
	return nil
end

-- CTFPlayer::FindNearestObservableTarget, by each candidate's precomputed dist.
function Nearest(list, valid)
	local best, bestDist
	for i, c in ipairs(list) do
		if valid(c) and (not bestDist or c.dist < bestDist) then
			best, bestDist = i, c.dist
		end
	end
	return best
end

-- CTFPlayer::PickWelcomeObserverPoint: walks the points taking each usable
-- one, and stops at the first marked defaultwelcome.
function WelcomePoint(points, valid)
	local chosen
	for i, p in ipairs(points) do
		if valid(p) then chosen = i end
		if p.welcome then break end
	end
	return chosen
end
