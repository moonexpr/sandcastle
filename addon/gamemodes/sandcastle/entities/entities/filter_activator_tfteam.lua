-- filter_activator_tfteam (CFilterTFTeam): passes entities on its TF2 team,
-- or fails them when Negated. During team win the winners pass every team
-- filter, which opens the losers' spawn doors to them. With a controlpoint,
-- the filter takes that point's owner at each round start.
-- Engine triggers consult it through PassesFilter.
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
	elseif k == "controlpoint" then
		self.pointName = value
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	self.team = self.team or 0
	self.negated = self.negated or false
end

-- Team numbers are compared raw, as TF2 does: a player on another addon's
-- team matches neither RED nor BLU.
function ENT:PassesFilter(trigger, ent)
	return TF2.TeamRules.FilterPasses(self.team, self.negated, ent:Team(), TF2.State(), GetGlobal2Int("tf2.winner", 0))
end

-- CFilterTFTeam::InputRoundActivate
function ENT:RoundActivate()
	if not self.pointName or self.pointName == "" then return end
	local point = TF2.FindByName(self.pointName)
	if IsValid(point) then self.team = TF2.CapTeam(point) end
end

local INPUTS = {
	setteam = function(self, value) self.team = tonumber(value) or 0 end,
	roundactivate = function(self) self:RoundActivate() end,
	-- CFilterTFTeam::InputRoundSpawn does nothing.
	roundspawn = function() end,
	-- CBaseFilter::InputTestActivator
	testactivator = function(self, value, activator)
		if self:PassesFilter(self, activator) then
			self:TriggerOutput("OnPass", activator)
		else
			self:TriggerOutput("OnFail", activator)
		end
	end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value, activator)
	return true
end
