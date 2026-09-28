-- Pure round logic, from TF2's own code (source-sdk-2013): mini-round
-- selection and win checks (team_control_point_master.cpp,
-- team_control_point_round.cpp), game limits and sudden death
-- (teamplayroundbased_gamerules.cpp), capture order (CTFGameRules::
-- TeamMayCapturePoint), the timer's outputs (teamplay_round_timer.cpp) and the
-- win panel (tf_hud_winpanel.cpp). No GMod globals; randomness is passed in.
local R = {}

-- teamplayroundbased_gamerules.h
R.WINREASON = {
	NONE = 0, ALL_POINTS_CAPTURED = 1, OPPONENTS_DEAD = 2, FLAG_CAPTURE_LIMIT = 3,
	DEFEND_UNTIL_TIME_LIMIT = 4, STALEMATE = 5, TIMELIMIT = 6, WINLIMIT = 7, WINDIFFLIMIT = 8,
}
R.STALEMATE = { JOIN_MID = 0, TIMER = 1, SERVER_TIMELIMIT = 2 }
-- shareddefs.h: point_warn_on_cap
R.CP_WARN = { NORMAL = 0, FINALCAP = 1, NO_ANNOUNCEMENTS = 2 }

local FIRST_GAME_TEAM = 2
local TEAM_INVALID = -1

-- Control points and rounds ---------------------------------------------------------

