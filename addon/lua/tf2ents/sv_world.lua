-- Server-side world helpers shared by the TF2 entities.

util.AddNetworkString("tf2.announce")
util.AddNetworkString("tf2.ready")

-- Sent by the client once it has finished loading (InitPostEntity).
net.Receive("tf2.ready", function(_, ply)
	ply.tf2Ready = true
end)

-- Keyvalues of engine entities we read but do not implement. GMod exposes no
-- getter for a path_track's next node or a teamspawn's team, so they are
-- recorded as the map sets them.
TF2.KV = TF2.KV or setmetatable({}, { __mode = "k" })

local RECORDED = {
	path_track = true,
	info_player_teamspawn = true,
	team_control_point = true,
}

-- Outputs are kept in map order in kv.outputs, since an output key may repeat.
hook.Add("EntityKeyValue", "tf2.record", function(ent, key, value)
	if not RECORDED[ent:GetClass()] then return end
	local kv = TF2.KV[ent]
	if not kv then
		kv = { outputs = {} }
		TF2.KV[ent] = kv
	end
	if string.sub(key, 1, 2) == "On" then
		kv.outputs[#kv.outputs + 1] = TF2.ParseOutput(key, value)
	else
		kv[string.lower(key)] = value
	end
end)

function TF2.KeyValues(ent)
	return TF2.KV[ent] or { outputs = {} }
end

function TF2.FindByName(name)
	if not name or name == "" then return NULL end
	return ents.FindByName(name)[1] or NULL
end

-- An output connection as Hammer writes it: target,input,param,delay,times
-- (newer compilers separate the fields with ESC instead of commas).
function TF2.ParseOutput(name, value)
	local sep = string.find(value, "\27", 1, true) and "\27" or ","
	local f = string.Explode(sep, value)
	return {
		name = name,
		target = f[1] or "",
		input = f[2] or "",
		param = f[3] or "",
		delay = tonumber(f[4]) or 0,
		times = tonumber(f[5]) or -1,
		fired = 0,
	}
end

local function OutputTargets(o, caller, activator)
	local t = string.lower(o.target)
	if t == "!self" or t == "!caller" then return { caller } end
	if t == "!activator" then return { activator } end
	if t == "!player" then return { player.GetAll()[1] } end
	return ents.FindByName(o.target)
end

-- Fire the named output of an engine entity whose outputs we recorded.
function TF2.FireOutput(caller, name, activator)
	for _, o in ipairs(TF2.KeyValues(caller).outputs) do
		if o.name == name and (o.times < 0 or o.fired < o.times) then
			o.fired = o.fired + 1
			for _, target in ipairs(OutputTargets(o, caller, activator)) do
				if IsValid(target) then
					target:Fire(o.input, o.param, o.delay, activator, caller)
				end
			end
		end
	end
end

function TF2.Announce(text, team)
	net.Start("tf2.announce")
	net.WriteString(text)
	net.WriteUInt(team or 0, 2)
	net.Broadcast()
end

function TF2.IsAliveInGame(ply)
	return IsValid(ply) and ply:IsPlayer() and ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE
end

-- Players whose hull overlaps the entity's bounds, tested in the entity's own
-- space so a volume parented to the moving cart turns with it. Brush volumes
-- are treated as their bounding box.
local HULL = Vector(16, 16, 36)
function TF2.PlayersInside(ent)
	local inside = {}
	if not IsValid(ent) then return inside end
	local mins, maxs = ent:OBBMins() - HULL, ent:OBBMaxs() + HULL
	for _, ply in ipairs(player.GetAll()) do
		if TF2.IsAliveInGame(ply) then
			local p = ent:WorldToLocal(ply:WorldSpaceCenter())
			if p:WithinAABox(mins, maxs) then
				inside[#inside + 1] = ply
			end
		end
	end
	return inside
end

-- A weapon's ammo ceiling: GMod's own per-type maximum when it sets one,
-- otherwise four clips (GMod reports 9999 for most types).
local function AmmoCeiling(wep, ammoType)
	local max = game.GetAmmoMax(ammoType)
	if max > 0 and max < 9999 then return max end
	return math.max(wep:GetMaxClip1(), 10) * 4
end

-- Refill every weapon's primary reserve by a fraction of its ceiling.
-- Returns whether anything was given.
function TF2.GiveAmmoFraction(ply, fraction)
	local gave = false
	for _, wep in ipairs(ply:GetWeapons()) do
		local ammoType = wep:GetPrimaryAmmoType()
		if ammoType >= 0 then
			local ceiling = AmmoCeiling(wep, ammoType)
			local have = ply:GetAmmoCount(ammoType)
			if have < ceiling then
				ply:SetAmmo(math.min(ceiling, have + math.ceil(ceiling * fraction)), ammoType)
				gave = true
			end
		end
	end
	return gave
end

function TF2.HealFraction(ply, fraction)
	local max = ply:GetMaxHealth()
	if ply:Health() >= max then return false end
	ply:SetHealth(math.min(max, ply:Health() + math.ceil(max * fraction)))
	ply:Extinguish()
	return true
end

-- info_player_teamspawn is an engine entity in GMod that ignores Enable,
-- Disable and SetTeam, so those inputs update the recorded keyvalues instead.
hook.Add("AcceptInput", "tf2.teamspawn", function(ent, input, activator, caller, value)
	if ent:GetClass() ~= "info_player_teamspawn" then return end
	local kv = TF2.KV[ent]
	if not kv then return end
	input = string.lower(input)
	if input == "enable" then
		kv.startdisabled = "0"
		return true
	elseif input == "disable" then
		kv.startdisabled = "1"
		return true
	elseif input == "setteam" then
		kv.teamnum = tostring(value)
		return true
	end
end)

-- path_track handles its own Enable/DisablePath; the train watcher only needs
-- to know which nodes are disabled, so note it and let the input through.
hook.Add("AcceptInput", "tf2.pathtrack", function(ent, input)
	if ent:GetClass() ~= "path_track" then return end
	local kv = TF2.KV[ent]
	if not kv then return end
	input = string.lower(input)
	if input == "disablepath" then
		kv.tf2disabled = true
	elseif input == "enablepath" then
		kv.tf2disabled = nil
	elseif input == "togglepath" then
		kv.tf2disabled = not kv.tf2disabled or nil
	end
end)

-- Enabled spawn points of a team. Points marked MatchSummary stand in the
-- end-of-match podium room and are only used for that screen in TF2.
function TF2.SpawnPoints(team)
	local points = {}
	for _, ent in ipairs(ents.FindByClass("info_player_teamspawn")) do
		local kv = TF2.KeyValues(ent)
		if kv.startdisabled ~= "1" and kv.matchsummary ~= "1" and tonumber(kv.teamnum) == team then
			points[#points + 1] = ent
		end
	end
	return points
end

local function Occupied(spot)
	local pos = spot:GetPos()
	for _, ent in ipairs(ents.FindInBox(pos + Vector(-16, -16, 0), pos + Vector(16, 16, 72))) do
		if ent:IsPlayer() and ent:Alive() then return true end
	end
	return false
end

hook.Add("PlayerSelectSpawn", "tf2.teamspawn", function(ply)
	if not TF2.Active() then return end
	if TF2.TeamOf(ply) == TF2.TEAM_UNASSIGNED then ply:SetTeam(TF2.TEAM_BLUE) end
	local points = TF2.SpawnPoints(TF2.TeamOf(ply))
	if #points == 0 then return end
	local start = math.random(#points)
	for i = 0, #points - 1 do
		local spot = points[(start + i - 1) % #points + 1]
		if not Occupied(spot) then return spot end
	end
	return points[start]
end)

-- Until there is a team picker, anyone without a TF2 team joins BLU so they
-- can push the cart. Other addons set teams in their own spawn hooks (one puts
-- players on a "Runner" team), so this runs a tick later, after them.
local function AssignDefaultTeam(ply)
	timer.Simple(0, function()
		if IsValid(ply) and TF2.Active() and TF2.TeamOf(ply) == TF2.TEAM_UNASSIGNED then
			ply:SetTeam(TF2.TEAM_BLUE)
		end
	end)
end
hook.Add("PlayerInitialSpawn", "tf2.defaultteam", AssignDefaultTeam)
hook.Add("PlayerSpawn", "tf2.defaultteam", AssignDefaultTeam)

-- Respawning belongs to tf_gamerules' respawn waves while it is running.
hook.Add("PlayerDeathThink", "tf2.respawnwaves", function(ply)
	if TF2.Active() then return false end
end)

local function NoteDeath(ply)
	if IsValid(TF2.Rules) then TF2.Rules:OnPlayerDeath(ply) end
end
hook.Add("PostPlayerDeath", "tf2.respawnwaves", NoteDeath)
