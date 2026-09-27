include("shared.lua")
for _, f in ipairs(GM:TF2Modules("cl_")) do include("tf2/" .. f) end

-- Tell the server this client has loaded, so the first round's pre-round
-- freeze is not spent on the loading screen.
function GM:InitPostEntity()
	self.BaseClass.InitPostEntity(self)
	net.Start("tf2.ready")
	net.SendToServer()
end

function GM:HUDPaint()
	self.BaseClass.HUDPaint(self)
	if not TF2.Active() then return end
	TF2.DrawHUD()
	-- Modules draw their own HUD elements here.
	hook.Run("SandcastleHUDPaint", ScrW(), ScrH())
end

function GM:Think()
	self.BaseClass.Think(self)
	if TF2.Active() then TF2.AnnouncerThink() end
end
