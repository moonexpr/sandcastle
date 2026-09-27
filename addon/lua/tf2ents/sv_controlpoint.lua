-- team_control_point. GMod's engine already has a class by this name, which
-- wins over a Lua entity of the same name, and it is inert: it shows its model
-- but keeps none of TF2's state. So the TF2 behaviour lives here, beside each
-- engine control point: its keyvalues and outputs are recorded as the map sets
-- them (sv_world.lua), its inputs are taken through AcceptInput, and its outputs
-- are fired from the recording.

-- team_control_point.h spawnflags
local SF_NO_CAP_SOUNDS = 8

local function State(ent)
	local kv = TF2.KeyValues(ent)
	if kv.owner == nil then
		kv.owner = tonumber(kv.point_default_owner) or TF2.TEAM_UNASSIGNED
		kv.locked = kv.point_start_locked == "1"
	end
	return kv
end

function TF2.CapTeam(ent)
	return State(ent).owner
end

function TF2.PointLocked(ent)
	return State(ent).locked
end

function TF2.PointIndex(ent)
	return tonumber(State(ent).point_index) or 0
end

-- CTeamControlPoint::InternalSetOwner
function TF2.SetPointOwner(ent, team, activator)
	local s = State(ent)
	local old = s.owner
	s.owner = team
	activator = activator or ent
	if team == TF2.TEAM_UNASSIGNED then
		TF2.FireOutput(ent, "OnCapReset", activator)
	elseif team == TF2.TEAM_RED then
		TF2.FireOutput(ent, "OnCapTeam1", activator)
		TF2.FireOutput(ent, "OnOwnerChangedToTeam1", activator)
	elseif team == TF2.TEAM_BLUE then
		TF2.FireOutput(ent, "OnCapTeam2", activator)
		TF2.FireOutput(ent, "OnOwnerChangedToTeam2", activator)
	end
	if team ~= old and team ~= TF2.TEAM_UNASSIGNED then
		local flags = tonumber(s.spawnflags) or 0
		local sound = s["team_capsound_" .. team]
		if sound and sound ~= "" and bit.band(flags, SF_NO_CAP_SOUNDS) == 0 then ent:EmitSound(sound) end
		TF2.Announce(TF2.TeamName[team] .. " captured point " .. TF2.PointIndex(ent), team)
	end
	hook.Run("TF2PointCaptured", ent, team)
end

local function Unlock(ent)
	local s = State(ent)
	if not s.locked then return end
	s.locked = false
	TF2.FireOutput(ent, "OnUnlocked", ent)
end

local INPUTS = {
	setowner = function(ent, value, activator) TF2.SetPointOwner(ent, tonumber(value) or 0, activator) end,
	setlocked = function(ent, value)
		if tonumber(value) == 1 then State(ent).locked = true else Unlock(ent) end
	end,
	setunlocktime = function(ent, value)
		timer.Simple(tonumber(value) or 0, function() if IsValid(ent) then Unlock(ent) end end)
	end,
	hidemodel = function(ent) ent:SetNoDraw(true) end,
	showmodel = function(ent) ent:SetNoDraw(false) end,
}

hook.Add("AcceptInput", "tf2.controlpoint", function(ent, input, activator, caller, value)
	if ent:GetClass() ~= "team_control_point" then return end
	local handler = INPUTS[string.lower(input)]
	if not handler then return end
	handler(ent, value, activator)
	return true
end)

hook.Add("TF2RoundActive", "tf2.controlpoint", function()
	for _, ent in ipairs(ents.FindByClass("team_control_point")) do
		local team = TF2.CapTeam(ent)
		if team == TF2.TEAM_RED then TF2.FireOutput(ent, "OnRoundStartOwnedByTeam1", ent) end
		if team == TF2.TEAM_BLUE then TF2.FireOutput(ent, "OnRoundStartOwnedByTeam2", ent) end
	end
end)
