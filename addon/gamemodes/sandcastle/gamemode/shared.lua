-- Sandcastle: Sandbox, plus working TF2 gameplay entities. On a map with a
-- tf_gamerules (any TF2 map) the round runs as in TF2; on any other map it is
-- plain Sandbox. Every override below defers to Sandbox first.
GM.Name = "Sandcastle"
GM.Author = "moonexpr"
GM.Email = ""
GM.Website = ""

DeriveGamemode("sandbox")

-- Modules in gamemode/tf2/ load by prefix: sh_ on both realms, sv_ on the
-- server, cl_ on clients. sh_core defines the TF2 table and loads first;
-- the rest load in name order.
function GM:TF2Modules(prefix)
	local files = file.Find(self.FolderName .. "/gamemode/tf2/" .. prefix .. "*.lua", "LUA")
	table.sort(files)
	return files
end

include("tf2/sh_core.lua")
for _, f in ipairs(GM:TF2Modules("sh_")) do
	if f ~= "sh_core.lua" then include("tf2/" .. f) end
end

-- TF2's team numbers (1 spectator, 2 RED, 3 BLU); GMod reserves only 0, 1001 and 1002.
function GM:CreateTeams()
	self.BaseClass.CreateTeams(self)
	team.SetUp(TF2.TEAM_SPECTATOR, "Spectator", Color(200, 200, 200), true)
	team.SetUp(TF2.TEAM_RED, "RED", TF2.TeamColor[TF2.TEAM_RED], false)
	team.SetUp(TF2.TEAM_BLUE, "BLU", TF2.TeamColor[TF2.TEAM_BLUE], false)
end

-- Neither Sandbox nor base defines StartCommand, so there is nothing to defer to.
function GM:StartCommand(ply, cmd)
	if TF2.Active() then TF2.RestrictCommand(ply, cmd) end
end
