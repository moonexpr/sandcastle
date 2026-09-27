-- func_respawnroomvisualizer: the forcefield over a spawn room's doors. It
-- takes its func_respawnroom's team and active state, blocks and shows itself
-- only to that team's enemies, and opens for everyone once a round is won
-- (C_FuncRespawnRoomVisualizer::ShouldCollide).
-- It is an "anim" entity rather than "brush" so clients can draw it.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "RoomTeam")
	self:NetworkVar("Bool", 0, "RoomActive")
	self:NetworkVar("Bool", 1, "Enabled")
	self:NetworkVar("Bool", 2, "SolidToEnemies")
end

function ENT:Blocks(ent)
	if not (IsValid(ent) and ent:IsPlayer()) then return false end
	if not (self:GetEnabled() and self:GetRoomActive() and self:GetSolidToEnemies()) then return false end
	if TF2.Active() and TF2.State() == TF2.STATE.TEAM_WIN then return false end
	local team = self:GetRoomTeam()
	return team ~= TF2.TEAM_UNASSIGNED and TF2.TeamOf(ent) ~= team
end

hook.Add("ShouldCollide", "tf2.respawnroomvisualizer", function(a, b)
	if a:GetClass() == "func_respawnroomvisualizer" then return a:Blocks(b) end
	if b:GetClass() == "func_respawnroomvisualizer" then return b:Blocks(a) end
end)

if CLIENT then
	function ENT:Draw()
		if self:Blocks(LocalPlayer()) then self:DrawModel() end
	end
	ENT.DrawTranslucent = ENT.Draw
	return
end

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if k == "model" then
		self.brushModel = value
	elseif k == "respawnroomname" then
		self.roomName = value
	elseif k == "solid_to_enemies" then
		self.solidToEnemies = value ~= "0"
	elseif k == "startdisabled" then
		self.startDisabled = value == "1"
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	if self.brushModel then self:SetModel(self.brushModel) end
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_BSP)
	self:SetCustomCollisionCheck(true)
	self:SetEnabled(not self.startDisabled)
	self:SetSolidToEnemies(self.solidToEnemies ~= false)
	self:SetRoomActive(true)
	self:SyncRoom()
end

-- The room decides team and activity; mirror it for clients and collisions.
function ENT:SyncRoom()
	local room = TF2.FindByName(self.roomName)
	if IsValid(room) and room.team then
		self:SetRoomTeam(room.team)
		self:SetRoomActive(room:IsActive())
	end
end

function ENT:Think()
	self:SyncRoom()
	self:NextThink(CurTime() + 0.2)
	return true
end

function ENT:AcceptInput(name, activator, caller, value)
	local input = string.lower(name)
	if input == "enable" then
		self:SetEnabled(true)
	elseif input == "disable" then
		self:SetEnabled(false)
	elseif input == "setsolid" then
		self:SetSolidToEnemies(tostring(value) ~= "0" and tostring(value) ~= "false")
	elseif input == "roundactivate" then
		self:SyncRoom()
	else
		return false
	end
	return true
end
