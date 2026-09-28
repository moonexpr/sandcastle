-- Common base for item_healthkit_* and item_ammopack_* (CTFPowerup, CItem).
-- A live player of its team (TeamNum 0: anyone) who can use it takes it:
-- a health kit heals ceil(max * size) and puts out fire, an ammo pack refills
-- each weapon by that share; the player alone hears the pickup sound, and
-- OnPlayerTouch fires. It comes back 10 seconds later with Item.Materialize,
-- or, with AutoMaterialize off, only when enabled again. Disabled pickups
-- are hidden and cannot be taken.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.Model = "models/items/medkit_small.mdl"
ENT.Size = "small"
ENT.Kind = "health"

if CLIENT then return end

local P = WETSAND.PlayerRules

local SOUNDS = {
	health = "HealthKit.Touch",
	ammo = "AmmoPack.Touch",
}

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if k == "teamnum" then
		self.team = tonumber(value) or 0
	elseif k == "startdisabled" then
		self.startDisabled = value == "1"
	elseif k == "automaterialize" then
		self.autoMaterialize = value ~= "0"
	elseif k == "powerup_model" then
		self.powerupModel = value
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

-- CTFPowerup::GetPowerupModel: the map's model when it exists.
function ENT:PowerupModel()
	if self.powerupModel and self.powerupModel ~= "" and util.IsValidModel(self.powerupModel) then
		return self.powerupModel
	end
	return self.Model
end

function ENT:Initialize()
	self:SetModel(self:PowerupModel())
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_BBOX)
	self:SetCollisionBounds(Vector(-16, -16, 0), Vector(16, 16, 24))
	self:SetTrigger(true)
	self:AddSolidFlags(FSOLID_NOT_SOLID)
	self:ResetSequence(self:LookupSequence("idle"))
	self.team = self.team or 0
	if self.autoMaterialize == nil then self.autoMaterialize = true end
	self.respawning = false
	self:SetDisabled(self.startDisabled == true)
end

-- CTFPowerup::SetDisabled
function ENT:SetDisabled(disabled)
	self.disabled = disabled
	if disabled then
		self:SetNoDraw(true)
	elseif not self.respawning then
		self:SetNoDraw(false)
	elseif not self.autoMaterialize then
		self:Materialize()
	end
end

-- CTFPowerup::Materialize_Internal
function ENT:Materialize()
	if not self.disabled and self:GetNoDraw() then
		self:EmitSound("Item.Materialize")
		self:SetNoDraw(false)
	end
	self.respawning = false
end

-- CItem::Respawn, then CTFPowerup::Materialize once the respawn time is up.
function ENT:Respawn()
	self.respawning = true
	self:SetNoDraw(true)
	timer.Simple(P.ITEM_RESPAWN_TIME, function()
		if IsValid(self) and self.respawning and self.autoMaterialize then self:Materialize() end
	end)
end

-- CTFPowerup::ValidTouch
function ENT:ValidTouch(ply)
	if self.disabled or self.respawning or not WETSAND.IsAliveInGame(ply) then return false end
	return self.team == 0 or ply:Team() == self.team
end

-- CHealthKit::MyTouch / CAmmoPack::MyTouch: whether the pickup was used.
function ENT:MyTouch(ply)
	local ratio = P.PACK_RATIO[self.Size]
	if self.Kind == "ammo" then return WETSAND.GiveAmmoFraction(ply, ratio) end
	local given = P.HealthKitHeal(ply:Health(), ply:GetMaxHealth(), ratio)
	local burning = ply:IsOnFire()
	if not P.HealthKitTaken(given, burning) then return false end
	ply:SetHealth(ply:Health() + given)
	WETSAND.RemoveCondition(ply, P.COND.BURNING)
	ply:Extinguish()
	return true
end

-- CItem::ItemTouch
function ENT:Touch(ply)
	if not self:ValidTouch(ply) or not self:MyTouch(ply) then return end
	WETSAND.PlaySoundTo(ply, self, SOUNDS[self.Kind])
	self:TriggerOutput("OnPlayerTouch", ply)
	self:Respawn()
end

local INPUTS = {
	enable = function(self) self:SetDisabled(false) end,
	disable = function(self) self:SetDisabled(true) end,
	toggle = function(self) self:SetDisabled(not self.disabled) end,
	setteam = function(self, value) self.team = tonumber(value) or 0 end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end