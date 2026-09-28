-- game_round_win: tells tf_gamerules the round is over (CTeamplayRoundWin,
-- server/tf/entity_roundwin.cpp). TeamNum 0 is a stalemate, which becomes
-- sudden death when mp_stalemate_enable is on. Only a full-reset win switches
-- teams.
ENT.Type = "point"
ENT.Base = "base_point"

-- WINREASON_DEFEND_UNTIL_TIME_LIMIT, the entity's default win_reason.
local DEFEND_UNTIL_TIME_LIMIT = 4
local STALEMATE_TIMER = 1

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if k == "teamnum" then
		self.team = tonumber(value) or 0
	elseif k == "force_map_reset" then
		self.forceMapReset = value ~= "0"
	elseif k == "switch_teams" then
		self.switchTeams = value == "1"
	elseif k == "win_reason" then
		self.winReason = tonumber(value) or DEFEND_UNTIL_TIME_LIMIT
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	self.team = self.team or 0
	if self.forceMapReset == nil then self.forceMapReset = true end
	self.switchTeams = self.switchTeams or false
	self.winReason = self.winReason or DEFEND_UNTIL_TIME_LIMIT
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:RoundWin()
	local rules = TF2.Rules
	if IsValid(rules) then
		if self.team > TF2.TEAM_SPECTATOR then
			rules:SetWinningTeam(self.team, self.winReason, self.forceMapReset, self.forceMapReset and self.switchTeams)
		else
			rules:SetStalemate(STALEMATE_TIMER, self.forceMapReset, self.switchTeams)
		end
	end
	self:TriggerOutput("OnRoundWin", self)
end

function ENT:AcceptInput(name, activator, caller, value)
	local input = string.lower(name)
	if input == "roundwin" then
		self:RoundWin()
	elseif input == "setteam" then
		self.team = tonumber(value) or 0
	else
		return false
	end
	return true
end
