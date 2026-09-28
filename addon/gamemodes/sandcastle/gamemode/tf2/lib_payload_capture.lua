-- CTriggerAreaCapture (trigger_area_capture.cpp) as a pure state machine:
-- each think takes the players standing in the area and returns the events
-- the SDK's area would raise, in its order. The trigger_capture_area entity
-- turns the events into outputs, ownership changes and callbacks.
--
-- Events: { kind = "start" | "break" | "end" | "capturestart", team },
-- { kind = "numcappers", n, blocked } (SetNumCappers), { kind = "blocked", value,
-- capping } (UpdateBlocked), { kind = "owner", old, team } (the area's new owner).
local C = {}

local TEAMS = { 2, 3 }

function C.New(owner)
	return {
		owner = owner,
		capturing = false,
		cappingTeam = 0,
		timeRemaining = 0,
		blocked = false,
		lastReduction = 0,
		touching = { [2] = 0, [3] = 0 },
		teamInZone = 0,
	}
end

-- Under mp_capstyle 1 more players cap faster, from a longer base time.
function C.TotalTime(capTime, scales, numRequired)
	if scales then return capTime * 2 * numRequired end
	return capTime
end

local function Total(s, i)
	return C.TotalTime(i.capTime, i.scales, i.numRequired[s.cappingTeam])
end

-- UpdateNumPlayers: the capping team's count goes to SetNumCappers.
local function NumPlayers(s, ev, blocked)
	if s.cappingTeam ~= 0 then
		ev[#ev + 1] = { kind = "numcappers", n = s.touching[s.cappingTeam], blocked = blocked }
	end
end

local function Start(s, ev, team, i)
	ev[#ev + 1] = { kind = "start", team = team }
	s.cappingTeam = team
	NumPlayers(s, ev, false)
	s.timeRemaining = Total(s, i)
	s.capturing, s.blocked = true, false
	s.lastReduction = i.now
	ev[#ev + 1] = { kind = "capturestart", team = team }
end

local function End(s, ev)
	local team = s.cappingTeam
	ev[#ev + 1] = { kind = "end", team = team }
	ev[#ev + 1] = { kind = "owner", old = s.owner, team = team }
	s.owner = team
	s.capturing, s.cappingTeam, s.timeRemaining = false, 0, 0
	ev[#ev + 1] = { kind = "numcappers", n = 0, blocked = false }
end

-- BreakCapture
local function Break(s, ev)
	if not s.capturing then return end
	ev[#ev + 1] = { kind = "break", team = s.cappingTeam }
	s.capturing, s.cappingTeam, s.timeRemaining = false, 0, 0
	ev[#ev + 1] = { kind = "numcappers", n = 0, blocked = false }
end

local function SetBlocked(s, ev, value)
	if s.blocked == value then return end
	s.blocked = value
	ev[#ev + 1] = { kind = "blocked", value = value, capping = s.cappingTeam }
end

-- Record the counts; returns teams in the zone and whether any count changed.
local function Survey(s, counts)
	local teamsInZone, changed = 0, false
	s.teamInZone = 0
	for _, team in ipairs(TEAMS) do
		if s.touching[team] ~= counts[team] then
			s.touching[team] = counts[team]
			changed = true
		end
		if counts[team] > 0 then
			teamsInZone = teamsInZone + 1
			s.teamInZone = team
		end
	end
	if teamsInZone > 1 then s.teamInZone = 0 end
	return teamsInZone, changed
end

-- Time taken off this think: diminishing returns for each extra capper.
local function Reduction(s, i, dt)
	local reduction = dt
	if i.scales then
		for k = 1, (s.touching[s.teamInZone] or 0) - 1 do
			reduction = reduction + dt / (k + 1)
		end
	end
	return reduction
end

local function Advance(s, ev, i, teamsInZone)
	local dt = i.now - s.lastReduction
	local reduction = Reduction(s, i, dt)
	s.lastReduction = i.now
	if teamsInZone > 1 then
		SetBlocked(s, ev, true)
		if i.blockstyle == 0 then Break(s, ev) end
		return
	end
	SetBlocked(s, ev, false)
	local total = Total(s, i)
	if s.cappingTeam == s.teamInZone then
		s.timeRemaining = s.timeRemaining - reduction
	elseif s.owner == 0 and s.teamInZone ~= 0 then
		s.timeRemaining = s.timeRemaining + reduction
	elseif i.teamMayCapture(s.cappingTeam) then
		-- caps deteriorate over time, six times as fast in overtime
		local scale = i.scales and i.deteriorate or total
		local decrease = total / scale * dt
		if i.overtime then decrease = decrease * 6 end
		s.timeRemaining = s.timeRemaining + decrease
	else
		s.timeRemaining = total
	end
	if s.timeRemaining <= 0 then
		End(s, ev)
	elseif s.timeRemaining >= total then
		Break(s, ev)
	end
end

local function TryStart(s, ev, i)
	for _, team in ipairs(TEAMS) do
		local n = s.touching[team]
		if i.canCap[team] and s.owner ~= team and n > 0 and n >= i.startRequired[team]
			and (i.scales or n >= i.numRequired[team]) then
			Start(s, ev, team, i)
			return
		end
	end
end

-- CaptureThink. i = { now, pointsMayBeCaptured, counts, canCap, numRequired,
-- startRequired, capTime, scales (mp_capstyle), blockstyle, deteriorate,
-- overtime, teamMayCapture(team) }.
function C.Step(s, i)
	local ev = {}
	if not i.pointsMayBeCaptured then
		Break(s, ev)
		return ev
	end
	local teamsInZone, changed = Survey(s, i.counts)
	-- mp_blockstyle 1: a block pauses the capture and tells the capping
	-- team's listeners there are no cappers (-1 on OnNumCappersChanged2)
	local blocked = false
	if i.blockstyle == 1 and s.capturing and teamsInZone > 1 then
		blocked = true
		for _, team in ipairs(TEAMS) do
			if s.touching[team] ~= 0 then
				s.touching[team] = 0
				changed = true
			end
		end
	end
	if changed then NumPlayers(s, ev, blocked) end
	if s.capturing then
		Advance(s, ev, i, teamsInZone)
	elseif teamsInZone > 0 then
		TryStart(s, ev, i)
	end
	return ev
end

-- InputCaptureCurrentCP
function C.CaptureCurrent(s)
	local ev = {}
	if s.capturing then End(s, ev) end
	return ev
end

-- InputSetControlPoint's BreakCapture
function C.Break(s)
	local ev = {}
	Break(s, ev)
	return ev
end

-- The HUD's capture progress, 0 (none) to 1 (captured).
function C.Progress(s, i)
	if not s.capturing then return 0 end
	return 1 - s.timeRemaining / Total(s, i)
end

-- HandleRespawnTimeAdjustments: undo the old owner's team_spawn_N, apply the new one's.
function C.SpawnAdjustments(old, new, spawnAdjust)
	local out = {}
	if old >= 2 and spawnAdjust[old] ~= 0 then out[#out + 1] = { team = old, seconds = -spawnAdjust[old] } end
	if new >= 2 and spawnAdjust[new] ~= 0 then out[#out + 1] = { team = new, seconds = spawnAdjust[new] } end
	return out
end

return C
