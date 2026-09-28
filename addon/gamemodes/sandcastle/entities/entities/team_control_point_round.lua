-- team_control_point_round: the control points that make up one mini-round,
-- its priority among the rounds, and which team may not win it by capping
-- them all (CTeamControlPointRound, team_control_point_round.cpp). The master
-- chooses which round is played; see team_control_point_master.
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if k == "cpr_cp_names" then
		self.pointNames = string.Explode("%s+", string.Trim(value), true)
	elseif k == "cpr_priority" then
		self.priority = tonumber(value) or 0
	elseif k == "cpr_restrict_team_cap_win" then
		self.restrictTeam = tonumber(value) or 0
	elseif k == "cpr_printname" then
		self.printName = value
	elseif k == "startdisabled" then
		self.disabled = value == "1"
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	self.pointNames = self.pointNames or {}
	self.priority = self.priority or 0
	self.restrictTeam = self.restrictTeam or 0
	self.printName = self.printName or ""
	self.disabled = self.disabled or false
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:Points()
	local points = {}
	for _, name in ipairs(self.pointNames) do
		for _, ent in ipairs(ents.FindByName(name)) do
			if ent:GetClass() == "team_control_point" then points[#points + 1] = ent end
		end
	end
	return points
end

function ENT:HasPoint(point)
	for _, p in ipairs(self:Points()) do
		if p == point then return true end
	end
	return false
end

-- Owners and groups, for lib_rounds.
function ENT:PointStates()
	local states = {}
	for i, p in ipairs(self:Points()) do
		states[i] = { owner = WETSAND.CapTeam(p), group = WETSAND.PointGroup(p) }
	end
	return states
end

-- CTeamControlPointRound::IsPlayable. StartDisabled is not consulted, as in
-- the SDK.
function ENT:IsPlayable()
	return WETSAND.RoundsLib.RoundPlayable(self.restrictTeam, self:PointStates())
end

-- CTeamControlPointRound::CheckWinConditions: the winner (firing
-- OnWonByTeam1/2), or nil.
function ENT:CheckWinConditions()
	local winner = WETSAND.RoundsLib.RoundWinner(self.restrictTeam, self:PointStates())
	if winner then
		self:TriggerOutput(winner == WETSAND.TEAM_RED and "OnWonByTeam1" or "OnWonByTeam2", self)
	end
	return winner
end

function ENT:FireOnStart()
	self:TriggerOutput("OnStart", self)
end

function ENT:FireOnEnd()
	self:TriggerOutput("OnEnd", self)
end

local INPUTS = {
	enable = function(self) self.disabled = false end,
	disable = function(self) self.disabled = true end,
	-- The point list is looked up by name whenever it is needed.
	roundspawn = function() end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end
