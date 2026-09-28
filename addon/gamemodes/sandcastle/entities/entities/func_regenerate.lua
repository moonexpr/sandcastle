-- func_regenerate (CRegenerateZone): the resupply locker volume. A player it
-- serves (its team, or during team win the winners at every locker, never
-- in a stalemate) is resupplied at most once every 3 seconds
-- (CTFPlayer::Regenerate), hears Regenerate.Touch alone, and the locker prop
-- opens, then closes a second before the next use.
ENT.Type = "brush"
ENT.Base = "wetsand_brush_volume"

local NEXT_USE_TIME = 3.0
local SOUND = "Regenerate.Touch"

function ENT:VolumeInit()
	self.associatedModel = self:Key("associatedmodel")
end

function ENT:Think()
	self:NextThink(CurTime() + 0.1)
	if not self.enabled then return true end
	local now, state, winner = CurTime(), TF2.State(), GetGlobal2Int("tf2.winner", 0)
	for _, ply in ipairs(TF2.PlayersInside(self)) do
		if now >= (ply.tf2NextRegen or 0) and TF2.TeamRules.RegenerateAllowed(self.team, ply:Team(), state, winner) then
			self:Regenerate(ply)
		end
	end
	return true
end

-- CRegenerateZone::Regenerate
function ENT:Regenerate(ply)
	TF2.RegeneratePlayer(ply)
	ply.tf2NextRegen = CurTime() + NEXT_USE_TIME
	TF2.PlaySoundTo(ply, ply, SOUND)
	local prop = TF2.FindByName(self.associatedModel)
	if IsValid(prop) then
		prop:Fire("SetAnimation", "open")
		prop:Fire("SetAnimation", "close", NEXT_USE_TIME - 1.0)
	end
end
