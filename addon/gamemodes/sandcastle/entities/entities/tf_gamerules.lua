-- tf_gamerules: TF2's gamerules proxy, carrying the round-based layer of
-- CTeamplayRoundBasedRules (teamplayroundbased_gamerules.cpp): the round state
-- machine, respawn waves, and winning. It survives round cleanups, as the
-- gamerules do in TF2.
ENT.Type = "point"
ENT.Base = "base_point"

local S = TF2.STATE

-- TF2's own convars, as teamplayroundbased_gamerules.cpp defines them.
local respawnwavetime = CreateConVar("mp_respawnwavetime", "10.0", { FCVAR_NOTIFY, FCVAR_REPLICATED }, "Time between respawn waves.")
local bonusroundtime = CreateConVar("mp_bonusroundtime", "15", FCVAR_REPLICATED, "Time after round win until round restarts", 5, 15)
local enableroundwaittime = CreateConVar("mp_enableroundwaittime", "1", FCVAR_REPLICATED, "Enable timers to wait between rounds.")

-- The pre-round lasts this many seconds times mp_enableroundwaittime. TF2's
-- State_Enter_PREROUND uses 5; Sandcastle uses 3.
local PREROUND_SECONDS = 3

-- GetMinTimeWhenPlayerMaySpawn: 2s death animation plus the freezecam's
-- spec_freeze_traveltime (0.4) and spec_freeze_time (4).
local DEATH_ANIM_LENGTH = 2.0 + 0.4 + 4.0
local OPTIMAL_TEAM_SIZE = 8

function ENT:KeyValue(key, value)
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Initialize()
	TF2.Rules = self
	SetGlobal2Bool("tf2.active", true)
	self.waveTime = { [2] = -1, [3] = -1 }
	self.nextWave = { [2] = 0, [3] = 0 }
	self.goalString = {}
	self.role = {}
	self.score = { [2] = 0, [3] = 0 }
	self.roundsPlayed = 0
	self.inSetup = false
	self:StateTransition(S.PREGAME)
end

function ENT:OnRemove()
	if TF2.Rules == self then
		TF2.Rules = nil
		SetGlobal2Bool("tf2.active", false)
	end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

-- State machine --------------------------------------------------------------

function ENT:StateGet()
	return self.state
end

function ENT:StateTransition(state)
	self.state = state
	self.transitionAt = nil
	SetGlobal2Int("tf2.state", state)
	local enter = self["StateEnter_" .. table.KeyFromValue(S, state)]
	if enter then enter(self) end
end

function ENT:Think()
	local think = self["StateThink_" .. table.KeyFromValue(S, self.state)]
	if think then think(self) end
	self:NextThink(CurTime() + 0.1)
	return true
end

function ENT:TransitionDue()
	return self.transitionAt and CurTime() >= self.transitionAt
end

-- TF2 waits for players before the first round. A player counts once their
-- client has finished loading, so the pre-round freeze is not spent on a
-- loading screen.
function ENT:StateThink_PREGAME()
	for _, ply in ipairs(player.GetAll()) do
		if ply.tf2Ready then
			self:StateTransition(S.PREROUND)
			return
		end
	end
end

function ENT:StateEnter_PREROUND()
	self:RoundRespawn()
	self.transitionAt = CurTime() + PREROUND_SECONDS * enableroundwaittime:GetFloat()
	SetGlobal2Float("tf2.preroundEnd", self.transitionAt)
end

function ENT:StateThink_PREROUND()
	if self:TransitionDue() then self:StateTransition(S.RND_RUNNING) end
end

function ENT:StateEnter_RND_RUNNING()
	self.nextWave = { [2] = 0, [3] = 0 }
	hook.Run("TF2RoundActive")
end

function ENT:StateThink_RND_RUNNING()
	self:CheckRespawnWaves()
end

function ENT:StateEnter_TEAM_WIN()
	if self.forceMapReset then self.roundsPlayed = self.roundsPlayed + 1 end
	self.transitionAt = CurTime() + bonusroundtime:GetFloat()
	local winner = self.winningTeam
	-- PlayWinSong: each side hears its own result.
	if winner ~= 0 then
		self.score[winner] = self.score[winner] + 1
		TF2.Announce(TF2.TeamName[winner] .. " WINS!", winner)
		TF2.BroadcastSound(winner, "Game.YourTeamWon")
		TF2.BroadcastSound(TF2.EnemyOf(winner), "Game.YourTeamLost")
	else
		TF2.Announce("STALEMATE", 0)
		TF2.BroadcastSound(TF2.TEAM_UNASSIGNED, "Game.Stalemate")
	end
	hook.Run("TF2RoundWin", winner)
end

function ENT:StateThink_TEAM_WIN()
	if self:TransitionDue() then self:StateTransition(S.PREROUND) end
end

-- Round control ----------------------------------------------------------------

function ENT:InSetup()
	return self.inSetup
end

function ENT:SetInSetup(inSetup)
	self.inSetup = inSetup
	SetGlobal2Bool("tf2.setup", inSetup)
end

function ENT:PointsMayBeCaptured()
	return (self.state == S.RND_RUNNING or self.state == S.STALEMATE) and not self.inSetup
end

function ENT:RoundRespawn()
	SetGlobal2Int("tf2.winner", 0)
	if self.roundsPlayed > 0 or self.forceMapReset then
		game.CleanUpMap(false, { "tf_gamerules" })
	end
	self.forceMapReset = nil
	self:SetInSetup(false)
	for _, ply in ipairs(player.GetAll()) do
		ply:Spawn()
	end
