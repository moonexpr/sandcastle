-- Team rules of TF2 as pure functions: joining, auto-assignment, balance,
-- and the team tests of the spawn-room entities. No GMod globals; the
-- modules that use it include it.
local L = {}

local UNASSIGNED, SPECTATOR, RED, BLUE = 0, 1, 2, 3
L.AUTO = "auto"
L.STATE_TEAM_WIN = 5 -- GR_STATE_TEAM_WIN
L.STATE_STALEMATE = 7 -- GR_STATE_STALEMATE
L.STATE_GAME_OVER = 8 -- GR_STATE_GAME_OVER

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

-- counts[t] is the number of players on each game team t now, the mover
-- included; the game teams are exactly its keys.

local function GameTeams(counts)
	local teams = {}
	for t in pairs(counts) do teams[#teams + 1] = t end
	table.sort(teams)
	return teams
end

-- CTeamplayRoundBasedRules::WouldChangeUnbalanceTeams.
function L.WouldUnbalance(counts, newTeam, currentTeam, limit)
	if newTeam == currentTeam or limit <= 0 or counts[newTeam] == nil then return false end
	local joined = counts[newTeam] + 1
	for t, n in pairs(counts) do
		if t ~= newTeam then
			if t == currentTeam then n = math.max(0, n - 1) end
			if joined - n > limit then return true end
		end
	end
	return false
end

-- CTeamplayRoundBasedRules::AreTeamsUnbalanced: heavy and light team, or nil.
function L.Unbalanced(counts, limit)
	if limit <= 0 then return nil end
	local heavy, light
	for _, t in ipairs(GameTeams(counts)) do
		if not heavy or counts[t] > counts[heavy] then heavy = t end
		if not light or counts[t] < counts[light] then light = t end
	end
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

-- The team menu (CTFTeamMenu) --------------------------------------------------

-- CTFTeamMenu::ShowPanel: nobody changes teams once the game is over, nor
-- does a player of a losing team while the winners celebrate.
function L.TeamMenuAllowed(state, currentTeam, winner)
	if state == L.STATE_GAME_OVER then return false end
	return not (state == L.STATE_TEAM_WIN and currentTeam >= RED and currentTeam ~= winner)
end

local TEAM_FULL = "Team is full"

local function Choice(kind, spec, currentTeam)
	return {
		kind = kind,
		index = spec.index,
		label = spec.name,
		color = spec.color,
		count = spec.count,
		command = spec.command,
		enabled = true,
		current = spec.index ~= nil and spec.index == currentTeam,
	}
end

-- CTFTeamMenu::OnTick: a game team is disabled while it is the heavy team
-- or joining it would unbalance the teams.
local function TeamChoice(spec, counts, currentTeam, limit)
	local c = Choice("team", spec, currentTeam)
	local heavy = L.Unbalanced(counts, limit)
	if heavy == spec.index or L.WouldUnbalance(counts, spec.index, currentTeam, limit) then
		c.enabled, c.reason = false, TEAM_FULL
	end
	return c
end

-- The menu as data, for any game's teams. teams: the joinable teams in
-- screen order, each { index, name, color, count, command }. extras.auto
-- { name, command } and extras.spectate { index, name, command, count } are
-- offered when present. Hotkeys number auto, spectate, then the teams
-- (Teammenu.res: &1 random, &2 spectate, &3 BLU, &4 RED). Cancel only once
-- the player has a team (CTFTeamMenu::Update).
function L.TeamMenu(teams, currentTeam, limit, extras)
	local counts = {}
	for _, t in ipairs(teams) do counts[t.index] = t.count end
	local menu = { teams = {}, choices = {}, cancel = currentTeam ~= UNASSIGNED }
	local function Add(c)
		menu.choices[#menu.choices + 1] = c
		c.hotkey = #menu.choices
		return c
	end
	if extras.auto then menu.auto = Add(Choice("auto", extras.auto, currentTeam)) end
	if extras.spectate then menu.spectate = Add(Choice("spectate", extras.spectate, currentTeam)) end
	for i, t in ipairs(teams) do menu.teams[i] = Add(TeamChoice(t, counts, currentTeam, limit)) end
	return menu
end

return L
