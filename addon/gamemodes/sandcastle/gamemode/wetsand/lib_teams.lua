-- Team rules of TF2 as pure functions: joining, auto-assignment, balance,
-- and the team tests of the spawn-room entities. No GMod globals; the
-- modules that use it include it.
local L = {}

local UNASSIGNED, SPECTATOR, RED, BLUE = 0, 1, 2, 3
L.AUTO = "auto"
L.STATE_TEAM_WIN = 5 -- GR_STATE_TEAM_WIN
L.STATE_STALEMATE = 7 -- GR_STATE_STALEMATE

-- HandleCommand_JoinTeam: g_aTeamNames, compared case-insensitively. A name
-- it does not know leaves the command's initial choice, RED. "blu" is
-- Sandcastle's alias, since that is how TF2 spells the team everywhere else.
local JOIN_NAMES = {
	unassigned = UNASSIGNED,
	spectator = SPECTATOR,
	spectate = SPECTATOR,
	spectatearena = SPECTATOR,
	red = RED,
	blue = BLUE,
	blu = BLUE,
	auto = L.AUTO,
}

function L.ParseJoinTeam(name)
	local team = JOIN_NAMES[string.lower(name)]
	if team == nil then return RED end
	return team
end

-- CTFPlayer::GetAutoTeam: the team with fewer players. On an even split TF2
-- gives attackers the player on escort (payload) maps; Sandcastle does so on
-- every map, so a lone player lands on BLU and can push the cart.
function L.AutoTeam(red, blue)
	if blue < red then return BLUE end
	if red < blue then return RED end
	return BLUE
end

local function Other(team)
	if team == RED then return BLUE end
	return RED
end

-- CTeamplayRoundBasedRules::WouldChangeUnbalanceTeams. counts[t] is the
-- number of players on RED/BLU now, the mover included.
function L.WouldUnbalance(counts, newTeam, currentTeam, limit)
	if newTeam == currentTeam or limit <= 0 or newTeam < RED then return false end
	local joined = counts[newTeam] + 1
	local other = Other(newTeam)
	local left = counts[other]
	if other == currentTeam then left = math.max(0, left - 1) end
	return joined - left > limit
end

-- CTeamplayRoundBasedRules::AreTeamsUnbalanced: heavy and light team, or nil.
function L.Unbalanced(counts, limit)
	if limit <= 0 then return nil end
	local heavy, light = RED, BLUE
	if counts[BLUE] > counts[RED] then heavy, light = BLUE, RED end
	if counts[heavy] - counts[light] > limit then return heavy, light end
	return nil
end

function L.SwitchesRequired(heavyCount, lightCount)
	return math.floor((heavyCount - lightCount) / 2)
end

-- CBaseMultiplayerPlayer::CalculateTeamBalanceScore: higher is switched
-- first, so the newest players move and anyone moved in the last 5 minutes
-- is spared.
function L.BalanceScore(now, connectedAt, lastForcedAt)
	local score = -math.floor(now - connectedAt)
	if lastForcedAt and now - lastForcedAt < 300 then score = score - 10000 end
	return score
end

-- The selection loop of CTeamplayRoundBasedRules::BalanceTeams: the best
-- `required` + 2 candidates by score; mid-round only dead ones may move.
-- candidates: { id, score, alive }. Returns the ids to switch.
function L.PickBalanceSwitches(candidates, required, requireDead)
	local sorted = {}
	for i, c in ipairs(candidates) do sorted[i] = c end
	table.sort(sorted, function(a, b) return a.score > b.score end)
	local picked = {}
	for i = 1, math.min(#sorted, required + 2) do
		if #picked >= required then break end
		local c = sorted[i]
		if not requireDead or not c.alive then picked[#picked + 1] = c.id end
	end
	return picked
end

-- CFilterTFTeam::PassesFilterImpl, then CBaseFilter::PassesFilter's
-- negation: during team win the winners pass every team filter (the impl
-- answers "no" to a negated filter, which the negation turns into a pass).
function L.FilterPasses(filterTeam, negated, entTeam, state, winner)
	local impl
	if state == L.STATE_TEAM_WIN and entTeam == winner then
		impl = not negated
	else
		impl = entTeam == filterTeam
	end
	if negated then return not impl end
	return impl
end

-- CFuncRespawnRoomVisualizer::ShouldCollide: a RED door stops players whose
-- movement mask holds CONTENTS_REDTEAM, which is BLU players, and the other
-- way round; any other non-zero team stops every player.
function L.VisualizerBlocks(vizTeam, playerTeam)
	if vizTeam == UNASSIGNED then return false end
	if vizTeam == RED then return playerTeam == BLUE end
	if vizTeam == BLUE then return playerTeam == RED end
	return true
end

-- CFuncRespawnRoomVisualizer::ShouldTransmit: drawn for players of the
-- other playing team while its room is active and nobody has won.
function L.VisualizerVisible(vizTeam, roomActive, teamWin, viewerTeam)
	if not roomActive or teamWin or vizTeam == UNASSIGNED then return false end
	return viewerTeam > SPECTATOR and viewerTeam ~= vizTeam
end

-- CRegenerateZone::Touch: a zone with a team serves only that team; during
-- team win every zone serves the winners and none the losers; nothing
-- during a stalemate.
function L.RegenerateAllowed(zoneTeam, playerTeam, state, winner)
	if state == L.STATE_TEAM_WIN then
		if winner ~= playerTeam then return false end
	elseif zoneTeam ~= UNASSIGNED and playerTeam ~= zoneTeam then
		return false
	end
	return state ~= L.STATE_STALEMATE
end

return L
