-- Common base for item_healthkit_* and item_ammopack_*: a static pickup that
-- restores a fraction of health or ammo on touch and comes back after 10s.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.RespawnTime = 10
ENT.Model = "models/items/medkit_small.mdl"
ENT.Fraction = 0.2
ENT.Kind = "health"

if CLIENT then return end

local SOUNDS = {
	health = "items/smallmedkit1.wav",
	ammo = "items/ammo_pickup.wav",
}

function ENT:Initialize()
	self:SetModel(self.Model)
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_BBOX)
	self:SetCollisionBounds(Vector(-16, -16, 0), Vector(16, 16, 24))
	self:SetTrigger(true)
	self:AddSolidFlags(FSOLID_NOT_SOLID)
	self.available = true
end

function ENT:Apply(ply)
	if self.Kind == "health" then return TF2.HealFraction(ply, self.Fraction) end
	return TF2.GiveAmmoFraction(ply, self.Fraction)
end

function ENT:Touch(ent)
	if not self.available or not TF2.IsAliveInGame(ent) then return end
	if not self:Apply(ent) then return end
	ent:EmitSound(SOUNDS[self.Kind])
	self.available = false
	self:SetNoDraw(true)
	timer.Simple(self.RespawnTime, function()
		if not IsValid(self) then return end
		self.available = true
		self:SetNoDraw(false)
	end)
end
