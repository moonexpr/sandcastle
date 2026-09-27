-- team_control_point: a capturable point. Its owner changes through SetOwner or
-- through a trigger_capture_area; the master then checks for a round win.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.RenderGroup = RENDERGROUP_BOTH

-- team_control_point.h spawnflags
local SF_HIDE_MODEL = 2
local SF_HIDE_SHADOW = 4
local SF_NO_CAP_SOUNDS = 8

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "CapTeam")
	self:NetworkVar("Int", 1, "PointIndex")
	self:NetworkVar("String", 0, "PointName")
end

if CLIENT then
	function ENT:Draw()
		self:DrawModel()
	end
	return
end

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	self.tf2kv = self.tf2kv or {}
	self.tf2kv[k] = value
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Key(name, default)
	local v = (self.tf2kv or {})[name]
	if v == nil or v == "" then return default end
	return v
end

function ENT:Initialize()
	self.flags = tonumber(self:Key("spawnflags", 0)) or 0
	self:SetPointIndex(tonumber(self:Key("point_index", 0)) or 0)
	self:SetPointName(self:Key("point_printname", self:GetName()))
	self.locked = self:Key("point_start_locked", "0") == "1"
	self:SetCapTeam(tonumber(self:Key("point_default_owner", 0)) or 0)
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_NONE)
	self:ApplyTeamModel()
	if bit.band(self.flags, SF_HIDE_MODEL) ~= 0 then self:SetNoDraw(true) end
	if bit.band(self.flags, SF_HIDE_SHADOW) ~= 0 then self:DrawShadow(false) end
	hook.Add("TF2RoundActive", self, self.OnRoundActive)
end

-- CTeamControlPoint::SetModel: per-team model, bodygroup 0 = team, skin by team.
function ENT:ApplyTeamModel()
	local team = self:GetCapTeam()
	local model = self:Key("team_model_" .. team, "models/effects/cappoint_hologram.mdl")
	if util.IsValidModel(model) then self:SetModel(model) end
	self:SetBodygroup(0, team)
	self:SetSkin(team == TF2.TEAM_UNASSIGNED and 2 or team - 2)
end

function ENT:OnRoundActive()
	local team = self:GetCapTeam()
	if team == TF2.TEAM_RED then self:TriggerOutput("OnRoundStartOwnedByTeam1", self) end
	if team == TF2.TEAM_BLUE then self:TriggerOutput("OnRoundStartOwnedByTeam2", self) end
end

-- The previous points a team must own before it may capture this one
-- (team_previouspoint_<team>_<n>).
function ENT:TeamCanCapture(team)
	if self.locked or team == self:GetCapTeam() then return false end
	for n = 0, 2 do
		local prev = TF2.FindByName(self:Key("team_previouspoint_" .. team .. "_" .. n))
		if IsValid(prev) and prev:GetCapTeam() ~= team then return false end
	end
	return true
end

function ENT:SetOwnerTeam(team, activator)
	local old = self:GetCapTeam()
	self:SetCapTeam(team)
	self:ApplyTeamModel()
	if team == TF2.TEAM_UNASSIGNED then
		self:TriggerOutput("OnCapReset", activator or self)
	elseif team == TF2.TEAM_RED then
		self:TriggerOutput("OnCapTeam1", activator or self)
		self:TriggerOutput("OnOwnerChangedToTeam1", activator or self)
	elseif team == TF2.TEAM_BLUE then
		self:TriggerOutput("OnCapTeam2", activator or self)
		self:TriggerOutput("OnOwnerChangedToTeam2", activator or self)
	end
	if team ~= old and team ~= TF2.TEAM_UNASSIGNED then
		if bit.band(self.flags, SF_NO_CAP_SOUNDS) == 0 then
			local sound = self:Key("team_capsound_" .. team)
			if sound then self:EmitSound(sound) end
		end
		TF2.Announce(TF2.TeamName[team] .. " captured " .. self:GetPointName(), team)
	end
	hook.Run("TF2PointCaptured", self, team)
end

local INPUTS = {
	setowner = function(self, value, activator) self:SetOwnerTeam(tonumber(value) or 0, activator) end,
	setlocked = function(self, value)
		local locked = tonumber(value) == 1
		if self.locked and not locked then self:TriggerOutput("OnUnlocked", self) end
		self.locked = locked
	end,
	setunlocktime = function(self, value)
		timer.Simple(tonumber(value) or 0, function()
			if IsValid(self) and self.locked then
				self.locked = false
				self:TriggerOutput("OnUnlocked", self)
			end
		end)
	end,
	hidemodel = function(self) self:SetNoDraw(true) end,
	showmodel = function(self) self:SetNoDraw(false) end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value, activator)
	return true
end
