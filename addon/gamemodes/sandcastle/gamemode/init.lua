AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("tf2/sh_core.lua")
AddCSLuaFile("tf2/sh_soundscripts.lua")
AddCSLuaFile("tf2/cl_hud.lua")
AddCSLuaFile("tf2/cl_announcer.lua")

include("shared.lua")
include("tf2/sv_world.lua")
include("tf2/sv_controlpoint.lua")

-- Until there is a team picker, anyone without a TF2 team plays BLU so they
-- can push the cart.
local function DefaultTeam(ply)
	if TF2.TeamOf(ply) == TF2.TEAM_UNASSIGNED then ply:SetTeam(TF2.TEAM_BLUE) end
end

function GM:PlayerInitialSpawn(ply, transition)
	self.BaseClass.PlayerInitialSpawn(self, ply, transition)
	if TF2.Active() then DefaultTeam(ply) end
end

function GM:PlayerSpawn(ply, transition)
	self.BaseClass.PlayerSpawn(self, ply, transition)
	-- Other addons move players between teams in their own spawn hooks (one
	-- puts everyone on a "Runner" team), so correct the team after them.
	if TF2.Active() then
		timer.Simple(0, function()
			if IsValid(ply) and TF2.Active() then DefaultTeam(ply) end
		end)
	end
end

-- Spawn in the team's own enabled spawn room.
function GM:PlayerSelectSpawn(ply, transition)
	if TF2.Active() then
		DefaultTeam(ply)
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

function GM:PostPlayerDeath(ply)
	self.BaseClass.PostPlayerDeath(self, ply)
	if IsValid(TF2.Rules) then TF2.Rules:OnPlayerDeath(ply) end
end
