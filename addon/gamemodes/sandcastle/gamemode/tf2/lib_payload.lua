-- The team_train_watcher's decisions, from team_train_watcher.cpp, as pure
-- functions: how fast the cart goes, which speed arrows the HUD shows, when
-- it recedes, how far it has come, and when the announcer and the capture
-- alarm sound. The entity feeds them what it reads from the world.
local P = {}

P.HILL_NONE, P.HILL_UP, P.HILL_DOWN = 0, 1, 2

P.ALERT_DISTANCE = 750           -- TEAM_TRAIN_ALERT_DISTANCE: the announcer's warning
P.ALARM_DISTANCE = 200           -- TEAM_TRAIN_ALARM_DISTANCE: the looping alarm at the point
P.MAX_ALARM_TIME_NO_RECEDE = 18  -- loop length when the train cannot recede
P.ALARM_SINGLE_INTERVAL = 8      -- TW_ALARM_THINK_INTERVAL

local RECEDE_SPEED = -0.1
local PUSH_SPEED = { 0.55, 0.77, 1.0 }

local function PushSpeed(numCappers, hill)
	if hill == P.HILL_DOWN then return 1.0 end
	return PUSH_SPEED[math.min(numCappers, 3)]
end

local function IdleSpeed(s)
	if s.currentSpeed > 0 then
		return s.hill == P.HILL_DOWN and 1.0 or 0
	end
	if s.hill == P.HILL_UP then return -1.0 end
	return s.receding and RECEDE_SPEED or 0
end

-- HandleTrainMovement. s = { numCappers, hill, currentSpeed, receding }.
-- Returns the speed fraction to set and the new receding flag.
function P.TrainSpeed(s, startReceding)
	local speed, receding = 0, s.receding
	if startReceding then
		speed, receding = RECEDE_SPEED, true
	elseif s.numCappers > 0 then
		speed, receding = PushSpeed(s.numCappers, s.hill), false
	elseif s.numCappers == -1 then
		-- a blocked cart stands still unless it is rolling downhill
		speed = s.hill == P.HILL_DOWN and 1.0 or 0
	else
		speed = IdleSpeed(s)
	end
	if speed ~= s.currentSpeed and speed >= 0 then receding = false end
	return speed, receding
end

-- WatcherThink's m_iTrainSpeedLevel: -1 backwards (0 once stopped at a dead
-- end), else 0..3 by the hud_min_speed_level_1..3 thresholds.
function P.SpeedLevel(desiredSpeed, currentSpeed, levels)
	if desiredSpeed < 0 then return currentSpeed == 0 and 0 or -1 end
	for level = 3, 1, -1 do
		if desiredSpeed > levels[level] then return level end
	end
	return 0
end

-- InternalSetNumTrainCappers: seconds until an unpushed cart recedes.
function P.RecedeDelay(overtime, trainRecedeTime, recedeTime, overtimeRecedeTime)
	if overtime then return overtimeRecedeTime end
	if trainRecedeTime > 0 then return trainRecedeTime end
	return recedeTime
end

-- InputOnStartOvertime: a pending recede longer than the overtime length is cut to it.
function P.OvertimeRecedeAt(recedeAt, now, overtimeLen)
	if recedeAt - now > overtimeLen then return now + overtimeLen end
	return recedeAt
end

