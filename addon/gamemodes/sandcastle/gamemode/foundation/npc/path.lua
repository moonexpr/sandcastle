-- Path costs: the IPathCost functor a NextBot hands its path search, as
-- strategies. A strategy is a part (foundation.npc.path.<name>) providing
-- Cost(step, limits, bot) -> cost or IMPASSABLE, where
--   step   = { hasFrom, traversable, ladderLength, length, centerDistance,
--              heightChange, fromCostSoFar, areaId } for the move into an area,
--   limits = the variant's LOCOMOTION (stepHeight, jumpHeight, deathDropHeight),
--   bot    = { entIndex, now }.
-- The binding builds `step` from the engine's navigation areas; a variant
-- names its strategy in PATH.
module(...)

IMPASSABLE = -1
JUMP_PENALTY = 5 -- jumping is slower than flat ground
