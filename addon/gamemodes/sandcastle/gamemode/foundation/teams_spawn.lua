-- Which info_player_teamspawn a player may use, as TF2 decides it: the
-- spawn's own state (CTFTeamSpawn), the per-round setup of mini-round maps
-- (CTFGameRules::SetupSpawnPointsForRound), the control-point spawns of maps
-- without mini-rounds (RecalculateControlPointState), and the round-robin
-- choice (CTFPlayer::SelectSpawnSpotByType). Pure: spawns are records
-- { team, disabled, controlpoint, roundBlue, roundRed, spawnMode, matchSummary }.
local ipairs, tonumber = ipairs, tonumber
module(...)

local RED, BLUE = 2, 3

local function Name(value)
	if value == nil or value == "" then return nil end
	return value
end

-- A record from the keyvalues the map gave the spawn (lowercased keys).
function FromKeyValues(kv)
	return {
		team = tonumber(kv.teamnum) or 0,
		disabled = kv.startdisabled == "1",
		controlpoint = Name(kv.controlpoint),
		roundBlue = Name(kv.round_bluespawn),
		roundRed = Name(kv.round_redspawn),
		spawnMode = tonumber(kv.spawnmode) or 0,
		matchSummary = tonumber(kv.matchsummary) or 0,
	}
end

-- CTFGameRules::IsSpawnPointValid, outside the match summary: the team's,
-- enabled, spawn mode Normal (Triggered spawns are only for a respawn
-- override), and not a podium spot.
function Valid(spawn, team)
	return spawn.team == team and not spawn.disabled and spawn.spawnMode == 0 and spawn.matchSummary == 0
end

-- CTFGameRules::SetupSpawnPointsForRound: spawns tied to a point of the
-- round take its owner; spawns tied to the round by round_bluespawn or
-- round_redspawn take that team; every other spawn is switched off.
-- roundPoints is the set of point names in the round; pointOwner(name) is
-- the owner of the named point, or nil when there is none.
function SetupForRound(spawns, roundName, roundPoints, pointOwner)
	for _, s in ipairs(spawns) do
		local owner = s.controlpoint and pointOwner(s.controlpoint)
		if owner and roundPoints[s.controlpoint] then
			s.disabled = false
			s.team = owner
		elseif s.roundBlue == roundName then
			s.disabled = false
			s.team = BLUE
		elseif s.roundRed == roundName then
			s.disabled = false
			s.team = RED
		else
			s.disabled = true
		end
	end
end

-- CTeamControlPointMaster::GetBaseControlPoint. points: { index, defaultOwner }.
function BaseControlPoint(points, team)
	local lowest, highest
	for _, p in ipairs(points) do
		if not highest or p.index > highest.index then highest = p end
		if not lowest or p.index < lowest.index then lowest = p end
	end
	if not lowest then return -1 end
	if highest.defaultOwner == team then return highest.index end
	if lowest.defaultOwner == team then return lowest.index end
	return -1
end

-- CTFGameRules::SetupOnRoundStart without mini-rounds: every spawn tied to a
-- control point starts off, and the points that have spawns are noted per
-- team. pointIndex(name) is the named point's index, or nil.
function StartControlPointSpawns(spawns, pointIndex)
	local controlSpawns = { [RED] = {}, [BLUE] = {} }
	for _, s in ipairs(spawns) do
		local index = s.controlpoint and pointIndex(s.controlpoint)
		if index then
			if controlSpawns[s.team] then controlSpawns[s.team][index] = true end
			s.disabled = true
		end
	end
	return controlSpawns
end

-- CTFGameRules::GetFarthestOwnedControlPoint(team, true). points: { index, owner, defaultOwner }.
function FarthestOwnedPoint(team, points, controlSpawns)
	local ownedEnd = BaseControlPoint(points, team)
	if ownedEnd == -1 then return -1 end
	local owner = {}
	for _, p in ipairs(points) do owner[p.index] = p.owner end
	local walk, enemyEnd = 1, #points - 1
	if ownedEnd ~= 0 then walk, enemyEnd = -1, 0 end
	local farthest = ownedEnd
	for i = ownedEnd, enemyEnd - walk, walk do
		if owner[i] ~= team then break end
		if controlSpawns[team][i] then farthest = i end
	end
	return farthest
end

-- CTFGameRules::RecalculateControlPointState: each team spawns at the
-- farthest point it holds that has spawns.
function RecalculateControlPointState(spawns, points, controlSpawns, pointIndex)
	for _, team in ipairs({ RED, BLUE }) do
		local farthest = FarthestOwnedPoint(team, points, controlSpawns)
		if farthest ~= -1 then
			for _, s in ipairs(spawns) do
				local index = s.controlpoint and pointIndex(s.controlpoint)
				if index and s.team == team then s.disabled = index ~= farthest end
			end
		end
	end
end

-- CTFPlayer::SelectSpawnSpotByType: start after the last spot the team
-- used, take the first valid clear spot, else the first valid one.
-- isClear(i) says whether spot i is free of players. Returns an index or nil.
function Pick(spawns, team, last, isClear)
	local n = #spawns
	local start = last or 0
	local fallback
	for step = 1, n do
		local i = (start + step - 1) % n + 1
		if Valid(spawns[i], team) then
			if isClear(i) then return i end
			fallback = fallback or i
		end
	end
	return fallback
end
