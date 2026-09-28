local T = dofile("tests/harness.lua")
local Fake = dofile("tests/fake_actor.lua")
local Combat = T.require("foundation.combat")
local Teams = T.require("foundation.teams")

local V = Fake.Vector

local RADIUS = 146 -- a rocket's
local DAMAGE = 90

local function Explosion(overrides)
	local config = {
		origin = V(0, 0, 0),
		radius = RADIUS,
		damage = DAMAGE,
		attackerTeam = Teams.RED,
		attacker = "attacker",
		halfFalloff = false,
		forceFriendlyFire = false,
		crit = false,
	}
	for k, v in pairs(overrides or {}) do config[k] = v end
	return Combat.Explosion.New(config)
end

-- A BLU player in the open unless the case says otherwise.
local function Victim(overrides)
	local victim = {
		team = Teams.BLUE,
		isAttacker = false,
		distance = 0,
		visible = true,
	}
	for k, v in pairs(overrides or {}) do victim[k] = v end
	return victim
end

T.test("the crit multiplier is TF2's", function()
	T.eq(Combat.CRIT_MULTIPLIER, 3, "TF_DAMAGE_CRIT_MULTIPLIER")
end)

-- CTFRadiusDamageInfo::CalculateFalloff and ApplyToEntity

T.test("full damage at the centre, damage times damage/radius at the edge", function()
	local e = Explosion()
	T.near(e:DamageTo(Victim({ distance = 0 })), DAMAGE, 1e-9, "centre")
	T.near(e:DamageTo(Victim({ distance = RADIUS })), DAMAGE * DAMAGE / RADIUS, 1e-9, "edge")
	T.near(e:DamageTo(Victim({ distance = RADIUS / 2 })), (DAMAGE + DAMAGE * DAMAGE / RADIUS) / 2, 1e-9, "halfway")
end)

T.test("half falloff halves the damage at the edge", function()
	local e = Explosion({ halfFalloff = true })
	T.near(e:DamageTo(Victim({ distance = 0 })), DAMAGE, 1e-9, "centre")
	T.near(e:DamageTo(Victim({ distance = RADIUS })), DAMAGE / 2, 1e-9, "edge")
	T.near(e:DamageTo(Victim({ distance = RADIUS / 2 })), DAMAGE * 0.75, 1e-9, "halfway")
end)

T.test("beyond the radius the damage stays at the edge's", function()
	local e = Explosion({ halfFalloff = true })
	T.near(e:DamageTo(Victim({ distance = 2 * RADIUS })), DAMAGE / 2, 1e-9, "clamped")
end)

T.test("a crit triples what the falloff leaves", function()
	local e = Explosion({
		halfFalloff = true,
		crit = true,
	})
	T.near(e:DamageTo(Victim({ distance = RADIUS })), DAMAGE / 2 * Combat.CRIT_MULTIPLIER, 1e-9, "crit edge")
end)

T.test("an explosion with no radius hurts nobody", function()
	T.eq(Explosion({ radius = 0 }):DamageTo(Victim()), nil, "no radius")
end)

-- Sides

T.test("an enemy is hurt, a teammate is not, and the attacker hurts itself", function()
	local e = Explosion()
	T.eq(e:DamageTo(Victim({ team = Teams.BLUE })), DAMAGE, "enemy")
	T.eq(e:DamageTo(Victim({ team = Teams.RED })), nil, "teammate")
	T.eq(e:DamageTo(Victim({
		team = Teams.RED,
		isAttacker = true,
	})), DAMAGE, "self")
	T.eq(e:DamageTo(Victim({ team = Teams.HALLOWEEN })), DAMAGE, "a skeleton")
end)

T.test("forced friendly fire hurts teammates too", function()
	local e = Explosion({ forceFriendlyFire = true })
	T.eq(e:DamageTo(Victim({ team = Teams.RED })), DAMAGE, "teammate")
end)

T.test("a Halloween explosion spares Halloween NPCs and hurts both teams", function()
	local e = Explosion({ attackerTeam = Teams.HALLOWEEN })
	T.eq(e:DamageTo(Victim({ team = Teams.HALLOWEEN })), nil, "skeleton")
	T.eq(e:DamageTo(Victim({ team = Teams.RED })), DAMAGE, "red")
	T.eq(e:DamageTo(Victim({ team = Teams.BLUE })), DAMAGE, "blue")
end)

T.test("an explosion with no team has no teammates", function()
	local e = Explosion({ attackerTeam = Teams.UNASSIGNED })
	T.eq(e:DamageTo(Victim({ team = Teams.UNASSIGNED })), DAMAGE, "a teamless prop")
end)

-- Line of sight: nothing passes through the world.

T.test("a victim the blast cannot see is not hurt, whatever its side", function()
	local e = Explosion({ forceFriendlyFire = true })
	T.eq(e:DamageTo(Victim({ visible = false })), nil, "enemy behind a wall")
	T.eq(e:DamageTo(Victim({
		team = Teams.RED,
		isAttacker = true,
		visible = false,
	})), nil, "self behind a wall")
end)

-- Distance: the nearer of the centre and the origin; a direct hit is 0.

T.test("the distance is to the nearer of the victim's centre and origin", function()
	local e = Explosion({ origin = V(0, 0, 100) })
	T.eq(e:DistanceTo(V(30, 40, 100), V(30, 40, 64)), 50, "centre nearer")
	T.eq(e:DistanceTo(V(0, 0, 36), V(0, 0, 90)), 10, "origin nearer")
	T.eq(e:DistanceTo(V(30, 40, 100), V(30, 40, 64), true), 0, "direct hit")
end)

T.test("a whole blast: a rocket among a crowd", function()
	local e = Explosion({ origin = V(0, 0, 0) })
	local crowd = {
		{
			name = "enemy at the blast",
			team = Teams.BLUE,
			center = V(0, 0, 36),
			origin = V(0, 0, 0),
			visible = true,
			expected = DAMAGE,
		},
		{
			name = "enemy hit directly",
			team = Teams.BLUE,
			center = V(100, 0, 36),
			origin = V(100, 0, 0),
			visible = true,
			direct = true,
			expected = DAMAGE,
		},
		{
			name = "enemy at the edge",
			team = Teams.BLUE,
			center = V(RADIUS, 0, 36),
			origin = V(RADIUS, 0, 0),
			visible = true,
			expected = DAMAGE * DAMAGE / RADIUS,
		},
		{
			name = "enemy behind a wall",
			team = Teams.BLUE,
			center = V(50, 0, 36),
			origin = V(50, 0, 0),
			visible = false,
		},
		{
			name = "teammate",
			team = Teams.RED,
			center = V(10, 0, 36),
			origin = V(10, 0, 0),
			visible = true,
		},
	}
	for _, v in ipairs(crowd) do
		local amount = e:DamageTo({
			team = v.team,
			isAttacker = false,
			distance = e:DistanceTo(v.center, v.origin, v.direct),
			visible = v.visible,
		})
		if v.expected then
			T.near(amount, v.expected, 1e-9, v.name)
		else
			T.eq(amount, nil, v.name)
		end
	end
end)

T.finish()
