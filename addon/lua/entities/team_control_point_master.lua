-- team_control_point_master: declares a round won when one team owns every
-- control point of the active round (or every point, with no rounds).
ENT.Type = "point"
ENT.Base = "base_point"

-- Win reason passed to tf_gamerules (WINREASON_ALL_POINTS_CAPTURED).
local WINREASON_ALL_POINTS_CAPTURED = 1

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	if k == "cpm_restrict_team_cap_win" then
		self.restrictTeam = tonumber(value) or 0
	elseif k == "switch_teams" then
		self.switchTeams = value == "1"
	elseif string.sub(key, 1, 2) == "On" then
		self:StoreOutput(key, value)
	end
end

function ENT:Initialize()
	self.restrictTeam = self.restrictTeam or 0
	self.enabled = true
	hook.Add("TF2PointCaptured", self, self.CheckWinConditions)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end

-- The points in play: the highest-priority team_control_point_round's list,
-- or every control point when the map has no rounds.
function ENT:PointsInPlay()
	local best
	for _, round in ipairs(ents.FindByClass("team_control_point_round")) do
		if not best or round.priority > best.priority then best = round end
	end
	if best then return best:Points(), best.restrictTeam end
	return ents.FindByClass("team_control_point"), self.restrictTeam
end

function ENT:CheckWinConditions()
	if not self.enabled then return end
	local points, restrictTeam = self:PointsInPlay()
	if #points == 0 then return end
	local owner = points[1]:GetCapTeam()
	if owner == TF2.TEAM_UNASSIGNED or owner == restrictTeam then return end
	for _, point in ipairs(points) do
		if point:GetCapTeam() ~= owner then return end
	end
	self:Win(owner)
end

function ENT:Win(team)
	if team == TF2.TEAM_RED then self:TriggerOutput("OnWonByTeam1", self) end
	if team == TF2.TEAM_BLUE then self:TriggerOutput("OnWonByTeam2", self) end
	if IsValid(TF2.Rules) then
		TF2.Rules:SetWinningTeam(team, WINREASON_ALL_POINTS_CAPTURED, true, self.switchTeams)
	end
end

function ENT:AcceptInput(name, activator, caller, value)
	local input = string.lower(name)
	if input == "setwinner" then
		self:Win(tonumber(value) or 0)
	elseif input == "enable" then
		self.enabled = true
	elseif input == "disable" then
		self.enabled = false
	elseif input == "setcaplayout" or input == "setcaplayoutcustompositionx" or input == "setcaplayoutcustompositiony" then
		-- HUD layout only; the HUD here lays points out along the cart track.
	else
		return false
	end
	return true
end
