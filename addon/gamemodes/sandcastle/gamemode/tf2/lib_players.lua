-- Player rules of TF2 as pure functions: pickup amounts, resupply, the
-- player conditions map triggers apply, and stuns. No GMod globals; the
-- modules that use it include it.
local P = {}

-- PackRatios (tf_powerup.cpp) and ITEM_RESPAWN_TIME (tf_gamerules.cpp).
P.PACK_RATIO = { small = 0.2, medium = 0.5, full = 1.0 }
P.ITEM_RESPAWN_TIME = 10

-- CTFAmmoPack: a medium pack, gone after 30s, which its dropper may not
-- pick up before FlyThink at 0.75s.
P.DROPPED_PACK = { ratio = 0.5, lifetime = 30, ownerDelay = 0.75 }

-- CHealthKit::MyTouch: TakeHealth(ceil(max * ratio)), which stops at max.
function P.HealthKitHeal(health, maxHealth, ratio)
	return math.max(0, math.min(math.ceil(maxHealth * ratio), maxHealth - health))
end

-- The kit is used up when it healed, or when it put out a fire.
function P.HealthKitTaken(given, burning)
	return given > 0 or burning
end

-- CAmmoPack::MyTouch through GiveAmmo: ceil(max * ratio), up to max.
function P.AmmoAfterPack(have, max, ratio)
	if have >= max then return have end
	return math.min(max, have + math.ceil(max * ratio))
end

-- CTFPlayer::Regenerate: InitClass refills health; a boost over max is kept.
function P.RegenerateHealth(health, maxHealth)
	return math.max(health, maxHealth)
end

-- ETFCond values (tf_shareddefs.h) of the conditions payload maps apply.
P.COND = {
	INVULNERABLE = 5,
	CRITBOOSTED = 11,
	PHASE = 14,
	BURNING = 22,
	URINE = 24,
	BLEEDING = 25,
	MAD_MILK = 27,
	SPEED_BOOST = 32,
	CRITBOOSTED_USER_BUFF = 34,
	CANNOT_SWITCH_FROM_MELEE = 41,
	BLAST_IMMUNE = 68,
	HALLOWEEN_QUICK_HEAL = 73,
	MELEE_ONLY = 85,
	PURGATORY = 108,
	GAS = 123,
}
local C = P.COND

-- PERMANENT_CONDITION
local PERMANENT = -1

-- conds maps a condition to the time it ends.
function P.AddCond(conds, cond, duration, now)
	conds[cond] = duration == PERMANENT and math.huge or now + duration
end

function P.RemoveCond(conds, cond)
	conds[cond] = nil
end

function P.InCond(conds, cond, now)
	local ends = conds[cond]
	return ends ~= nil and now < ends
end

-- Drops finished conditions; returns them.
function P.ExpireConds(conds, now)
	local gone = {}
	for cond, ends in pairs(conds) do
		if now >= ends then gone[#gone + 1] = cond end
	end
	for _, cond in ipairs(gone) do conds[cond] = nil end
	return gone
end

-- The conditions CTFPlayer::Regenerate removes that Sandcastle tracks.
local REGENERATE_CLEARS = { C.BURNING, C.URINE, C.MAD_MILK, C.GAS, C.BLEEDING, C.PHASE }

function P.ClearOnRegenerate(conds)
	for _, cond in ipairs(REGENERATE_CLEARS) do conds[cond] = nil end
end

-- TF_STUN_* (tf_shareddefs.h)
P.STUN = { MOVEMENT = 1, CONTROLS = 2, NO_EFFECTS = 32, LOSER_STATE = 64 }

-- CTriggerStun::StunEntity: stun_type 0 movement, 1 controls, 2 loser state.
function P.StunFlags(stunType)
	if stunType == 1 then return P.STUN.MOVEMENT + P.STUN.CONTROLS end
	if stunType == 2 then return P.STUN.MOVEMENT + P.STUN.LOSER_STATE end
	return P.STUN.MOVEMENT
end

-- CTFPlayerShared::StunPlayer keeps a list of stuns and applies the
-- strongest; Sandcastle folds them into one: the later end, the stronger
-- slow, and every flag.
function P.Stun(current, duration, reduction, flags, now)
	local ends = now + duration
	if not current or now >= current.ends then
		return { ends = ends, reduction = reduction, flags = flags }
	end
	return {
		ends = math.max(current.ends, ends),
		reduction = math.max(current.reduction, reduction),
		flags = bit.bor(current.flags, flags),
	}
end

function P.StunHas(stun, flag, now)
	return stun ~= nil and now < stun.ends and bit.band(stun.flags, flag) ~= 0
end

-- tf_whip_speed_increase: the cap on a speed boost's bonus.
local SPEED_BOOST_CAP = 105

-- TeamFortress_CalculateMaxSpeed adds the boost; CTFGameMovement then
-- scales by the stun's slow.
function P.MaxSpeed(base, speedBoost, stunReduction)
	local speed = base
	if speedBoost and speed > 0 then speed = speed + math.min(speed * 0.4, SPEED_BOOST_CAP) end
	return speed * (1 - stunReduction)
end

-- TF_DAMAGE_CRIT_MULTIPLIER
local CRIT_MULTIPLIER = 3

-- Damage scale from conditions: an invulnerable victim, or a blast-immune
-- one hit by a blast, takes nothing; a crit-boosted attacker deals triple.
function P.DamageScale(victimConds, attackerConds, isBlast, now)
	if P.InCond(victimConds, C.INVULNERABLE, now) then return 0 end
	if isBlast and P.InCond(victimConds, C.BLAST_IMMUNE, now) then return 0 end
	if P.InCond(attackerConds, C.CRITBOOSTED, now) or P.InCond(attackerConds, C.CRITBOOSTED_USER_BUFF, now) then
		return CRIT_MULTIPLIER
	end
	return 1
end

return P
