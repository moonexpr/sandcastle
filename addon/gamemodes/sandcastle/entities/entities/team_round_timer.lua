-- team_round_timer: the round clock, with an optional setup phase first.
-- Under tf_gamerules it starts when the round goes active; without one it
-- starts at spawn unless start_paused is set.
ENT.Type = "point"
ENT.Base = "base_point"

-- Outputs fired as the normal (non-setup) time crosses each mark.
local REMAIN_OUTPUTS = {
	{ 300, "On5MinRemain" }, { 240, "On4MinRemain" }, { 180, "On3MinRemain" },
	{ 120, "On2MinRemain" }, { 60, "On1MinRemain" }, { 30, "On30SecRemain" },
	{ 10, "On10SecRemain" }, { 5, "On5SecRemain" }, { 4, "On4SecRemain" },
	{ 3, "On3SecRemain" }, { 2, "On2SecRemain" }, { 1, "On1SecRemain" },
}

local INT_KEYS = {
	timer_length = "timerLength",
	max_length = "maxLength",
	setup_length = "setupLength",
	start_paused = "startPaused",
	show_in_hud = "showInHud",
	auto_countdown = "autoCountdown",
	show_time_remaining = "showTimeRemaining",
	reset_time = "resetTime",
	startdisabled = "startDisabled",
}

function ENT:KeyValue(key, value)
	local field = INT_KEYS[string.lower(key)]
	if field then
		self[field] = tonumber(value) or 0
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	self.timerLength = self.timerLength or 600
	self.maxLength = self.maxLength or 0
	self.setupLength = self.setupLength or 0
	self.startPaused = self.startPaused or 1
	self.showInHud = self.showInHud or 1
	self.autoCountdown = self.autoCountdown or 1
	self.enabled = self.startDisabled ~= 1
	self.paused = true
	self.inSetup = false
	self.finished = false
	self.remaining = self.timerLength
	self:Publish()
	if TF2.Active() then
		hook.Add("TF2RoundActive", self, self.RoundStart)
	elseif self.startPaused == 0 then
		timer.Simple(0, function() if IsValid(self) then self:RoundStart() end end)
	end
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

function ENT:TimeRemaining()
	if self.paused then return self.remaining end
	return math.max(0, self.endTime - CurTime())
end

-- Every change to the timer's length bumps a serial, which is how clients know
-- to re-arm their countdown announcements (CalculateOutputMessages).
function ENT:SetRemaining(seconds)
	self.remaining = seconds
	self.endTime = CurTime() + seconds
	self.serial = (self.serial or 0) + 1
	self:Publish()
end

function ENT:Publish()
	if self.showInHud ~= 1 then return end
	SetGlobal2Bool("tf2.timer.show", self.enabled)
	SetGlobal2Bool("tf2.timer.paused", self.paused)
	SetGlobal2Float("tf2.timer.left", self:TimeRemaining())
	SetGlobal2Float("tf2.timer.end", CurTime() + self:TimeRemaining())
	SetGlobal2Bool("tf2.timer.setup", self.inSetup)
	SetGlobal2Bool("tf2.timer.autocountdown", self.autoCountdown ~= 0)
	SetGlobal2Int("tf2.timer.serial", self.serial or 0)
end

function ENT:RoundStart()
	self.finished = false
	self.lastRemaining = nil
	if self.setupLength > 0 then
		self.inSetup = true
		if IsValid(TF2.Rules) then TF2.Rules:SetInSetup(true) end
		self.paused = self.startPaused == 1
		self:SetRemaining(self.setupLength)
		self:TriggerOutput("OnSetupStart", self)
	else
		self.paused = self.startPaused == 1
		self:SetRemaining(self.timerLength)
		self:TriggerOutput("OnRoundStart", self)
	end
end

function ENT:EndSetup()
	self.inSetup = false
	if IsValid(TF2.Rules) then TF2.Rules:SetInSetup(false) end
	self:SetRemaining(self.timerLength)
	self.lastRemaining = nil
	self:TriggerOutput("OnSetupFinished", self)
	self:TriggerOutput("OnRoundStart", self)
end

-- A payload cart with pushers on it holds the clock at zero (overtime).
local function TimerMayExpire()
	for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
		if not watcher:TimerMayExpire() then return false end
	end
	return true
end

function ENT:Think()
	self:NextThink(CurTime() + 0.1)
	if self.paused or not self.enabled or self.finished then return true end

	local left = self:TimeRemaining()
	if not self.inSetup then
		local before = self.lastRemaining or math.huge
		for _, mark in ipairs(REMAIN_OUTPUTS) do
			if before > mark[1] and left <= mark[1] then
				self:TriggerOutput(mark[2], self)
			end
		end
		self.lastRemaining = left
	end

	if left <= 0 then
		if self.inSetup then
			self:EndSetup()
		elseif not TimerMayExpire() then
			SetGlobal2Bool("tf2.overtime", true)
		else
			SetGlobal2Bool("tf2.overtime", false)
			self.finished = true
			self.paused = true
			self.remaining = 0
			self:Publish()
			self:TriggerOutput("OnFinished", self)
		end
	end
	return true
end

-- The announcer credits the team the time was added for (AddTeamTime), and
-- says nothing once the round is decided (CTeamRoundTimer::AddTimerSeconds).
local function AnnounceTimeAdded(team)
	if IsValid(TF2.Rules) and (TF2.Rules:StateGet() == TF2.STATE.TEAM_WIN or TF2.Rules:StateGet() == TF2.STATE.STALEMATE) then return end
	if team == TF2.TEAM_RED or team == TF2.TEAM_BLUE then
		TF2.BroadcastSound(team, "Announcer.TimeAwardedForTeam")
		TF2.BroadcastSound(TF2.EnemyOf(team), "Announcer.TimeAddedForEnemy")
	else
		TF2.BroadcastSound(TF2.TEAM_UNASSIGNED, "Announcer.TimeAdded")
	end
end

function ENT:AddTime(seconds, team)
	local left = self:TimeRemaining() + seconds
	if self.maxLength > 0 and not self.inSetup then
		left = math.min(left, self.maxLength)
	end
	if self.paused then self.remaining = left end
	self:SetRemaining(left)
	if seconds > 0 and self.showInHud == 1 then
		TF2.Announce(string.format("+%d:%02d", math.floor(seconds / 60), seconds % 60), 0)
		AnnounceTimeAdded(team)
	end
end

local INPUTS = {
	addteamtime = function(self, value)
		local team, seconds = string.match(tostring(value), "(%d+)%s+(%-?%d+)")
		self:AddTime(tonumber(seconds) or 0, tonumber(team))
	end,
	addtime = function(self, value) self:AddTime(tonumber(value) or 0) end,
	settime = function(self, value) self:SetRemaining(tonumber(value) or 0) end,
	setmaxtime = function(self, value) self.maxLength = tonumber(value) or 0 end,
	setsetuptime = function(self, value) self.setupLength = tonumber(value) or 0 end,
	pause = function(self)
		self.remaining = self:TimeRemaining()
		self.paused = true
		self:Publish()
	end,
	resume = function(self)
		self.paused = false
		self:SetRemaining(self.remaining)
	end,
	restart = function(self) self:RoundStart() end,
	enable = function(self) self.enabled = true self:Publish() end,
	disable = function(self) self.enabled = false self:Publish() end,
	showinhud = function(self, value) self.showInHud = tonumber(value) or 0 self:Publish() end,
	autocountdown = function(self, value) self.autoCountdown = tonumber(value) or 0 self:Publish() end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end
