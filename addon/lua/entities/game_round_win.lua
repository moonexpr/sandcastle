-- game_round_win: tells tf_gamerules the round is over. TeamNum 0 is a
-- stalemate (sudden death is not implemented, so it ends the round drawn).
ENT.Type = "point"
ENT.Base = "base_point"

-- WINREASON_DEFEND_UNTIL_TIME_LIMIT, the reason TF2 gives for this entity.
local WINREASON_DEFEND_UNTIL_TIME_LIMIT = 4

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if k == "teamnum" then
		self.team = tonumber(value) or 0
	elseif k == "force_map_reset" then
		self.forceMapReset = value ~= "0"
	elseif k == "switch_teams" then
		self.switchTeams = value == "1"
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	self.team = self.team or 0
	if self.forceMapReset == nil then self.forceMapReset = true end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:AcceptInput(name, activator, caller, value)
	local input = string.lower(name)
	if input == "roundwin" then
		if IsValid(TF2.Rules) then
			TF2.Rules:SetWinningTeam(self.team, WINREASON_DEFEND_UNTIL_TIME_LIMIT, self.forceMapReset, self.switchTeams)
		end
		self:TriggerOutput("OnRoundWin", activator)
	elseif input == "setteam" then
		self.team = tonumber(value) or 0
	else
		return false
	end
	return true
end
