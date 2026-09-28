-- TF2 player conditions (CTFPlayerShared::AddCond / RemoveCond) and stuns
-- (StunPlayer), as far as GMod can express them: map triggers add and
-- remove them. The effects GMod can show are applied here and in sh_core.lua
-- (movement); the others are kept, so a later RemoveCond or a condition
-- filter still sees them, but do nothing.
--   INVULNERABLE: no damage taken. CRITBOOSTED(_USER_BUFF): triple damage dealt.
--   BLAST_IMMUNE: no blast damage. SPEED_BOOST: +40% speed (max +105).
--   HALLOWEEN_QUICK_HEAL: heals 30 health a second, up to max health.
-- Movement and stun state reach clients as NW2 vars for prediction:
-- tf2.speedboost, tf2.stunEnd, tf2.stunAmount, tf2.stunFlags.
local P = TF2.PlayerRules
local C = P.COND

-- HALLOWEEN_QUICK_HEAL: CTFPlayerShared::Heal(outer, 30, ...), per second.
local QUICK_HEAL_RATE = 30
local THINK_INTERVAL = 0.1

local function Conds(ply)
	ply.tf2Conds = ply.tf2Conds or {}
	return ply.tf2Conds
end

local function SyncMovement(ply)
	ply:SetNW2Bool("tf2.speedboost", P.InCond(Conds(ply), C.SPEED_BOOST, CurTime()))
end

function TF2.AddCondition(ply, cond, duration)
	P.AddCond(Conds(ply), cond, duration, CurTime())
	if cond == C.BURNING then ply:Ignite(duration > 0 and duration or 10) end
	SyncMovement(ply)
end

function TF2.RemoveCondition(ply, cond)
	P.RemoveCond(Conds(ply), cond)
	if cond == C.BURNING then ply:Extinguish() end
	SyncMovement(ply)
end

function TF2.InCondition(ply, cond)
	return P.InCond(Conds(ply), cond, CurTime())
end

-- CTFPlayerShared::RemoveAllCond: also ends a stun.
function TF2.RemoveAllConditions(ply)
	ply.tf2Conds = {}
	ply.tf2Stun = nil
	ply:SetNW2Float("tf2.stunEnd", 0)
	ply:SetNW2Int("tf2.stunFlags", 0)
	SyncMovement(ply)
end

-- CTFPlayer::Regenerate's condition removals.
function TF2.ClearConditionsOnRegenerate(ply)
	P.ClearOnRegenerate(Conds(ply))
	ply:Extinguish()
	SyncMovement(ply)
end

function TF2.StunPlayer(ply, duration, reduction, flags)
	local stun = P.Stun(ply.tf2Stun, duration, reduction, flags, CurTime())
	ply.tf2Stun = stun
	ply:SetNW2Float("tf2.stunEnd", stun.ends)
	ply:SetNW2Float("tf2.stunAmount", stun.reduction)
	ply:SetNW2Int("tf2.stunFlags", stun.flags)
end

-- A player starts each life with no conditions.
hook.Add("PlayerSpawn", "tf2.conditions", TF2.RemoveAllConditions)
hook.Add("PostPlayerDeath", "tf2.conditions", TF2.RemoveAllConditions)

hook.Add("EntityTakeDamage", "tf2.conditions", function(target, dmg)
	if not target:IsPlayer() then return end
	local attacker = dmg:GetAttacker()
	local attackerConds = IsValid(attacker) and attacker:IsPlayer() and Conds(attacker) or {}
	local scale = P.DamageScale(Conds(target), attackerConds, dmg:IsDamageType(DMG_BLAST), CurTime())
	if scale ~= 1 then dmg:ScaleDamage(scale) end
end)

timer.Create("tf2.conditions", THINK_INTERVAL, 0, function()
	local now = CurTime()
	for _, ply in ipairs(player.GetAll()) do
		local conds = ply.tf2Conds
		if conds and next(conds) then
			if #P.ExpireConds(conds, now) > 0 then SyncMovement(ply) end
			if P.InCond(conds, C.HALLOWEEN_QUICK_HEAL, now) and ply:Alive() and ply:Health() < ply:GetMaxHealth() then
				ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + math.ceil(QUICK_HEAL_RATE * THINK_INTERVAL)))
			end
		end
	end
end)
