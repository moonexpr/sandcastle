-- foundation.rounds: the win panel's wording (CTFWinPanel::FireGameEvent) and the
-- lookup of TF2 localization tokens in tf_english.txt (UTF-16LE).
local T = dofile("tests/harness.lua")
local R = T.require("foundation.rounds")

local W = R.WINREASON

T.test("a full round win says the team wins", function()
	local p = R.WinPanel({ winner = 3, reason = W.ALL_POINTS_CAPTURED, fullRound = true, remaining = 0 })
	T.eq(p.title, "BLU TEAM WINS!")
	T.eq(p.reason, "BLU captured all control points")
	T.eq(p.details, nil)
end)

T.test("a mini-round win seizes the area and counts what is left", function()
	local p = R.WinPanel({ winner = 3, reason = W.ALL_POINTS_CAPTURED, fullRound = false, remaining = 2 })
	T.eq(p.title, "BLU TEAM SEIZES AREA")
	T.eq(p.details, "2 more areas to win")
	p = R.WinPanel({ winner = 3, reason = W.ALL_POINTS_CAPTURED, fullRound = false, remaining = 1 })
	T.eq(p.details, "1 more area to win")
end)

T.test("defending a mini-round until time runs out defends", function()
	local p = R.WinPanel({ winner = 2, reason = W.DEFEND_UNTIL_TIME_LIMIT, fullRound = false, remaining = 1 })
	T.eq(p.title, "RED TEAM DEFENDS!")
	T.eq(p.reason, "RED successfully defended until time ran out")
end)

T.test("a stalemate has everyone lose", function()
	local p = R.WinPanel({ winner = 0, reason = W.STALEMATE, fullRound = true, remaining = 0 })
	T.eq(p.title, "STALEMATE")
	T.eq(p.reason, "You're all losers")
end)

T.test("sudden death wins by killing everyone", function()
	local p = R.WinPanel({ winner = 2, reason = W.OPPONENTS_DEAD, fullRound = true, remaining = 0 })
	T.eq(p.reason, "RED killed all opponents during sudden death")
end)

T.test("sudden death explains why it started", function()
	local p = R.StalematePanel(R.STALEMATE.TIMER)
	T.eq(p.title, "SUDDEN DEATH!")
	T.eq(p.reason, "You've run out of time. Watch your back and finish 'em off. No more spawning.")
	T.eq(R.StalematePanel(R.STALEMATE.SERVER_TIMELIMIT).reason, "Map time limit reached. No more spawning, so make this count.")
end)

local function Utf16(s)
	return (string.gsub(s, ".", function(c) return c .. "\0" end))
end

local FILE = "\255\254" .. Utf16('"lang"\r\n{\r\n"Tokens"\r\n{\r\n'
	.. '"[english]Goldrush_blue_setup_goal"\t"old"\r\n'
	.. '"Goldrush_blue_setup_goal"\t\t"Move the cart!"\r\n'
	.. '"Other"\t"x"\r\n}\r\n}\r\n')

T.test("a token's text is read from the UTF-16 file", function()
	T.eq(R.Localize(FILE, "#Goldrush_blue_setup_goal"), "Move the cart!")
end)

T.test("token lookup ignores case, as VGUI's does", function()
	T.eq(R.Localize(FILE, "#goldrush_BLUE_setup_goal"), "Move the cart!")
end)

T.test("an unknown token is not found", function()
	T.eq(R.Localize(FILE, "#Missing"), nil)
end)

T.test("plain text needs no lookup", function()
	T.eq(R.Localize(FILE, "Push the cart"), "Push the cart")
end)

T.test("non-ASCII characters decode to UTF-8", function()
	local raw = "\255\254" .. Utf16('"K"\t"') .. "\233\0" .. Utf16('"\r\n')
	T.eq(R.Localize(raw, "#K"), "\195\169")
end)

T.finish()
