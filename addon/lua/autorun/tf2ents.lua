AddCSLuaFile()
AddCSLuaFile("tf2ents/sh_core.lua")
AddCSLuaFile("tf2ents/cl_hud.lua")

include("tf2ents/sh_core.lua")

if SERVER then
	include("tf2ents/sv_world.lua")
else
	include("tf2ents/cl_hud.lua")
end