-- The path node the train is heading for, given the index of its current
-- node (func_tracktrain's m_ppath): the next one, or its own when reversing.
function P.TargetIndex(pathIndex, speed, count)
	if speed < 0 then return pathIndex end
	return math.min(pathIndex + 1, count)
end

-- The train's current node after it passes node `index`: CFuncTrackTrain
-- fires OnPass on the new node going forward, and on the node it leaves
-- going backward.
function P.PassedIndex(index, speed)
	if speed >= 0 then return index end
	return math.max(index - 1, 1)
end

-- distanceAt[i] is the path length from the start node to node i.
function P.DistanceToGoal(total, distanceAt, targetIndex, straight)
	return straight + total - distanceAt[targetIndex]
end

function P.Progress(total, distanceToGoal)
	return math.min(math.max(1 - distanceToGoal / total, 0), 1)
end

-- Approach alerts. links = { { distance, alerted }, ... }, updated in place;
-- returns the indices whose alert should play now.
function P.AlertsDue(links, trainDistance, canRecede)
	local due = {}
	for i, link in ipairs(links) do
		if trainDistance < link.distance - P.ALERT_DISTANCE then
			-- re-arm after backing off twice the distance, or for a train
			-- that rolled back down a hill although it never recedes
			if trainDistance < link.distance - 2 * P.ALERT_DISTANCE or not canRecede then
				link.alerted = false
			end
		elseif trainDistance < link.distance and not link.alerted then
			link.alerted = true
			due[#due + 1] = i
		end
	end
	return due
end

-- The capture alarm: a loop at the final point while the train is within
-- ALARM_DISTANCE of the goal. Actions: "start" (loop), "stop" (loop and
-- singles), "single" (one Cart.WarningSingle).
function P.NewAlarm()
	return { playing = false, played = false, endAt = -1, nextSingle = nil }
end

-- StopCaptureAlarm
local function StopAlarm(a, out)
	if a.playing or a.nextSingle then out[#out + 1] = "stop" end
	a.playing, a.endAt, a.nextSingle = false, -1, nil
end

-- One WatcherThink (and WatcherAlarmThink) step.
function P.AlarmStep(a, distanceToGoal, running, canRecede, hasLinks, now)
	local out = {}
	if a.nextSingle and now >= a.nextSingle then
		out[#out + 1] = "single"
		a.nextSingle = a.nextSingle + P.ALARM_SINGLE_INTERVAL
	end
	if not running then StopAlarm(a, out) end
	if distanceToGoal > P.ALARM_DISTANCE then
		StopAlarm(a, out)
		a.played = false
	elseif running then
		if not a.playing then
			-- played: on maps where the train does not recede, the loop
			-- plays once and then only singles
			if hasLinks and not a.played then
				out[#out + 1] = "start"
				a.playing, a.played, a.endAt = true, true, now + P.MAX_ALARM_TIME_NO_RECEDE
			end
		elseif not canRecede and a.endAt > 0 and a.endAt < now then
			StopAlarm(a, out)
			a.nextSingle = now + P.ALARM_SINGLE_INTERVAL
		end
	end
	return out
end

-- WatcherActivate's hill data for the HUD. nodes[i] = { distance, hill } from
-- the start node to the goal; returns { { from, to, down }, ... } as
-- fractions of the path, pulled 0.005 inward so a train stopped at the foot
-- or top of a hill does not show as on it.
function P.HillSegments(nodes, total)
	local marks, down = {}, {}
	local onHill, hillStart, current = false, nil, P.HILL_NONE
	local function StartHill(i, distance)
		marks[#marks + 1] = distance
		onHill, hillStart = true, i
		down[#down + 1] = nodes[i].hill == P.HILL_DOWN
	end
	for i = 2, #nodes do
		local node = nodes[i]
		if node.hill ~= current then
			if not onHill then
				StartHill(i, node.distance)
			else
				-- the previous node ended the hill, unless the hill was that one node
				local length = node.distance - nodes[i - 1].distance
				marks[#marks + 1] = hillStart == i - 1 and node.distance or node.distance - length
				if node.hill ~= P.HILL_NONE then
					StartHill(i, node.distance)
				else
					onHill, hillStart = false, nil
				end
			end
			current = node.hill
		end
	end
	if #marks % 2 ~= 0 then marks[#marks + 1] = total end
	local hills = {}
	if total <= 0 then return hills end
	for k = 1, #marks, 2 do
		hills[#hills + 1] = { from = marks[k] / total + 0.005, to = marks[k + 1] / total - 0.005, down = down[(k + 1) / 2] }
	end
	return hills
end

-- CTeamControlPointRound/Master::TeamOwnsAllPoints. points = { { group, owner } };
-- with overrideIndex, that point is taken as owned by newTeam. Returns the
-- team owning every point of some group, else 0.
function P.TeamOwnsAllPoints(points, overrideIndex, newTeam)
	local winning, order = {}, {}
	for i, point in ipairs(points) do
		local owner = i == overrideIndex and newTeam or point.owner
		local g = point.group
		if winning[g] == nil then
			winning[g] = owner
			order[#order + 1] = g
		elseif winning[g] ~= 0 and winning[g] ~= owner then
			winning[g] = 0
		end
	end
	table.sort(order)
	for _, g in ipairs(order) do
		if winning[g] >= 2 then return winning[g] end
	end
	return 0
end

-- CTeamControlPointRound::IsPlayable; invalidCapWinner is the round's
-- cpr_restrict_team_cap_win (1: neither team wins it by capping).
function P.IsPlayable(points, invalidCapWinner)
	if invalidCapWinner == 1 then return true end
	local winners = P.TeamOwnsAllPoints(points)
	return not (winners >= 2 and winners ~= invalidCapWinner)
end

-- WatcherThink's bFinalPointInMap: without mini-rounds, whether a team that
-- may capture point `index` would win by it; with mini-rounds, only in the
-- last playable round.
function P.FinalPoint(miniRounds, playableRounds, points, index, cappingTeams)
	if miniRounds and playableRounds ~= 1 then return false end
	for _, team in ipairs(cappingTeams) do
		if P.TeamOwnsAllPoints(points, index, team) == team then return true end
	end
	return false
end

return P
