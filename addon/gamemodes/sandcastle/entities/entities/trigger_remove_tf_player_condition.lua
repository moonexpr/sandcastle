-- trigger_remove_tf_player_condition (CTriggerRemoveTFPlayerCondition): a
-- player who enters loses the condition, or every condition when it is -1
-- (TF_COND_INVALID).
ENT.Type = "brush"
ENT.Base = "tf2_trigger_volume"

function ENT:TriggerInit()
	self.condition = tonumber(self:Key("condition", -1)) or -1
end

function ENT:PlayerStartTouch(ply)
	if not self:PassesTriggerFilters(ply) then return end
	if self.condition < 0 then
		TF2.RemoveAllConditions(ply)
	else
		TF2.RemoveCondition(ply, self.condition)
	end
	self:TriggerOutput("OnStartTouch", ply)
end

function ENT:PlayerEndTouch(ply)
	self:TriggerOutput("OnEndTouch", ply)
end
