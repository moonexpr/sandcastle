-- trigger_remove_tf_player_condition (CTriggerRemoveTFPlayerCondition): a
-- player who enters loses the condition, or every condition when it is -1
-- (TF_COND_INVALID).
ENT.Type = "brush"
ENT.Base = "wetsand_trigger_volume"

local INVALID = WETSAND.PlayerRules.COND.INVALID

function ENT:TriggerInit()
	self.condition = tonumber(self:Key("condition", INVALID)) or INVALID
end

function ENT:PlayerStartTouch(ply)
	if not self:PassesTriggerFilters(ply) then return end
	if self.condition == INVALID then
		WETSAND.RemoveAllConditions(ply)
	else
		WETSAND.RemoveCondition(ply, self.condition)
	end
	self:TriggerOutput("OnStartTouch", ply)
end

function ENT:PlayerEndTouch(ply)
	self:TriggerOutput("OnEndTouch", ply)
end
