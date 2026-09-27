-- The round timer's announcer, as CTeamRoundTimer plays it on each client
-- (teamplay_round_timer.cpp): "Mission begins in 60 seconds" ... "1" through
-- setup, "Mission ends in ..." through normal time, and the siren when setup
-- gives way to the round. Only the timer shown in the HUD speaks, and only
-- while it runs with auto_countdown on.

-- ClientThink's thresholds: each warning fires once the time left drops to
-- its mark, at most one per think, in this order.
local WARNINGS = {
	{ at = 61, seconds = 60 },
	{ at = 31, seconds = 30 },
	{ at = 11, seconds = 10 },
	{ at = 6, seconds = 5 },
	{ at = 5, seconds = 4 },
	{ at = 4, seconds = 3 },
	{ at = 3, seconds = 2 },
	{ at = 2, seconds = 1 },
}

local SETUP_SOUND = {
	[60] = "Announcer.RoundBegins60Seconds", [30] = "Announcer.RoundBegins30Seconds",
	[10] = "Announcer.RoundBegins10Seconds", [5] = "Announcer.RoundBegins5Seconds",
	[4] = "Announcer.RoundBegins4Seconds", [3] = "Announcer.RoundBegins3Seconds",
	[2] = "Announcer.RoundBegins2Seconds", [1] = "Announcer.RoundBegins1Seconds",
}

local ROUND_SOUND = {
	[60] = "Announcer.RoundEnds60seconds", [30] = "Announcer.RoundEnds30seconds",
	[10] = "Announcer.RoundEnds10seconds", [5] = "Announcer.RoundEnds5seconds",
	[4] = "Announcer.RoundEnds4seconds", [3] = "Announcer.RoundEnds3seconds",
	[2] = "Announcer.RoundEnds2seconds", [1] = "Announcer.RoundEnds1seconds",
}

local ROUND_START_BELL = "Ambient.Siren"

local function Play(name)
	local ply = LocalPlayer()
	if IsValid(ply) then ply:EmitSound(name) end
end

net.Receive("tf2.sound", function()
	Play(net.ReadString())
end)

local serial, wasSetup
local pending = {}

-- CalculateOutputMessages: a warning is armed while there is at least that
-- much time left, recomputed whenever the timer's length changes.
local function Arm(left)
	pending = {}
	for _, w in ipairs(WARNINGS) do
		pending[w.seconds] = left >= w.seconds
	end
end

function TF2.AnnouncerThink()
	if not GetGlobal2Bool("tf2.timer.show", false) then return end
	local setup = GetGlobal2Bool("tf2.timer.setup", false)
	local paused = GetGlobal2Bool("tf2.timer.paused", true)
	local speaks = not paused and GetGlobal2Bool("tf2.timer.autocountdown", true)
	local left
	if paused then
		left = GetGlobal2Float("tf2.timer.left", 0)
	else
		left = GetGlobal2Float("tf2.timer.end", 0) - CurTime()
	end

	-- OnDataChanged: setup giving way to normal time rings the bell.
	if wasSetup == true and not setup and speaks then Play(ROUND_START_BELL) end
	wasSetup = setup

	local s = GetGlobal2Int("tf2.timer.serial", 0)
	if s ~= serial then
		serial = s
		Arm(left)
	end
	if paused then return end

	for _, w in ipairs(WARNINGS) do
		if left <= w.at and pending[w.seconds] then
			pending[w.seconds] = false
			if speaks then Play((setup and SETUP_SOUND or ROUND_SOUND)[w.seconds]) end
			return
		end
	end
end
