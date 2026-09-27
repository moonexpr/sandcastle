-- team_train_watcher: tracks the payload cart along its path_track chain and,
-- with handle_train_movement, drives it: speed from the number of pushers,
-- uphill/downhill rules from the path nodes, and receding after a spell with
-- nobody pushing (CTeamTrainWatcher, team_train_watcher.cpp).
ENT.Type = "point"
ENT.Base = "base_point"

local recede_time = CreateConVar("tf_escort_recede_time", "30", 0, "Seconds without pushers before the cart recedes.", 0)

local HILL_NONE, HILL_UP, HILL_DOWN = 0, 1, 2
local SF_PATH_UPHILL, SF_PATH_DOWNHILL = 0x20, 0x40
local RECEDE_SPEED = -0.1
-- Fraction of the train's top speed for 1, 2 and 3+ pushers.
local PUSH_SPEED = { 0.55, 0.77, 1.0 }

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
	self.enabled = self:Key("startdisabled", "0") ~= "1"
	self.handleMovement = self:Key("handle_train_movement", "0") == "1"
	self.canRecede = self:Key("train_can_recede", "1") == "1"
	self.recedeTime = tonumber(self:Key("train_recede_time", 0)) or 0
	self.forwardModifier = tonumber(self:Key("speed_forward_modifier", 1)) or 1
	self.numCappers = 0
	self.currentSpeed = 0
	self.hill = HILL_NONE
	self.receding = false
	self.waitingToRecede = false
	self.recedeAt = 0
	self.ready = false
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

local function HillType(node)
	local flags = tonumber(TF2.KeyValues(node).spawnflags) or 0
	if bit.band(flags, SF_PATH_UPHILL) ~= 0 then return HILL_UP end
	if bit.band(flags, SF_PATH_DOWNHILL) ~= 0 then return HILL_DOWN end
	return HILL_NONE
end

