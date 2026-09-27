-- Shared definitions for the TF2 map entities. Team numbers and round states
-- keep TF2's values so map keyvalues (TeamNum=2/3) mean the same thing here.
TF2 = TF2 or {}

TF2.TEAM_UNASSIGNED = 0
TF2.TEAM_SPECTATOR = 1
TF2.TEAM_RED = 2
TF2.TEAM_BLUE = 3

-- gamerules_roundstate_t, teamplayroundbased_gamerules.h
TF2.STATE = {
	INIT = 0,
	PREGAME = 1,
	STARTGAME = 2,
	PREROUND = 3,
	RND_RUNNING = 4,
	TEAM_WIN = 5,
	RESTART = 6,
	STALEMATE = 7,
	GAME_OVER = 8,
	BONUS = 9,
	BETWEEN_RNDS = 10,
}

TF2.TeamName = { [0] = "Nobody", [2] = "RED", [3] = "BLU" }
TF2.TeamColor = {
	[0] = Color(220, 220, 220),
	[2] = Color(189, 59, 59),
	[3] = Color(91, 122, 140),
}

-- GMod's team library reserves 0, 1001 and 1002, so TF2's own numbers are
-- free to register as they are.
team.SetUp(TF2.TEAM_RED, "RED", TF2.TeamColor[TF2.TEAM_RED], false)
team.SetUp(TF2.TEAM_BLUE, "BLU", TF2.TeamColor[TF2.TEAM_BLUE], false)

local PLAYABLE = { [TF2.TEAM_RED] = true, [TF2.TEAM_BLUE] = true }

function TF2.TeamOf(ent)
	if not IsValid(ent) then return TF2.TEAM_UNASSIGNED end
	local t = ent:Team()
	if PLAYABLE[t] then return t end
	return TF2.TEAM_UNASSIGNED
end

function TF2.EnemyOf(team)
	if team == TF2.TEAM_RED then return TF2.TEAM_BLUE end
	if team == TF2.TEAM_BLUE then return TF2.TEAM_RED end
	return TF2.TEAM_UNASSIGNED
end

function TF2.Active()
	return GetGlobal2Bool("tf2.active", false)
end

function TF2.State()
	return GetGlobal2Int("tf2.state", TF2.STATE.INIT)
end

-- Players cannot move during pre-round, and the losing team cannot attack
-- while the winners celebrate (TF2's humiliation), as in TF2.
hook.Add("StartCommand", "tf2.roundstate", function(ply, cmd)
	if not TF2.Active() then return end
	local state = TF2.State()
	if state == TF2.STATE.PREROUND then
		cmd:ClearMovement()
		cmd:RemoveKey(IN_JUMP)
	elseif state == TF2.STATE.TEAM_WIN then
		local winner = GetGlobal2Int("tf2.winner", 0)
		if winner ~= 0 and TF2.TeamOf(ply) ~= winner then
			cmd:RemoveKey(IN_ATTACK)
			cmd:RemoveKey(IN_ATTACK2)
		end
	end
end)