end

function ENT:SetWinningTeam(team, reason, forceMapReset, switchTeams)
	if self.state == S.TEAM_WIN or self.state == S.GAME_OVER then return end
	self.winningTeam = team
	self.winReason = reason
	self.forceMapReset = forceMapReset ~= false
	SetGlobal2Int("tf2.winner", team)
	self:StateTransition(S.TEAM_WIN)
end

-- Respawn waves (CheckRespawnWaves / GetNextRespawnWave) ----------------------------

function ENT:TeamPlayers(team)
	local players = {}
	for _, ply in ipairs(player.GetAll()) do
		if TF2.TeamOf(ply) == team then players[#players + 1] = ply end
	end
	return players
end

function ENT:GetRespawnTimeScalar(team)
	local n = #self:TeamPlayers(team)
	return math.Remap(math.Clamp(n, 1, OPTIMAL_TEAM_SIZE), 1, OPTIMAL_TEAM_SIZE, 0.25, 1.0)
end

function ENT:GetRespawnWaveMaxLength(team, scaleWithNumPlayers)
	if self.state ~= S.RND_RUNNING then return 0 end
	local t = self.waveTime[team] >= 0 and self.waveTime[team] or respawnwavetime:GetFloat()
	if scaleWithNumPlayers and t > 5 then
		t = math.max(5, t * self:GetRespawnTimeScalar(team))
	end
	return t
end

function ENT:ShouldRespawnQuickly(ply)
	return self.inSetup
end

function ENT:GetMinTimeWhenPlayerMaySpawn(ply)
	local delay = DEATH_ANIM_LENGTH
	if not self:ShouldRespawnQuickly(ply) then
		delay = delay + self:GetRespawnWaveMaxLength(TF2.TeamOf(ply), false)
	end
	return (ply.tf2DeathTime or 0) + delay
end

function ENT:GetNextRespawnWave(team, ply)
	local minTime = self:GetMinTimeWhenPlayerMaySpawn(ply)
	if self:ShouldRespawnQuickly(ply) then return minTime end
	local nextWave = self.nextWave[team]
	local waveLength = self:GetRespawnWaveMaxLength(team, true)
	if waveLength <= 0 then return math.max(nextWave, minTime) end
	while nextWave < minTime do
		nextWave = nextWave + waveLength
	end
	return nextWave
end

function ENT:OnPlayerDeath(ply)
	ply.tf2DeathTime = CurTime()
	ply:SetNW2Float("tf2.respawnAt", self:GetNextRespawnWave(TF2.TeamOf(ply), ply))
end

function ENT:RespawnTeam(team)
	local now = CurTime()
	for _, ply in ipairs(self:TeamPlayers(team)) do
		if not ply:Alive() and now >= self:GetMinTimeWhenPlayerMaySpawn(ply) then
			ply:Spawn()
		end
	end
end

function ENT:CheckRespawnWaves()
	local now = CurTime()
	for team = TF2.TEAM_RED, TF2.TEAM_BLUE do
		if self.nextWave[team] == 0 or self.nextWave[team] <= now then
			self:RespawnTeam(team)
			local length = self:GetRespawnWaveMaxLength(team, true)
			self.nextWave[team] = length > 0 and now + length or 0
		end
	end
end

-- Inputs -----------------------------------------------------------------------

local function TeamWaveSetter(team, add)
	return function(self, value)
		local v = tonumber(value) or 0
		if add then
			local base = self.waveTime[team] >= 0 and self.waveTime[team] or respawnwavetime:GetFloat()
			self.waveTime[team] = math.max(0, base + v)
		else
			self.waveTime[team] = v
		end
	end
end

local function Store(field, team)
	return function(self, value) self[field][team] = value end
end

local function Ignore() end

local INPUTS = {
	setredteamrespawnwavetime = TeamWaveSetter(2, false),
	setblueteamrespawnwavetime = TeamWaveSetter(3, false),
	addredteamrespawnwavetime = TeamWaveSetter(2, true),
	addblueteamrespawnwavetime = TeamWaveSetter(3, true),
	setredteamgoalstring = Store("goalString", 2),
	setblueteamgoalstring = Store("goalString", 3),
	setredteamrole = Store("role", 2),
	setblueteamrole = Store("role", 3),
	addredteamscore = function(self, v) self.score[2] = self.score[2] + (tonumber(v) or 0) end,
	addblueteamscore = function(self, v) self.score[3] = self.score[3] + (tonumber(v) or 0) end,
	-- Accepted so the map's I/O is honoured, with no effect in GMod: there is
	-- no spectator targeting, VO channel, timelimit, KOTH clock or upgrades file.
	setrequiredobservertarget = Ignore,
	setstalemateontimelimit = Ignore,
	playvo = Ignore,
	playvored = Ignore,
	playvoblue = Ignore,
	handlemapevent = Ignore,
	setroundrespawnfreezeenabled = function(self, value)
		TF2.RestartFreeze:SetBool(tonumber(value) ~= 0 and tostring(value) ~= "false")
	end,
	setmapforcedtruceduringbossfight = Ignore,
	setctfcapturebonustime = Ignore,
	setcustomupgradesfile = Ignore,
	setredkothclockactive = Ignore,
	setbluekothclockactive = Ignore,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end
