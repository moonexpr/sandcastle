-- Shared definitions for the TF2 map entities. Team numbers and round states
-- keep TF2's values so map keyvalues (TeamNum=2/3) mean the same thing here.
WETSAND = WETSAND or {}

-- Lua 5.1's require for the gamemode's module(...) files (gamemode/foundation/):
-- GMod's include passes no name to the chunk, so load it here, once, calling
-- it with the dotted name. GM exists only while the gamemode loads.
local GAMEMODE_ROOT = GM.FolderName .. "/gamemode/"

function WETSAND.require(name)
	if package.loaded[name] == nil then
		CompileFile(GAMEMODE_ROOT .. name:gsub("%.", "/") .. ".lua")(name)
	end
	return package.loaded[name]
end

WETSAND.TEAM_UNASSIGNED = 0
WETSAND.TEAM_SPECTATOR = 1
WETSAND.TEAM_RED = 2
WETSAND.TEAM_BLUE = 3

-- gamerules_roundstate_t, teamplayroundbased_gamerules.h
WETSAND.STATE = {
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

-- Pure rule libraries (lib_*.lua), shared so client prediction and drawing
-- follow the same rules as the server.
if SERVER then
	AddCSLuaFile("lib_teams.lua")
	AddCSLuaFile("lib_players.lua")
end
WETSAND.TeamRules = include("lib_teams.lua")
WETSAND.PlayerRules = include("lib_players.lua")

WETSAND.TeamName = { [0] = "Nobody", [1] = "Spectator", [2] = "RED", [3] = "BLU" }
WETSAND.TeamColor = {
	[0] = Color(220, 220, 220),
	[2] = Color(189, 59, 59),
	[3] = Color(91, 122, 140),
}

local PLAYABLE = { [WETSAND.TEAM_RED] = true, [WETSAND.TEAM_BLUE] = true }

function WETSAND.TeamOf(ent)
	if not IsValid(ent) then return WETSAND.TEAM_UNASSIGNED end
	local t = ent:Team()
	if PLAYABLE[t] then return t end
	return WETSAND.TEAM_UNASSIGNED
end

function WETSAND.EnemyOf(team)
	if team == WETSAND.TEAM_RED then return WETSAND.TEAM_BLUE end
	if team == WETSAND.TEAM_BLUE then return WETSAND.TEAM_RED end
	return WETSAND.TEAM_UNASSIGNED
end

function WETSAND.Active()
	return GetGlobal2Bool("tf2.active", false)
end

function WETSAND.State()
	return GetGlobal2Int("tf2.state", WETSAND.STATE.INIT)
end

-- TF2's convar; the map's SetRoundRespawnFreezeEnabled input sets it.
-- Replicated, so client prediction freezes too.
WETSAND.RestartFreeze = CreateConVar("tf_player_movement_restart_freeze", "1", FCVAR_REPLICATED,
	"When set, prevent player movement during round restart")

-- TF2's convar (teamplayroundbased_gamerules.cpp), replicated as there, so the
-- team menu disables the teams the server would refuse.
WETSAND.UnbalanceLimit = CreateConVar("mp_teams_unbalance_limit", "1", FCVAR_REPLICATED,
	"Teams are unbalanced when one team has this many more players than the other team. (0 disables check)", 0, 30)

-- The input restrictions of the round states: during pre-round players may
-- look around and shoot but not move (CTFPlayer::CanPlayerMove); the losing
-- team cannot attack while the winners celebrate (TF2's humiliation).
function WETSAND.RestrictCommand(ply, cmd)
	WETSAND.RestrictStunned(ply, cmd)
	local state = WETSAND.State()
	if state == WETSAND.STATE.PREROUND then
		if not WETSAND.RestartFreeze:GetBool() then return end
		cmd:ClearMovement()
		cmd:RemoveKey(IN_JUMP)
		cmd:RemoveKey(IN_DUCK)
	elseif state == WETSAND.STATE.TEAM_WIN then
		local winner = GetGlobal2Int("tf2.winner", 0)
		if winner ~= 0 and WETSAND.TeamOf(ply) ~= winner then
			cmd:RemoveKey(IN_ATTACK)
			cmd:RemoveKey(IN_ATTACK2)
		end
	end
end

-- A stun's control effects (CTFPlayerShared::StunPlayer): TF_STUN_CONTROLS
-- takes movement and attacks, TF_STUN_LOSER_STATE attacks. The server sets
-- the NW2 vars (sv_teams_conditions.lua).
function WETSAND.RestrictStunned(ply, cmd)
	if CurTime() >= ply:GetNW2Float("tf2.stunEnd", 0) then return end
	local flags = ply:GetNW2Int("tf2.stunFlags", 0)
	local STUN = WETSAND.PlayerRules.STUN
	if bit.band(flags, STUN.CONTROLS) ~= 0 then
		cmd:ClearMovement()
		cmd:RemoveKey(IN_JUMP)
	end
	if bit.band(flags, STUN.CONTROLS + STUN.LOSER_STATE) ~= 0 then
		cmd:RemoveKey(IN_ATTACK)
		cmd:RemoveKey(IN_ATTACK2)
	end
end

-- Speed boost and a stun's slow on the player's top speed, predicted on
-- both realms (TeamFortress_CalculateMaxSpeed, CTFGameMovement).
hook.Add("SetupMove", "tf2.conditions", function(ply, mv)
	local boost = ply:GetNW2Bool("tf2.speedboost", false)
	local reduction = 0
	if CurTime() < ply:GetNW2Float("tf2.stunEnd", 0) then reduction = ply:GetNW2Float("tf2.stunAmount", 0) end
	if not boost and reduction == 0 then return end
	local speed = WETSAND.PlayerRules.MaxSpeed(mv:GetMaxClientSpeed(), boost, reduction)
	mv:SetMaxClientSpeed(speed)
	mv:SetMaxSpeed(speed)
end)
