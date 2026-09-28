-- lib_rounds: team_round_timer output arming (CalculateOutputMessages), the
-- one-output-per-think chains of RoundTimerThink / RoundTimerSetupThink and
-- the client's ClientThink, and CTeamRoundTimer::SetActiveTimer.
local T = dofile("tests/harness.lua")
local R = T.lib("rounds")

T.test("outputs are armed for every mark the time still reaches", function()
	local armed = R.ArmTimerOutputs(70)
	T.eq(armed.finished, true)
	T.eq(armed[300], false)
	T.eq(armed[60], true)
	T.eq(armed[1], true)
end)

T.test("a timer at zero arms nothing", function()
	local armed = R.ArmTimerOutputs(0)
	T.eq(armed.finished, false)
	T.eq(armed[1], false)
end)

T.test("the normal chain fires the highest crossed mark first", function()
	local armed = R.ArmTimerOutputs(400)
	T.eq(R.NextTimerOutput(armed, 250, false), 300)
	armed[300] = false
	T.eq(R.NextTimerOutput(armed, 250, false), nil)
	T.eq(R.NextTimerOutput(armed, 239, false), 240)
end)

T.test("finishing comes before any remaining mark", function()
	local armed = R.ArmTimerOutputs(3)
	T.eq(R.NextTimerOutput(armed, 0, false), "finished")
	armed.finished = false
	T.eq(R.NextTimerOutput(armed, 0, false), 3)
end)

T.test("the setup chain has no minute marks above one", function()
	local armed = R.ArmTimerOutputs(400)
	T.eq(R.NextTimerOutput(armed, 100, true), nil)
	T.eq(R.NextTimerOutput(armed, 60, true), 60)
end)

T.test("the output name of each mark", function()
	T.eq(R.TimerOutputName(300), "On5MinRemain")
	T.eq(R.TimerOutputName(30), "On30SecRemain")
	T.eq(R.TimerOutputName(1), "On1SecRemain")
end)

-- Client countdown (CalculateOutputMessages with the client's 2 s allowance)

T.test("the client arms with two seconds of slack above ten seconds", function()
	local armed = R.ArmClientWarnings(59)
	T.eq(armed[60], true)
	T.eq(armed[30], true)
	armed = R.ArmClientWarnings(57)
	T.eq(armed[60], false)
end)

T.test("the client does not pad short times", function()
	local armed = R.ArmClientWarnings(9)
	T.eq(armed[10], false)
	T.eq(armed[5], true)
end)

T.test("client warnings speak a second early, one per think", function()
	local armed = R.ArmClientWarnings(120)
	T.eq(R.NextClientWarning(armed, 61), 60)
	armed[60] = false
	T.eq(R.NextClientWarning(armed, 61), nil)
	T.eq(R.NextClientWarning(armed, 6), 30)
end)

-- SetActiveTimer

local function Timers(list)
	local timers = {}
	for i, t in ipairs(list) do timers[i] = { enabled = t[1], show = t[2] } end
	return timers
end

T.test("a newly active timer hides the other shown timers", function()
	local chosen, hide = R.ChooseActiveTimer(Timers({ { true, true }, { true, true }, { false, true } }), 2)
	T.eq(chosen, 2)
	T.eq(#hide, 1)
	T.eq(hide[1], 1)
end)

T.test("with none newly active the first enabled shown timer is chosen", function()
	local chosen, hide = R.ChooseActiveTimer(Timers({ { false, true }, { true, false }, { true, true } }), nil)
	T.eq(chosen, 3)
	T.eq(#hide, 0)
end)

T.test("no candidate chooses nothing", function()
	local chosen = R.ChooseActiveTimer(Timers({ { false, true } }), nil)
	T.eq(chosen, nil)
end)

T.test("the timer after setup keeps its remaining time unless reset_time", function()
	T.eq(R.TimeAfterSetup(false, true, 120, 300), 120)
	T.eq(R.TimeAfterSetup(true, true, 120, 300), 300)
	T.eq(R.TimeAfterSetup(false, false, 40, 300), 300)
end)

T.test("added time is capped by the maximum length", function()
	T.eq(R.ClampAdd(500, 200, 600), 100)
	T.eq(R.ClampAdd(100, 200, 600), 200)
	T.eq(R.ClampAdd(500, 200, 0), 200)
end)

T.finish()
