-- team_control_point_round: names the control points that make up one
-- mini-round, and which team may not win it by capping them all.
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
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	self.pointNames = self.pointNames or {}
	self.priority = self.priority or 0
	self.restrictTeam = self.restrictTeam or 0
	hook.Add("TF2RoundActive", self, function() self:TriggerOutput("OnStart", self) end)
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
