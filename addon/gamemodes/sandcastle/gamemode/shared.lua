-- Sandcastle: Sandbox, plus working TF2 gameplay entities. On a map with a
-- tf_gamerules (any TF2 map) the round runs as in TF2; on any other map it is
-- plain Sandbox. Every override below defers to Sandbox first.
GM.Name = "Sandcastle"
GM.Author = "moonexpr"
GM.Email = ""
GM.Website = ""

DeriveGamemode("sandbox")

include("tf2/sh_core.lua")
include("tf2/sh_soundscripts.lua")

-- TF2's team numbers; GMod reserves only 0, 1001 and 1002.
function GM:CreateTeams()
	self.BaseClass.CreateTeams(self)
	team.SetUp(TF2.TEAM_RED, "RED", TF2.TeamColor[TF2.TEAM_RED], false)
	team.SetUp(TF2.TEAM_BLUE, "BLU", TF2.TeamColor[TF2.TEAM_BLUE], false)
end

function GM:StartCommand(ply, cmd)
	self.BaseClass.StartCommand(self, ply, cmd)
	if TF2.Active() then TF2.RestrictCommand(ply, cmd) end
end
