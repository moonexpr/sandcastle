-- The payload race announcer lines (Announcer.PLR_*). TF2's soundscripts no
-- longer define them, so they are registered here, on the client, where
-- WETSAND.BroadcastSound plays them; like TF2's other announcer entries they use
-- CHAN_VOICE2 and no attenuation.
local R = include("lib_payload_race.lua")

for name, wave in pairs(R.Sounds()) do
	if not sound.GetProperties(name) then
		sound.Add({ name = name, channel = CHAN_VOICE2, volume = 1.0, level = 0, pitch = 100, sound = wave })
	end
end
