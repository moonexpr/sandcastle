include("shared.lua")
include("tf2/cl_hud.lua")
include("tf2/cl_announcer.lua")

-- Tell the server this client has loaded, so the first round's pre-round
-- freeze is not spent on the loading screen.
function GM:InitPostEntity()
	self.BaseClass.InitPostEntity(self)
	net.Start("tf2.ready")
	net.SendToServer()
end

function GM:HUDPaint()
	self.BaseClass.HUDPaint(self)
	if TF2.Active() then TF2.DrawHUD() end
end

function GM:Think()
	self.BaseClass.Think(self)
	if TF2.Active() then TF2.AnnouncerThink() end
end
