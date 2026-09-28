-- A walker's path cost that spreads bots over routes: CZombiePathCost's
-- preference term makes each bot favour different areas, and keeps its
-- choice for ten seconds so repaths follow the same route.
local cos, floor = math.cos, math.floor
local Ground = require("foundation.npc.path.ground")
module(...)

local ROUTE_PERIOD = 10 -- seconds a bot keeps its preferences
local PREFERENCE_SPREAD = 50

function Preference(entIndex, areaId, now)
	local timeMod = floor(now / ROUTE_PERIOD) + 1
	return 1 + PREFERENCE_SPREAD * (1 + cos(entIndex * areaId * timeMod))
end

function Cost(step, limits, bot)
	return Ground.Weighted(step, limits, Preference(bot.entIndex, step.areaId, bot.now))
end
