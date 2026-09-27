-- func_respawnroom: a team's spawn room. Its team and active state drive the
-- func_respawnroomvisualizer forcefields that name it.
ENT.Type = "brush"
ENT.Base = "tf2_brush_volume"

function ENT:VolumeInit()
	self.active = true
	self.originalTeam = self.team
	hook.Add("TF2RoundActive", self, self.RoundActivate)
end

function ENT:IsActive()
	return self.active and self.enabled
end

-- RoundActivate: a room placed with no team takes the team of an enabled
-- spawn point inside it (CFuncRespawnRoom::InputRoundActivate).
function ENT:RoundActivate()
	if self.originalTeam ~= TF2.TEAM_UNASSIGNED then return end
	local mins, maxs = self:OBBMins(), self:OBBMaxs()
	for team = TF2.TEAM_RED, TF2.TEAM_BLUE do
		for _, spawn in ipairs(TF2.SpawnPoints(team)) do
			if self:WorldToLocal(spawn:GetPos()):WithinAABox(mins, maxs) then
				self.team = team
				return
			end
		end
	end
end

ENT.Inputs = {
	setactive = function(self) self.active = true end,
	setinactive = function(self) self.active = false end,
	toggleactive = function(self) self.active = not self.active end,
	roundactivate = function(self) self:RoundActivate() end,
}
