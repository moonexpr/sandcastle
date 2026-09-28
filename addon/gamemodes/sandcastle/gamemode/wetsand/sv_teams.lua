-- Teams as TF2 runs them: the one way to change a player's team
-- (CTFPlayer::ChangeTeam / ForceChangeTeam), the jointeam command
-- (HandleCommand_JoinTeam), auto-assignment (GetAutoTeam), and automatic
-- balancing (CTeamplayRoundBasedRules::BalanceTeams). The rules themselves
-- are in lib_teams.lua.
local L = TF2.TeamRules

util.AddNetworkString("tf2.team.menu")

-- TF2's convars, as teamplayroundbased_gamerules.cpp defines them.
local autoteambalance = CreateConVar("mp_autoteambalance", "1", FCVAR_NOTIFY,
	"Automatically balance the teams based on mp_teams_unbalance_limit. 0 = off, 1 = forcibly switch", 0, 1)
local unbalanceLimit = CreateConVar("mp_teams_unbalance_limit", "1", FCVAR_NONE,
	"Teams are unbalanced when one team has this many more players than the other team. (0 disables check)", 0, 30)

local SPECTATOR, RED, BLUE = TF2.TEAM_SPECTATOR, TF2.TEAM_RED, TF2.TEAM_BLUE

local function Playing(team)
	return team == RED or team == BLUE
end

local function Counts()
	return { [RED] = team.NumPlayers(RED), [BLUE] = team.NumPlayers(BLUE) }
end

function TF2.AutoTeam()
	return L.AutoTeam(team.NumPlayers(RED), team.NumPlayers(BLUE))
end

-- A switch's suicide is not a death that drops an ammo pack.
local function Die(ply)
	ply.tf2ChangingTeam = true
	ply:Kill()
	ply.tf2ChangingTeam = nil
end

-- The one way to change a player's TF2 team. The team is remembered, so a
-- spawn hook of another addon that moves the player is undone (see
-- TF2.RestoreTeam). CTFPlayer::ChangeTeam: a live player moving between RED
-- and BLU dies, and comes back with the new team's respawn wave; joining
-- the spectators puts the player into observer mode. force follows
-- ForceChangeTeam with a full team switch: nobody dies (the round-end team
-- swap, whose players are respawned anyway).
function TF2.SetPlayerTeam(ply, newTeam, force)
	local old = ply:Team()
	ply.tf2Team = newTeam
	if newTeam == old then return end
	if newTeam == SPECTATOR then
		-- HandleCommand_JoinTeam: a live player dies before becoming a spectator.
		if not force and Playing(old) and ply:Alive() then Die(ply) end
		ply:SetTeam(newTeam)
		TF2.StartObserving(ply)
		return
	end
	if old == SPECTATOR then
		-- The engine needs a spawn or a kill after leaving observer mode; the
		-- player waits, dead, for the new team's respawn wave.
		TF2.StopObserving(ply)
		if ply:Alive() then ply:KillSilent() end
	end
	ply:SetTeam(newTeam)
	if not force and Playing(old) and ply:Alive() then Die(ply) end
end

-- Undo a team change made behind TF2.SetPlayerTeam (other addons put
-- players on their own teams, such as 21 "Runner", in their spawn hooks).
-- A player who never had a TF2 team keeps spectator, RED or BLU if they
-- are on one, and is assigned a team otherwise.
function TF2.RestoreTeam(ply)
	if not ply.tf2Team then
		local current = ply:Team()
		if current == SPECTATOR or Playing(current) then
			ply.tf2Team = current
		else
			TF2.SetPlayerTeam(ply, TF2.AutoTeam(), true)
		end
	elseif ply:Team() ~= ply.tf2Team then
		ply:SetTeam(ply.tf2Team)
	end
end

function TF2.ShowTeamMenu(ply)
	net.Start("tf2.team.menu")
	net.Send(ply)
end

-- CTFPlayer::HandleCommand_JoinTeam: "red", "blue", "auto" or "spectate".
-- A join that would unbalance the teams is refused and the menu shown again.
function TF2.JoinTeam(ply, name)
	if TF2.State() == TF2.STATE.GAME_OVER then return end
	local newTeam = L.ParseJoinTeam(name)
	if newTeam == L.AUTO then newTeam = TF2.AutoTeam() end
	if newTeam < SPECTATOR or newTeam == ply:Team() then return end
	if newTeam ~= SPECTATOR and L.WouldUnbalance(Counts(), newTeam, ply:Team(), unbalanceLimit:GetInt()) then
		ply:PrintMessage(HUD_PRINTCENTER, "That team is full; join the other team or wait.")
		TF2.ShowTeamMenu(ply)
		return
	end
	TF2.SetPlayerTeam(ply, newTeam)
end

concommand.Add("jointeam", function(ply, _, args)
	if not IsValid(ply) or not TF2.Active() or not args[1] then return end
	TF2.JoinTeam(ply, args[1])
end, nil, "Join a team: red, blue, auto or spectate")

-- Balancing ----------------------------------------------------------------

local unbalancedSince, warned

-- CTeamplayRoundBasedRules::BalanceTeams. requireDead: mid-round, only dead
-- players are moved. The recently-switched queue of the SDK is left out;
-- the score still spares anyone moved in the last five minutes.
function TF2.BalanceTeams(requireDead)
	if not autoteambalance:GetBool() then return end
	local counts = Counts()
	local heavy, light = L.Unbalanced(counts, unbalanceLimit:GetInt())
	if not heavy then
		unbalancedSince, warned = nil, false
		return
	end
	local now = CurTime()
	unbalancedSince = unbalancedSince or now
	if not warned and now - unbalancedSince > 1 then
		PrintMessage(HUD_PRINTTALK, "Teams will be auto-balanced in 5 seconds")
		warned = true
	end
	local byId, candidates = {}, {}
	for _, ply in ipairs(team.GetPlayers(heavy)) do
		local id = ply:UserID()
		byId[id] = ply
		candidates[#candidates + 1] = {
			id = id,
			score = L.BalanceScore(now, now - ply:TimeConnected(), ply.tf2ForcedTeamAt),
			alive = ply:Alive(),
		}
	end
	local required = L.SwitchesRequired(counts[heavy], counts[light])
	for _, id in ipairs(L.PickBalanceSwitches(candidates, required, requireDead)) do
		local ply = byId[id]
		TF2.SetPlayerTeam(ply, light)
		ply.tf2ForcedTeamAt = now
		PrintMessage(HUD_PRINTTALK, ply:Nick() .. " was moved to the other team for game balance")
	end
end

-- State_Enter_PREROUND holds balancing off for the first 60 seconds of a
-- round; State_Think_RND_RUNNING balances dead players once a second.
local balanceFrom = 0

hook.Add("TF2RoundActive", "tf2.teams", function()
	balanceFrom = CurTime() + 60
end)

timer.Create("tf2.teams.balance", 1, 0, function()
	if not TF2.Active() or TF2.State() ~= TF2.STATE.RND_RUNNING then return end
	if CurTime() < balanceFrom then return end
	TF2.BalanceTeams(true)
end)
