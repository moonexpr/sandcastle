-- trigger_capture_area: the volume players stand in to capture its control
-- point. On payload maps it rides the cart, and area_time_to_cap is set so
-- high that the point is captured by the track (CaptureCurrentCP) instead; what
-- matters is the capper count it reports to the team_train_watcher.
ENT.Type = "brush"
ENT.Base = "base_brush"

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	self.tf2kv = self.tf2kv or {}
	self.tf2kv[k] = value
	if k == "model" then self.brushModel = value end
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Key(name, default)
	local v = (self.tf2kv or {})[name]
	if v == nil or v == "" then return default end
	return v
end

function ENT:Initialize()
	if self.brushModel then self:SetModel(self.brushModel) end
	self:SetSolid(SOLID_NONE)
	self:SetNoDraw(true)
	self.enabled = self:Key("startdisabled", "0") ~= "1"
	self.pointName = self:Key("area_cap_point")
	self.canCap = {
		[TF2.TEAM_RED] = self:Key("team_cancap_2", "1") == "1",
		[TF2.TEAM_BLUE] = self:Key("team_cancap_3", "1") == "1",
	}
	self.numCap = {
		[TF2.TEAM_RED] = tonumber(self:Key("team_numcap_2", 1)) or 1,
		[TF2.TEAM_BLUE] = tonumber(self:Key("team_numcap_3", 1)) or 1,
	}
	self.reported = 0
	self.cappingTeam = TF2.TEAM_UNASSIGNED
end

function ENT:Point()
	return TF2.FindByName(self.pointName)
end

function ENT:PointsMayBeCaptured()
	return self.enabled and (not IsValid(TF2.Rules) or TF2.Rules:PointsMayBeCaptured())
end

-- Which team is capturing, how many of them, and whether the other team blocks.
function ENT:Survey()
	local counts = { [TF2.TEAM_RED] = 0, [TF2.TEAM_BLUE] = 0 }
	for _, ply in ipairs(TF2.PlayersInside(self)) do
		local team = TF2.TeamOf(ply)
		if counts[team] then counts[team] = counts[team] + 1 end
	end
	local point = self:Point()
	local owner = IsValid(point) and point:GetCapTeam() or TF2.TEAM_UNASSIGNED
	local capping = TF2.TEAM_UNASSIGNED
	for team = TF2.TEAM_RED, TF2.TEAM_BLUE do
		if self.canCap[team] and team ~= owner and counts[team] >= self.numCap[team] then
			capping = team
		end
	end
	local blocked = capping ~= TF2.TEAM_UNASSIGNED and counts[TF2.EnemyOf(capping)] > 0
	return capping, counts[capping] or 0, blocked
end

-- The number the train watcher is told: cappers, 0 for none, -1 when blocked.
function ENT:Think()
	self:NextThink(CurTime() + 0.1)
	local capping, cappers, blocked = TF2.TEAM_UNASSIGNED, 0, false
	if self:PointsMayBeCaptured() then
		capping, cappers, blocked = self:Survey()
	end
	local report = blocked and -1 or cappers
	self.blocked = blocked

	if capping ~= self.cappingTeam then
		if self.cappingTeam ~= TF2.TEAM_UNASSIGNED then
			self:TriggerOutput("OnBreakCap", self)
			self:TriggerOutput(self.cappingTeam == TF2.TEAM_RED and "OnBreakTeam1" or "OnBreakTeam2", self)
		end
		if capping ~= TF2.TEAM_UNASSIGNED then
			self:TriggerOutput("OnStartCap", self)
			self:TriggerOutput(capping == TF2.TEAM_RED and "OnStartTeam1" or "OnStartTeam2", self)
		end
		self.cappingTeam = capping
	end

	if report ~= self.reported then
		self.reported = report
		self:TriggerOutput("OnNumCappersChanged", self, tostring(math.max(report, 0)))
		self:TriggerOutput("OnNumCappersChanged2", self, tostring(report))
		for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
			if watcher:IsWatching(self:GetParent()) then
				watcher:SetNumTrainCappers(report, self)
			end
		end
	end
	return true
end

function ENT:IsBlocked()
	return self.blocked == true
end

-- CaptureCurrentCP: the capping team, or else the first team that may cap and
-- does not own the point, takes it now.
function ENT:CaptureCurrentPoint(activator)
	local point = self:Point()
	if not IsValid(point) then return end
	local team = self.cappingTeam
	if team == TF2.TEAM_UNASSIGNED then
		for t = TF2.TEAM_BLUE, TF2.TEAM_RED, -1 do
			if self.canCap[t] and point:GetCapTeam() ~= t then team = t break end
		end
	end
	if team == TF2.TEAM_UNASSIGNED then return end
	self:TriggerOutput("OnEndCap", self)
	self:TriggerOutput(team == TF2.TEAM_RED and "OnCapTeam1" or "OnCapTeam2", self)
	point:SetOwnerTeam(team, activator)
end

local INPUTS = {
	setcontrolpoint = function(self, value) self.pointName = tostring(value) end,
	capturecurrentcp = function(self, value, activator) self:CaptureCurrentPoint(activator) end,
	setteamcancap = function(self, value)
		local team, can = string.match(tostring(value), "(%d+)%s+(%d+)")
		team = tonumber(team)
		if self.canCap[team] ~= nil then self.canCap[team] = can == "1" end
	end,
	enable = function(self) self.enabled = true end,
	disable = function(self) self.enabled = false end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value, activator)
	return true
end
