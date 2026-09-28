-- tf_logic_holiday: marks a holiday map (CTFHolidayEntity). Sandcastle has no
-- holidays, spells or Hell, so its keyvalues and inputs are accepted and do
-- nothing; accepting them keeps the map's I/O from reporting unknown inputs.
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:KeyValue(key, value)
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

local INPUTS = {
	halloweensetusingspells = true,
	halloween2013teleporttohell = true,
}

function ENT:AcceptInput(name)
	return INPUTS[string.lower(name)] == true
end