-- TeamOwnsAllPoints: points is a list of { owner, group }. Each group is won by
-- a team owning every point in it; the lowest-numbered won group reports.
function R.TeamOwnsAllPoints(points)
	local byGroup = {}
	for _, p in ipairs(points) do
		local g = byGroup[p.group]
		if g == nil then
			byGroup[p.group] = p.owner
		elseif g ~= 0 and p.owner ~= g then
			byGroup[p.group] = 0
		end
	end
	local groups = {}
	for group in pairs(byGroup) do groups[#groups + 1] = group end
	table.sort(groups)
	for _, group in ipairs(groups) do
		if byGroup[group] >= FIRST_GAME_TEAM then return byGroup[group] end
	end
	return 0
end

-- CTeamControlPointRound::CheckWinConditions (and the master's own check when
-- the map has no rounds): the winner, or nil. restrict 1 means nobody.
function R.RoundWinner(restrict, points)
	local winner = R.TeamOwnsAllPoints(points)
	if restrict ~= 1 and winner >= FIRST_GAME_TEAM and winner ~= restrict then return winner end
	return nil
end

-- CTeamControlPointRound::IsPlayable
function R.RoundPlayable(restrict, points)
	if restrict == 1 then return true end
	return R.RoundWinner(restrict, points) == nil
end

function R.PlayableCount(rounds)
	local n = 0
	for _, r in ipairs(rounds) do
		if r.playable then n = n + 1 end
	end
	return n
end

local function ByPriority(rounds)
	local order = {}
	for i = 1, #rounds do order[i] = i end
	table.sort(order, function(a, b)
		if rounds[a].priority ~= rounds[b].priority then return rounds[a].priority > rounds[b].priority end
		return a < b
	end)
	return order
end

-- The 1-based stage of round i: its place in priority order (highest first),
-- which is the order multi-stage maps play their rounds in.
function R.StageOf(rounds, i)
	for stage, j in ipairs(ByPriority(rounds)) do
		if j == i then return stage end
	end
end

local function Contains(list, value)
	for i, v in ipairs(list) do
		if v == value then return i end
	end
end

-- CTeamControlPointMaster::GetControlPointRoundToPlay. rounds: { name,
-- priority, playable }; history: { previous = the last two played, most recent
-- first; first = the first round played after the last full restart;
-- firstAfterRestart }; random(n) returns 1..n. Returns the chosen index or nil.
function R.ChooseRound(rounds, history, random)
	local order = ByPriority(rounds)
	local priority
	for _, i in ipairs(order) do
		if rounds[i].playable then priority = rounds[i].priority break end
	end
	if priority == nil then return nil end

	local candidates = {}
	for _, i in ipairs(order) do
		if rounds[i].playable and rounds[i].priority == priority then candidates[#candidates + 1] = i end
	end

	local function Drop(name)
		if #candidates < 2 or name == nil then return end
		for k, i in ipairs(candidates) do
			if rounds[i].name == name then table.remove(candidates, k) return end
		end
	end
	Drop(history.previous[1])
	if history.firstAfterRestart then Drop(history.first) end

	local k = random(#candidates)
	while #candidates > 1 and Contains(history.previous, rounds[candidates[k]].name) do
		table.remove(candidates, k)
		k = random(#candidates)
	end
	return candidates[k]
end

-- CTeamplayRoundBasedRules::AddPlayedRound: remember the last two.
function R.AddPlayedRound(previous, name)
	local list = { name, previous[1] }
	return list
end

-- CTeamControlPointMaster::CalcNumRoundsRemaining: how many more mini-rounds a
-- team must win to own every point. rounds: { restrict, points = indices into
-- points }; points: { owner }. Unlike IsPlayable this ignores point groups.
-- It stops when no round makes progress (the SDK would loop forever there).
function R.RoundsRemaining(team, rounds, points)
	local owned, count = {}, 0
	for i, p in ipairs(points) do
		if p.owner == team then owned[i] = true count = count + 1 end
	end
	local remaining = 0
	while count < #points do
		local progressed = false
		for _, r in ipairs(rounds) do
			local roundOwner
			for k, i in ipairs(r.points) do
				local owner = owned[i] and team or points[i].owner
				if k == 1 then roundOwner = owner elseif roundOwner ~= owner then roundOwner = TEAM_INVALID end
			end
			local playable = roundOwner == nil or roundOwner < FIRST_GAME_TEAM or r.restrict == 1 or roundOwner == r.restrict
			if playable then
				for _, i in ipairs(r.points) do
					if not owned[i] then owned[i] = true count = count + 1 progressed = true end
				end
				if progressed then break end
			end
		end
		if not progressed then break end
		remaining = remaining + 1
	end
	return remaining
end

-- Sudden death and limits --------------------------------------------------------------

-- State_Think_STALEMATE: teams[t] = { players, alive }. A team with no live
-- player (or no players) is dead. Returns the surviving team when exactly
-- one side is dead, and whether everyone is dead.
function R.StalemateOutcome(teams)
	local dead, alive
	for t = 2, 3 do
		if teams[t].players > 0 and teams[t].alive > 0 then alive = t else dead = t end
	end
	if dead and alive then return alive, false end
	return nil, dead ~= nil and alive == nil
end

-- CTeamplayRoundBasedRules::GetTimeLeft
function R.TimeLeft(mapResetTime, timelimitMinutes, now)
	return math.max(0, math.floor(mapResetTime + timelimitMinutes * 60 - now))
end

-- CheckWinLimit
function R.WinLimitReached(winlimit, scores)
	if winlimit <= 0 then return false end
	return scores[2] >= winlimit or scores[3] >= winlimit
end

-- CheckMaxRounds
function R.MaxRoundsReached(maxrounds, roundsPlayed)
	return maxrounds > 0 and roundsPlayed >= maxrounds
end

-- CTFGameRules::CanChangelevelBecauseOfTimeLimit: maps like Dustbowl play all
-- their mini-rounds before the time limit may change the level.
function R.CanChangeLevelForTimeLimit(forceMapReset, playingMiniRounds, playAllRounds, playable)
	return not (not forceMapReset and playingMiniRounds and playAllRounds and playable > 0)
end

-- CheckTimeLimit: c = { timelimit (minutes), timeLeft, canChange, afterStalemate }.
-- Under five minutes left the level changes now, so sudden death never starts
-- just after a new round.
function R.TimeLimitReached(c)
	if not ((c.timelimit > 0 and c.canChange) or c.afterStalemate) then return false end
	local switchDueToTime = c.timelimit > 5 and c.timeLeft < 5 * 60
	return c.timeLeft <= 0 or c.afterStalemate == true or switchDueToTime
end

-- State_Think_RND_RUNNING at the time limit: the higher score, 0 when drawn.
function R.TimelimitWinner(scores)
	if scores[2] == scores[3] then return 0 end
	return scores[3] > scores[2] and 3 or 2
end

-- SetWinningTeam: a round win scores for a full round, or at the time limit.
function R.ShouldRewardTeam(forceMapReset, timelimit, timeLeft, dontAddScore)
	if dontAddScore then return false end
	return forceMapReset or (timelimit > 0 and timeLeft <= 0)
end

-- Capture order (CTFGameRules::TeamMayCapturePoint) --------------------------------------

-- CTeamControlPointMaster::FindControlPoints renumbers the points 0..n-1 in
-- point_index order. Returns each input's rank.
function R.Ranks(indices)
	local order = {}
	for i = 1, #indices do order[i] = i end
	table.sort(order, function(a, b)
		if indices[a] ~= indices[b] then return indices[a] < indices[b] end
		return a < b
	end)
	local ranks = {}
	for rank, i in ipairs(order) do ranks[i] = rank - 1 end
	return ranks
end

-- CTeamControlPointMaster::GetBaseControlPoint. points: { index, defaultOwner }.
function R.BaseControlPoint(team, points)
	local low, high
	for _, p in ipairs(points) do
		if not low or p.index < low.index then low = p end
		if not high or p.index > high.index then high = p end
	end
	if not low then return -1 end
	if high.defaultOwner == team then return high.index end
	if low.defaultOwner == team then return low.index end
	return -1
end

-- CTFGameRules::GetFarthestOwnedControlPoint (without spawn points).
-- owners is indexed by rank 0..count-1.
function R.FarthestOwnedControlPoint(team, owners, count, base)
	if base == -1 then return -1 end
	local walk, enemyEnd = 1, count - 1
	if base ~= 0 then walk, enemyEnd = -1, 0 end
	local farthest = base
	local p = base
	while p ~= enemyEnd do
		if owners[p] ~= team then break end
		farthest = p
		p = p + walk
	end
	return farthest
end

-- q = { caplinear, index, team, locked, previous = { three ranks, -1 unused },
-- playingMiniRounds, owners (by rank), count, base (the team's base rank) }
function R.TeamMayCapturePoint(q)
	if not q.caplinear then return true end
	local needed = q.previous[1]
	if needed == q.index then return true end
	if q.locked then return false end
	if needed == -1 then
		if q.playingMiniRounds then return true end
		local farthest = R.FarthestOwnedControlPoint(q.team, q.owners, q.count, q.base)
		return math.abs(farthest - q.index) <= 1
	end
	for _, prev in ipairs(q.previous) do
		if prev ~= -1 and q.owners[prev] ~= q.team then return false end
	end
	return true
end

-- team_round_timer ------------------------------------------------------------------------

local MARKS = { 300, 240, 180, 120, 60, 30, 10, 5, 4, 3, 2, 1 }
local SETUP_MARKS = { 60, 30, 10, 5, 4, 3, 2, 1 }
local OUTPUT = {
	[300] = "On5MinRemain", [240] = "On4MinRemain", [180] = "On3MinRemain", [120] = "On2MinRemain",
	[60] = "On1MinRemain", [30] = "On30SecRemain", [10] = "On10SecRemain", [5] = "On5SecRemain",
	[4] = "On4SecRemain", [3] = "On3SecRemain", [2] = "On2SecRemain", [1] = "On1SecRemain",
}

function R.TimerOutputName(mark)
	return OUTPUT[mark]
end

-- CalculateOutputMessages (server): each mark is armed while there is at least
-- that much time left.
function R.ArmTimerOutputs(t)
	local armed = { finished = t > 0 }
	for _, m in ipairs(MARKS) do armed[m] = t >= m end
	return armed
end

-- RoundTimerThink / RoundTimerSetupThink: at most one output per think, in
-- this order. Returns "finished", a mark, or nil.
function R.NextTimerOutput(armed, t, setup)
	if t <= 0 and armed.finished then return "finished" end
	for _, m in ipairs(setup and SETUP_MARKS or MARKS) do
		if t <= m and armed[m] then return m end
	end
	return nil
end

-- The client's CalculateOutputMessages adds 2 s above ten seconds, covering
-- the time the update took to arrive.
local WARNINGS = { 60, 30, 10, 5, 4, 3, 2, 1 }
local WARN_AT = { [60] = 61, [30] = 31, [10] = 11, [5] = 6, [4] = 5, [3] = 4, [2] = 3, [1] = 2 }

function R.ArmClientWarnings(t)
	local padded = t > 10 and t + 2 or t
	local armed = {}
	for _, s in ipairs(WARNINGS) do armed[s] = padded >= s end
	return armed
end

-- CTeamRoundTimer::ClientThink: the countdown line to speak now, or nil.
function R.NextClientWarning(armed, t)
	for _, s in ipairs(WARNINGS) do
		if t <= WARN_AT[s] and armed[s] then return s end
	end
	return nil
end

-- CTeamRoundTimer::SetActiveTimer. timers: { enabled, show }; newly: the index
-- becoming active, or nil when the active one goes away. Returns the chosen
-- index (or nil) and the indices whose show_in_hud is turned off.
function R.ChooseActiveTimer(timers, newly)
	local chosen, hide = newly, {}
	for i, t in ipairs(timers) do
		if i ~= newly and t.enabled and t.show then
			if chosen then hide[#hide + 1] = i else chosen = i end
		end
	end
	return chosen, hide
end

-- CTeamRoundTimer::InputRoundSpawn: the time to run after setup. Without
-- reset_time a timer already in normal time carries its time into the next
-- mini-round.
function R.TimeAfterSetup(resetTime, inNormalState, remaining, initialLength)
	if not resetTime and inNormalState then return remaining end
	return initialLength
end

-- AddTimerSeconds: the seconds actually added under max_length.
function R.ClampAdd(remaining, seconds, maxLength)
	if maxLength > 0 and remaining + seconds > maxLength then return maxLength - remaining end
	return seconds
end

-- Win panel (CTFWinPanel::FireGameEvent, English strings from tf_english.txt) -----------

local TEAM_LABEL = { [2] = "RED", [3] = "BLU" }
local REASON_TEXT = {
	[R.WINREASON.ALL_POINTS_CAPTURED] = "%s captured all control points",
	[R.WINREASON.OPPONENTS_DEAD] = "%s killed all opponents during sudden death",
	[R.WINREASON.DEFEND_UNTIL_TIME_LIMIT] = "%s successfully defended until time ran out",
	[R.WINREASON.STALEMATE] = "You're all losers",
	[R.WINREASON.TIMELIMIT] = "%s had more points when the time limit was reached",
	[R.WINREASON.WINLIMIT] = "%s had more points when the win limit was reached",
	[R.WINREASON.WINDIFFLIMIT] = "%s was ahead by the required difference to win",
}

-- info = { winner, reason, fullRound, remaining (areas left for the winner) }
function R.WinPanel(info)
	if info.winner < FIRST_GAME_TEAM then
		return { title = "STALEMATE", reason = REASON_TEXT[R.WINREASON.STALEMATE] }
	end
	local team = TEAM_LABEL[info.winner]
	local areaDefense = info.reason == R.WINREASON.DEFEND_UNTIL_TIME_LIMIT and not info.fullRound
	local title
	if info.fullRound then
		title = team .. " TEAM WINS!"
	elseif areaDefense then
		title = team .. " TEAM DEFENDS!"
	else
		title = team .. " TEAM SEIZES AREA"
	end
	local text = REASON_TEXT[info.reason]
	local panel = { title = title, reason = text and string.format(text, team) or nil }
	if not info.fullRound and info.reason ~= R.WINREASON.STALEMATE then
		panel.details = info.remaining .. (info.remaining == 1 and " more area to win" or " more areas to win")
	end
	return panel
end

-- CHudStalemate::SetupStalematePanel
local STALEMATE_REASON = {
	[R.STALEMATE.JOIN_MID] = "Sit back and relax while you wait for this petty conflict to end.",
	[R.STALEMATE.TIMER] = "You've run out of time. Watch your back and finish 'em off. No more spawning.",
	[R.STALEMATE.SERVER_TIMELIMIT] = "Map time limit reached. No more spawning, so make this count.",
}

function R.StalematePanel(reason)
	return { title = "SUDDEN DEATH!", reason = STALEMATE_REASON[reason] }
end

-- Localization ---------------------------------------------------------------------------

local function Utf16(s)
	return (string.gsub(s, ".", function(c) return c .. "\0" end))
end

local function Utf8(code)
	if code < 0x80 then return string.char(code) end
	if code < 0x800 then
		return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
	end
	if code < 0x10000 then
		return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
	end
	return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
		0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local function Unit(raw, i)
	return string.byte(raw, i) + string.byte(raw, i + 1) * 256
end

-- Only indentation between the line's start (or the file's BOM) and unit i.
local function StartsLine(raw, i)
	i = i - 2
	while i >= 1 do
		local u = Unit(raw, i)
		if u == 10 or u == 0xFEFF then return true end
		if u ~= 9 and u ~= 32 then return false end
		i = i - 2
	end
	return true
end

-- The English text of a "#Token" from a UTF-16LE localization file (as
-- tf/resource/tf_english.txt), matched case-insensitively. Text without a
-- leading "#" is returned as it is; an unknown token is nil.
function R.Localize(raw, token)
	if string.sub(token, 1, 1) ~= "#" then return token end
	local key = Utf16('"' .. string.lower(string.sub(token, 2)) .. '"')
	local lowered = string.lower(raw)
	local init = 1
	local i
	-- A key starts its line (after any indent); the same text after a key is a value.
	repeat
		local s, e = string.find(lowered, key, init, true)
		if not s then return nil end
		if s % 2 == 1 and StartsLine(raw, s) then i = e + 1 end
		init = e + 1
	until i
	while i < #raw and (Unit(raw, i) == 9 or Unit(raw, i) == 32) do i = i + 2 end
	if Unit(raw, i) ~= 34 then return nil end
	i = i + 2
	local out = {}
	while i < #raw do
		local u = Unit(raw, i)
		if u == 34 then return table.concat(out) end
		if u >= 0xD800 and u < 0xDC00 then
			local low = Unit(raw, i + 2)
			out[#out + 1] = Utf8(0x10000 + (u - 0xD800) * 0x400 + (low - 0xDC00))
			i = i + 4
		else
			out[#out + 1] = Utf8(u)
			i = i + 2
		end
	end
	return nil
end

return R
