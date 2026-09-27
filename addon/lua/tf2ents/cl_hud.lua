-- Minimal round HUD: timer, payload progress, announcements, respawn countdown.

surface.CreateFont("TF2Ents.Timer", { font = "Roboto", size = 34, weight = 800 })
surface.CreateFont("TF2Ents.Label", { font = "Roboto", size = 18, weight = 700 })
surface.CreateFont("TF2Ents.Announce", { font = "Roboto", size = 42, weight = 900 })

-- The top-centre of the screen can sit under a display notch (MacBook), so
-- the timer is pushed down by a fraction of the screen height.
local timer_y = CreateClientConVar("tf2_hud_timer_y", "0.08", true, false, "Timer box top, as a fraction of screen height (clears display notches).")

local announcement

hook.Add("InitPostEntity", "tf2.ready", function()
	net.Start("tf2.ready")
	net.SendToServer()
end)

net.Receive("tf2.announce", function()
	announcement = {
		text = net.ReadString(),
		team = net.ReadUInt(2),
		expires = CurTime() + 4,
	}
end)

local function Clock(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function DrawTimer(w, h)
	if not GetGlobal2Bool("tf2.timer.show", false) then return end
	local top = math.floor(h * timer_y:GetFloat())
	local left
	if GetGlobal2Bool("tf2.timer.paused", true) then
		left = GetGlobal2Float("tf2.timer.left", 0)
	else
		left = GetGlobal2Float("tf2.timer.end", 0) - CurTime()
	end
	local label
	if TF2.State() == TF2.STATE.PREROUND then
		label = "PREPARE"
	elseif GetGlobal2Bool("tf2.timer.setup", false) then
		label = "SETUP"
	elseif GetGlobal2Bool("tf2.overtime", false) then
		label = "OVERTIME"
	end
	draw.RoundedBox(6, w / 2 - 70, top, 140, label and 64 or 46, Color(0, 0, 0, 170))
	draw.SimpleText(Clock(left), "TF2Ents.Timer", w / 2, top + 4, color_white, TEXT_ALIGN_CENTER)
	if label then
		draw.SimpleText(label, "TF2Ents.Label", w / 2, top + 40, Color(255, 210, 90), TEXT_ALIGN_CENTER)
	end
end

local function DrawCart(w, h)
	if not GetGlobal2Bool("tf2.cart.show", false) then return end
	local barW, barH = math.min(600, w * 0.5), 14
	local x, y = (w - barW) / 2, h - 90
	local progress = GetGlobal2Float("tf2.cart.progress", 0)
	draw.RoundedBox(4, x - 6, y - 6, barW + 12, barH + 12, Color(0, 0, 0, 170))
	surface.SetDrawColor(60, 60, 60, 255)
	surface.DrawRect(x, y, barW, barH)
	local blu = TF2.TeamColor[TF2.TEAM_BLUE]
	surface.SetDrawColor(blu.r, blu.g, blu.b, 255)
	surface.DrawRect(x, y, barW * progress, barH)

	local owners = string.Explode(",", GetGlobal2String("tf2.cart.owners", ""))
	for i, f in ipairs(string.Explode(",", GetGlobal2String("tf2.cart.cps", ""))) do
		local fraction = tonumber(f)
		if fraction then
			local c = TF2.TeamColor[tonumber(owners[i]) or 0] or TF2.TeamColor[0]
			draw.RoundedBox(4, x + barW * fraction - 7, y - 4, 14, barH + 8, c)
		end
	end
	draw.RoundedBox(3, x + barW * progress - 5, y - 10, 10, 10, color_white)

	local cappers = GetGlobal2Int("tf2.cart.cappers", 0)
	local status
	if cappers == -1 then
		status = "BLOCKED"
	elseif cappers > 0 then
		status = "PUSHING x" .. math.min(cappers, 3)
	else
		local recedeAt = GetGlobal2Float("tf2.cart.recedeAt", 0)
		if recedeAt > 0 then status = "Cart rolls back in " .. math.ceil(recedeAt - CurTime()) end
	end
	if status then
		draw.SimpleText(status, "TF2Ents.Label", w / 2, y - 30, color_white, TEXT_ALIGN_CENTER)
	end
end

local function DrawAnnouncement(w, h)
	if not announcement or CurTime() > announcement.expires then return end
	local c = TF2.TeamColor[announcement.team] or color_white
	draw.SimpleTextOutlined(announcement.text, "TF2Ents.Announce", w / 2, h * 0.25, c, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
end

local function DrawRespawn(w, h)
	local ply = LocalPlayer()
	if not IsValid(ply) or ply:Alive() then return end
	local at = ply:GetNW2Float("tf2.respawnAt", 0)
	if at <= 0 then return end
	local left = math.max(0, math.ceil(at - CurTime()))
	local text = left > 0 and ("Respawn in " .. left .. "s") or "Prepare to respawn"
	draw.SimpleTextOutlined(text, "TF2Ents.Label", w / 2, h * 0.7, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
end

local function DrawPreround(w, h)
	if TF2.State() ~= TF2.STATE.PREROUND then return end
	local left = math.max(1, math.ceil(GetGlobal2Float("tf2.preroundEnd", 0) - CurTime()))
	draw.SimpleTextOutlined("Round begins in " .. left, "TF2Ents.Announce", w / 2, h * 0.35, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
end

hook.Add("HUDPaint", "tf2.hud", function()
	if not TF2.Active() then return end
	local w, h = ScrW(), ScrH()
	DrawTimer(w, h)
	DrawCart(w, h)
	DrawPreround(w, h)
	DrawAnnouncement(w, h)
	DrawRespawn(w, h)
end)
