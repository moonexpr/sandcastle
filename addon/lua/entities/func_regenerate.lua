-- func_regenerate: the resupply locker volume. A player of its team who walks
-- in is refilled to full health and ammo, at most once every 3 seconds, and
-- the locker prop plays open then close (CRegenerateZone::Regenerate).
ENT.Type = "brush"
ENT.Base = "tf2_brush_volume"

local NEXT_USE_TIME = 3.0
local SOUND = "items/regenerate.wav"

function ENT:VolumeInit()
	self.associatedModel = self:Key("associatedmodel")
end

function ENT:Think()
	self:NextThink(CurTime() + 0.1)
	if not self.enabled then return true end
	local now = CurTime()
	for _, ply in ipairs(TF2.PlayersInside(self)) do
		if self:AllowsTeam(TF2.TeamOf(ply)) and now >= (ply.tf2NextRegen or 0) then
			self:Regenerate(ply)
		end
	end
	return true
end

function ENT:Regenerate(ply)
	ply.tf2NextRegen = CurTime() + NEXT_USE_TIME
	ply:SetHealth(math.max(ply:Health(), ply:GetMaxHealth()))
	ply:Extinguish()
	TF2.GiveAmmoFraction(ply, 1.0)
	ply:EmitSound(SOUND)
	local prop = TF2.FindByName(self.associatedModel)
	if IsValid(prop) then
		prop:Fire("SetAnimation", "open")
		prop:Fire("SetAnimation", "close", NEXT_USE_TIME - 1.0)
	end
end
