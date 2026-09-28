-- Teams as TF2 runs them: the one way to change a player's team
-- (CTFPlayer::ChangeTeam / ForceChangeTeam), the jointeam command
-- (HandleCommand_JoinTeam), auto-assignment (GetAutoTeam), and automatic
-- balancing (CTeamplayRoundBasedRules::BalanceTeams). The rules themselves
-- are in lib_teams.lua.
local L = TF2.TeamRules

util.AddNetworkString("tf2.team.menu")
util.AddNetworkString("tf2.team.ready")

-- TF2's convar, as teamplayroundbased_gamerules.cpp defines it;
-- mp_teams_unbalance_limit is shared (sh_core.lua) for the team menu.
local autoteambalance = CreateConVar("mp_autoteambalance", "1", FCVAR_NOTIFY,
	"Automatically balance the teams based on mp_teams_unbalance_limit. 0 = off, 1 = forcibly switch", 0, 1)
local unbalanceLimit = TF2.UnbalanceLimit

local UNASSIGNED, SPECTATOR, RED, BLUE = TF2.TEAM_UNASSIGNED, TF2.TEAM_SPECTATOR, TF2.TEAM_RED, TF2.TEAM_BLUE

local function Playing(team)
	return team == RED or team == BLUE
end

-- Players without a team and spectators watch the game in observer mode.
local function Observes(team)
	return team == UNASSIGNED or team == SPECTATOR
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
-- the spectators (or leaving players unassigned) puts the player into
-- observer mode. force follows ForceChangeTeam with a full team switch:
-- nobody dies (the round-end team swap, whose players are respawned anyway).
function TF2.SetPlayerTeam(ply, newTeam, force)
	local old = ply:Team()
	ply.tf2Team = newTeam
	if newTeam == old then return end
	if Observes(newTeam) then
		-- HandleCommand_JoinTeam: a live player dies before becoming a spectator.
		if not force and Playing(old) and ply:Alive() then Die(ply) end
		ply:SetTeam(newTeam)
		TF2.StartObserving(ply)
		return
	end
	ply:SetTeam(newTeam)
	if Observes(old) then
		-- The engine needs a spawn or a kill after leaving observer mode; the
		-- player waits, dead, for the new team's respawn wave. The kill comes
		-- after the team change so the wave is the new team's.
		TF2.StopObserving(ply)
		if ply:Alive() then ply:KillSilent() end
	elseif not force and Playing(old) and ply:Alive() then
		Die(ply)
	end
end

-- CTFPlayer::InitialSpawn (TF_STATE_WELCOME): a new player has no team.
-- GM:PlayerSpawn keeps them observing, and the team menu opens once their
-- client is ready for it ("tf2.team.ready").
function TF2.SetInitialTeam(ply)
	ply.tf2Team = UNASSIGNED
	ply:SetTeam(UNASSIGNED)
end

-- Undo a team change made behind TF2.SetPlayerTeam (other addons put
-- players on their own teams, such as 21 "Runner", in their spawn hooks).
-- A player who never had a TF2 team keeps it if they are on one, and is
-- otherwise left without a team and shown the team menu.
function TF2.RestoreTeam(ply)
	if not ply.tf2Team then
		local current = ply:Team()
		if Observes(current) or Playing(current) then
			ply.tf2Team = current
		else
			TF2.SetPlayerTeam(ply, UNASSIGNED, true)
			TF2.ShowTeamMenu(ply)
		end
	elseif ply:Team() ~= ply.tf2Team then
		ply:SetTeam(ply.tf2Team)
	end
end

-- CTFTeamMenu::ShowPanel refuses to open during game over, and for a
-- losing player while the winners celebrate.
function TF2.ShowTeamMenu(ply)
	if not L.TeamMenuAllowed(TF2.State(), ply:Team(), GetGlobal2Int("tf2.winner", 0)) then
		ply:PrintMessage(HUD_PRINTCENTER, "You can't change team at this time.")
		return
	end
	net.Start("tf2.team.menu")
	net.Send(ply)
end

-- Net messages sent during PlayerInitialSpawn can arrive before the client
-- can take them, so the client says when it is ready for the menu.
net.Receive("tf2.team.ready", function(_, ply)
	if TF2.Active() and ply.tf2Team == UNASSIGNED then TF2.ShowTeamMenu(ply) end
end)

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
