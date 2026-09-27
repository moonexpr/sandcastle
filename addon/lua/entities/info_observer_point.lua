-- info_observer_point: a spectator camera position. GMod's spectating does
-- not use them yet; the entity exists so the map's I/O to it resolves.
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end
