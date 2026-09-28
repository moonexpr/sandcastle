-- trigger_add_tf_player_condition (CTriggerAddTFPlayerCondition): a player
-- who enters gets the condition for duration seconds; with duration -1 it
-- lasts until they leave. See sv_teams_conditions.lua for which conditions
-- have an effect in GMod.
ENT.Type = "brush"
ENT.Base = "tf2_trigger_volume"

local PERMANENT = -1

function ENT:TriggerInit()
	self.condition = tonumber(self:Key("condition", -1)) or -1
	self.duration = tonumber(self:Key("duration", 0)) or 0
end

function ENT:PlayerStartTouch(ply)
	if not self:PassesTriggerFilters(ply) or self.condition < 0 then return end
	TF2.AddCondition(ply, self.condition, self.duration)
	self:TriggerOutput("OnStartTouch", ply)
end

function ENT:PlayerEndTouch(ply)
	self:TriggerOutput("OnEndTouch", ply)
	if self.duration ~= PERMANENT or not self.enabled then return end
	if not self:PassesTriggerFilters(ply) or self.condition < 0 then return end
	TF2.RemoveCondition(ply, self.condition)
end