-- Walk the path from start_node, measuring it, and listen to every node's OnPass.
function ENT:BuildPath()
	self.train = TF2.FindByName(self:Key("train"))
	local start = TF2.FindByName(self:Key("start_node"))
	local goal = TF2.FindByName(self:Key("goal_node"))
	self.nodes, self.nodeIndex, self.distance = {}, {}, {}
	local node, total = start, 0
	while IsValid(node) and not self.nodeIndex[node] do
		local i = #self.nodes + 1
		if i > 1 then total = total + node:GetPos():Distance(self.nodes[i - 1]:GetPos()) end
		self.nodes[i], self.nodeIndex[node], self.distance[i] = node, i, total
		node:Fire("AddOutput", "OnPass " .. self:GetName() .. ":TF2PathPassed::0:-1")
		if node == goal then break end
		node = TF2.FindByName(TF2.KeyValues(node).target)
	end
	self.length = math.max(total, 1)

	self.checkpoints = {}
	for n = 1, 8 do
		local track = TF2.FindByName(self:Key("linked_pathtrack_" .. n))
		local cp = self:Key("linked_cp_" .. n)
		if IsValid(track) and self.nodeIndex[track] then
			self.checkpoints[#self.checkpoints + 1] = { fraction = self.distance[self.nodeIndex[track]] / self.length, cp = cp }
		end
	end
	local fractions = {}
	for _, c in ipairs(self.checkpoints) do fractions[#fractions + 1] = string.format("%.4f", c.fraction) end
	SetGlobal2String("tf2.cart.cps", table.concat(fractions, ","))
	SetGlobal2Bool("tf2.cart.show", self.enabled)
	self:SetSpeedForwardModifier(self.forwardModifier)
	self.ready = true
end

function ENT:IsWatching(train)
	return IsValid(train) and train == self.train
end

function ENT:TimerMayExpire()
	return not (self.enabled and self.numCappers > 0)
end

-- Distance travelled along the path, by projecting the train onto the nearest segment.
function ENT:Progress()
	if not IsValid(self.train) or #self.nodes < 2 then return 0 end
	local pos = self.train:GetPos()
	local best, bestDist = 0, math.huge
	for i = 2, #self.nodes do
		local a, b = self.nodes[i - 1]:GetPos(), self.nodes[i]:GetPos()
		local ab = b - a
		local t = math.Clamp((pos - a):Dot(ab) / math.max(ab:LengthSqr(), 1), 0, 1)
		local d = pos:DistToSqr(a + ab * t)
		if d < bestDist then
			bestDist = d
			best = self.distance[i - 1] + ab:Length() * t
		end
	end
	return best / self.length
end

function ENT:SetTrainSpeed(speed)
	if not IsValid(self.train) then return end
	self.train:Fire("SetSpeedDirAccel", tostring(speed))
end

function ENT:SetSpeedForwardModifier(modifier)
	self.forwardModifier = math.Clamp(math.abs(modifier), 0, 1)
	if IsValid(self.train) and self.handleMovement then
		self.train:Fire("SetSpeedForwardModifier", tostring(self.forwardModifier))
	end
end

-- HandleTrainMovement
function ENT:HandleTrainMovement(startReceding)
	if not self.enabled or not self.handleMovement or not IsValid(self.train) then return end
	local speed = 0
	if startReceding then
		speed = RECEDE_SPEED
		self.receding = true
	elseif self.numCappers > 0 then
		self.receding = false
		speed = self.hill == HILL_DOWN and 1.0 or PUSH_SPEED[math.min(self.numCappers, 3)]
	elseif self.numCappers == -1 then
		if self.hill == HILL_DOWN then speed = 1.0 end
	elseif self.currentSpeed > 0 then
		if self.hill == HILL_DOWN then speed = 1.0 end
	elseif self.hill == HILL_UP then
		speed = -1.0
	elseif self.receding then
		speed = RECEDE_SPEED
	end
	if speed ~= self.currentSpeed then
		if speed >= 0 then self.receding = false end
		self.currentSpeed = speed
		self:SetTrainSpeed(speed)
		self:Sparks(speed < 0)
	end
end

function ENT:Sparks(on)
	local name = self:Key("env_spark_name")
	if not name then return end
	for _, spark in ipairs(ents.FindByName(name)) do
		spark:Fire(on and "StartSpark" or "StopSpark")
	end
end

-- InternalSetNumTrainCappers
function ENT:SetNumTrainCappers(num, area)
	if not self.enabled then return end
	self.numCappers = num
	local blocked = IsValid(area) and area:IsBlocked()
	if num <= 0 and not blocked and self.canRecede then
		if not self.waitingToRecede then
			self.waitingToRecede = true
			local wait = self.recedeTime > 0 and self.recedeTime or recede_time:GetFloat()
			self.recedeAt = CurTime() + wait
		end
	else
		self.waitingToRecede = false
		self.recedeAt = 0
	end
	self:HandleTrainMovement()
end

-- The path_track_passed event: follow hill segments as the cart crosses nodes.
function ENT:PathPassed(node)
	local i = self.nodeIndex[node]
	if not i then return end
	if self.receding then
		local prev = self.nodes[i - 1]
		if IsValid(prev) and TF2.KeyValues(prev).tf2disabled then return end
	end
	local hill = HillType(node)
	local update = hill ~= self.hill
	if not update and self.hill ~= HILL_NONE then
		local nextNode = self.currentSpeed < 0 and self.nodes[i - 1] or self.nodes[i + 1]
		if IsValid(nextNode) and HillType(nextNode) ~= self.hill then
			update = true
			hill = HILL_NONE
		end
	end
	if update then
		self.hill = hill
		self:HandleTrainMovement()
	end
end

function ENT:Think()
	self:NextThink(CurTime() + 0.1)
	if not self.ready then self:BuildPath() end
	if not self.enabled then return true end

	local overtime = GetGlobal2Bool("tf2.overtime", false)
	if self.waitingToRecede and CurTime() >= self.recedeAt then
		self.waitingToRecede = false
		if not overtime then
			self:TriggerOutput("OnTrainStartRecede", self)
			self:HandleTrainMovement(true)
		end
	end

	SetGlobal2Float("tf2.cart.progress", self:Progress())
	SetGlobal2Int("tf2.cart.cappers", self.numCappers)
	SetGlobal2Float("tf2.cart.recedeAt", self.waitingToRecede and self.recedeAt or 0)
	local owners = {}
	for _, c in ipairs(self.checkpoints) do
		local cp = TF2.FindByName(c.cp)
		owners[#owners + 1] = IsValid(cp) and TF2.CapTeam(cp) or 0
	end
	SetGlobal2String("tf2.cart.owners", table.concat(owners, ","))
	return true
end

local INPUTS = {
	tf2pathpassed = function(self, value, caller) self:PathPassed(caller) end,
	setnumtraincappers = function(self, value, caller) self:SetNumTrainCappers(tonumber(value) or 0, caller) end,
	setspeedforwardmodifier = function(self, value) self:SetSpeedForwardModifier(tonumber(value) or 1) end,
	settraincanrecede = function(self, value) self.canRecede = tostring(value) ~= "0" and tostring(value) ~= "false" end,
	settrainrecedetime = function(self, value) self.recedeTime = tonumber(value) or 0 end,
	settrainrecedetimeandupdate = function(self, value)
		self.recedeTime = tonumber(value) or 0
		if self.waitingToRecede then
			self.recedeAt = CurTime() + (self.recedeTime > 0 and self.recedeTime or recede_time:GetFloat())
		end
	end,
	enable = function(self) self.enabled = true SetGlobal2Bool("tf2.cart.show", true) end,
	disable = function(self)
		self.enabled = false
		SetGlobal2Bool("tf2.cart.show", false)
		self.currentSpeed = 0
		self:SetTrainSpeed(0)
	end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value, caller)
	return true
end
