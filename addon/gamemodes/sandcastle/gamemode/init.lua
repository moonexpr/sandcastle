AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

for _, f in ipairs(GM:TF2Modules("sh_")) do AddCSLuaFile("wetsand/" .. f) end
for _, f in ipairs(GM:TF2Modules("cl_")) do AddCSLuaFile("wetsand/" .. f) end
for _, f in ipairs(GM:TF2Modules("sv_")) do include("wetsand/" .. f) end

-- New players are auto-assigned (GetAutoTeam) before their first spawn.
function GM:PlayerInitialSpawn(ply, transition)
	self.BaseClass.PlayerInitialSpawn(self, ply, transition)
	if TF2.Active() then TF2.SetPlayerTeam(ply, TF2.AutoTeam(), true) end
end

function GM:PlayerSpawn(ply, transition)
	self.BaseClass.PlayerSpawn(self, ply, transition)
	if not TF2.Active() then return end
	if ply:Team() == TF2.TEAM_SPECTATOR then TF2.StartObserving(ply) end
	-- Other addons move players between teams in their own spawn hooks (one
	-- puts everyone on a "Runner" team), so correct the team after them.
	timer.Simple(0, function()
		if IsValid(ply) and TF2.Active() then TF2.RestoreTeam(ply) end
	end)
end

-- Spawn at the team's next valid info_player_teamspawn for this round.
function GM:PlayerSelectSpawn(ply, transition)
	if TF2.Active() then
		TF2.RestoreTeam(ply)
		local spot = TF2.PickSpawn(TF2.TeamOf(ply))
		if spot then return spot end
	end
	return self.BaseClass.PlayerSelectSpawn(self, ply, transition)
end

-- On TF2 maps, players come back with tf_gamerules' respawn waves rather than
-- when they click.
function GM:PlayerDeathThink(ply)
	if TF2.Active() then return false end
	return self.BaseClass.PlayerDeathThink(self, ply)
end

-- CTFPlayer::Event_Killed drops an ammo pack where the player died.
function GM:DoPlayerDeath(ply, attacker, dmg)
	self.BaseClass.DoPlayerDeath(self, ply, attacker, dmg)
	if TF2.Active() and not ply.tf2ChangingTeam then TF2.DropAmmoPack(ply) end
end

-- Neither Sandbox nor base defines PostPlayerDeath.
function GM:PostPlayerDeath(ply)
	if IsValid(TF2.Rules) then TF2.Rules:OnPlayerDeath(ply) end
end

-- The team key (F2, gm_showteam) opens TF2's team menu on TF2 maps.
function GM:ShowTeam(ply)
	if TF2.Active() then
		TF2.ShowTeamMenu(ply)
		return
	end
	self.BaseClass.ShowTeam(self, ply)
end

-- Base's changeteam command goes through TF2's join rules on TF2 maps.
local JOIN_NAME = {
	[TF2.TEAM_SPECTATOR] = "spectate",
	[TF2.TEAM_RED] = "red",
	[TF2.TEAM_BLUE] = "blue",
}

function GM:PlayerRequestTeam(ply, teamIndex)
	if TF2.Active() then
		if JOIN_NAME[teamIndex] then TF2.JoinTeam(ply, JOIN_NAME[teamIndex]) end
		return
	end
	self.BaseClass.PlayerRequestTeam(self, ply, teamIndex)
end
