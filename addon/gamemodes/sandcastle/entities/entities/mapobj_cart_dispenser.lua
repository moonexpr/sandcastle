-- mapobj_cart_dispenser: the payload cart's level 1 dispenser. It heals and
-- resupplies players of its team standing in its dispenser_touch_trigger.
ENT.Type = "point"
ENT.Base = "base_point"

local HEAL_PER_SECOND = 10     -- level 1 dispenser heal rate
local AMMO_INTERVAL = 1.0      -- seconds between ammo doses
local AMMO_FRACTION = 0.2      -- of each weapon's ceiling per dose

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if k == "touch_trigger" then
		self.triggerName = value
	elseif k == "teamnum" then
		self.team = tonumber(value) or 0
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	self.team = self.team or 0
	self.enabled = true
	self.healCarry = {}
	self.nextAmmo = 0
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:Think()
	local dt = 0.1
	self:NextThink(CurTime() + dt)
	local trigger = TF2.FindByName(self.triggerName)
	if not self.enabled or not IsValid(trigger) then return true end
	local giveAmmo = CurTime() >= self.nextAmmo
	if giveAmmo then self.nextAmmo = CurTime() + AMMO_INTERVAL end
	for _, ply in ipairs(TF2.PlayersInside(trigger)) do
		if self.team == TF2.TEAM_UNASSIGNED or TF2.TeamOf(ply) == self.team then
			-- Heal in whole points, carrying the fraction between thinks.
			local carry = (self.healCarry[ply] or 0) + HEAL_PER_SECOND * dt
			local whole = math.floor(carry)
			self.healCarry[ply] = carry - whole
			if whole > 0 and ply:Health() < ply:GetMaxHealth() then
				ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + whole))
			end
			if giveAmmo then TF2.GiveAmmoFraction(ply, AMMO_FRACTION) end
		end
	end
	return true
end

function ENT:AcceptInput(name, activator, caller, value)
	local input = string.lower(name)
	if input == "enable" then
		self.enabled = true
	elseif input == "disable" then
		self.enabled = false
	elseif input == "setteam" then
		self.team = tonumber(value) or 0
	else
		return false
	end
	return true
end
