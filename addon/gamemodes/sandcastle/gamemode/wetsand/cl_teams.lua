-- TF2's team menu, reduced: BLU, RED, auto-assign and spectate, each with
-- its player count. The team key (F2) opens it on TF2 maps; picking a team
-- runs TF2's jointeam command, which enforces mp_teams_unbalance_limit.
local menu

local function TeamButton(parent, label, color, command)
	local b = vgui.Create("DButton", parent)
	b:Dock(TOP)
	b:DockMargin(0, 0, 0, 6)
	b:SetTall(40)
	b:SetText(label)
	b:SetTextColor(color_white)
	b:SetFont("DermaLarge")
	local hover = Color(math.min(color.r + 30, 255), math.min(color.g + 30, 255), math.min(color.b + 30, 255))
	b.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and hover or color)
	end
	b.DoClick = function()
		RunConsoleCommand("jointeam", command)
		menu:Close()
	end
	return b
end

local function Count(t)
	return team.NumPlayers(t)
end

function TF2.OpenTeamMenu()
	if IsValid(menu) then menu:Close() end
	menu = vgui.Create("DFrame")
	menu:SetTitle("Choose a team")
	menu:SetSize(320, 260)
	menu:Center()
	menu:MakePopup()
	menu:DockPadding(12, 32, 12, 12)
	local mine = LocalPlayer():Team()
	local function Label(name, t)
		local label = name .. "  (" .. Count(t) .. ")"
		if t == mine then label = label .. "  - yours" end
		return label
	end
	TeamButton(menu, Label("BLU", TF2.TEAM_BLUE), TF2.TeamColor[TF2.TEAM_BLUE], "blue")
	TeamButton(menu, Label("RED", TF2.TEAM_RED), TF2.TeamColor[TF2.TEAM_RED], "red")
	TeamButton(menu, "Auto-assign", Color(90, 90, 90), "auto")
	TeamButton(menu, Label("Spectate", TF2.TEAM_SPECTATOR), Color(60, 60, 60), "spectate")
end

net.Receive("tf2.team.menu", function()
	TF2.OpenTeamMenu()
end)
