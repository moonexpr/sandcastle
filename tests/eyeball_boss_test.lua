local T = dofile("tests/harness.lua")
local FakeCombatant = dofile("tests/fake_combatant.lua")
local Projectile = T.require("foundation.projectile")
local Rocket = T.require("foundation.projectile.rocket")
local Combat = T.require("foundation.combat")
local Teams = T.require("foundation.teams")

local V = FakeCombatant.Vector

-------------------------------------------------------------------------------
-- The rocket (CTFBaseRocket, CTFProjectile_Rocket)

local function NewRocket(overrides)
	local config = {
		damage = 50,
		crit = true,
		team = Teams.HALLOWEEN,
		attacker = "eyeball",
	}
	for k, v in pairs(overrides or {}) do config[k] = v end
	return Projectile.New(Rocket, config, 0)
end

T.test("a rocket flies straight and blows up on whatever it touches", function()
	T.eq(Rocket.GRAVITY, 0, "straight")
	T.eq(NewRocket():Touch({
		world = true,
		enemy = false,
	}), Projectile.DETONATE, "the world")
	T.eq(NewRocket():Touch({
		world = false,
		enemy = true,
	}), Projectile.DETONATE, "an enemy")
	T.eq(NewRocket():Touch({
		world = false,
		enemy = false,
	}), Projectile.DETONATE, "a teammate's body")
	local rocket = NewRocket()
	T.eq(rocket:Tick(1000), Projectile.NONE, "no fuse")
	rocket:Touch({ world = true })
	T.eq(rocket:Touch({ world = true }), Projectile.NONE, "only once")
end)

T.test("a rocket's blast is TF_ROCKET_RADIUS with its damage, team, attacker and crit", function()
	T.eq(Rocket.ROCKET_RADIUS, 146, "TF_ROCKET_RADIUS")
	local rocket = NewRocket()
	local blast = Rocket.Blast(rocket.state, V(1, 2, 3))
	T.eq(blast.origin, V(1, 2, 3), "origin")
	T.eq(blast.radius, Rocket.ROCKET_RADIUS, "radius")
	T.eq(blast.damage, 50, "base damage: the explosion applies the crit")
	T.eq(blast.attackerTeam, Teams.HALLOWEEN, "team")
	T.eq(blast.attacker, "eyeball", "attacker")
	T.eq(blast.crit, true, "crit")
	T.eq(blast.halfFalloff, false, "full falloff")
	T.eq(blast.forceFriendlyFire, false, "no friendly fire")
	local amount = Combat.Explosion.New(blast):DamageTo({
		team = Teams.RED,
		isAttacker = false,
		distance = 0,
		visible = true,
	})
	T.eq(amount, 50 * Combat.CRIT_MULTIPLIER, "a crit rocket's direct hit")
	T.eq(Rocket.Blast(NewRocket({ radius = 200 }).state, V(0, 0, 0)).radius, 200, "a launcher's own radius")
end)

T.test("a rocket trails smoke, and a crit one its team's crit glow or the eyeball's", function()
	local function Trails(overrides) return table.concat(Rocket.Trails(NewRocket(overrides).state), ",") end
	T.eq(Trails({ crit = false }), Rocket.TRAIL, "plain")
	T.eq(Trails({
		crit = true,
		team = Teams.RED,
	}), Rocket.TRAIL .. ",critical_rocket_red", "RED crit")
	T.eq(Trails({
		crit = true,
		team = Teams.BLUE,
	}), Rocket.TRAIL .. ",critical_rocket_blue", "BLU crit")
	T.eq(Trails({ crit = true }), Rocket.TRAIL .. ",eyeboss_projectile", "the eyeball's crit")
end)

T.finish()
