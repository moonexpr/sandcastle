-- filter_activator_tfteam: passes entities on its TF2 team (or fails them,
-- when Negated). Engine triggers consult it through PassesFilter.
ENT.Type = "filter"
ENT.Base = "base_filter"

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if k == "teamnum" then
		self.team = tonumber(value) or 0
	elseif k == "negated" then
		-- Hammer sometimes stores the choice's label ("Allow entities that
		-- match criteria") rather than 0/1; only "1" negates.
		self.negated = value == "1"
	end
end

function ENT:Initialize()
	self.team = self.team or 0
end

function ENT:PassesFilter(trigger, ent)
	local match = TF2.TeamOf(ent) == self.team
	if self.negated then return not match end
	return match
end

function ENT:AcceptInput(name, activator, caller, value)
	if string.lower(name) ~= "setteam" then return false end
	self.team = tonumber(value) or 0
	return true
end
