AddCSLuaFile()
AddCSLuaFile("tf2ents/sh_core.lua")
AddCSLuaFile("tf2ents/sh_soundscripts.lua")
AddCSLuaFile("tf2ents/cl_hud.lua")

include("tf2ents/sh_core.lua")
include("tf2ents/sh_soundscripts.lua")

if SERVER then
	include("tf2ents/sv_world.lua")
	include("tf2ents/sv_controlpoint.lua")
else
	include("tf2ents/cl_hud.lua")
end
