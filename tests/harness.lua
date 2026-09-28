-- Minimal harness for Sandcastle's pure-logic libraries, run under plain
-- LuaJIT (no GMod). Libraries under test live in gamemode/wetsand/lib_*.lua and
-- use no GMod globals, so a test loads them with dofile.
local T = { passed = 0, failed = 0 }

T.ROOT = "addon/gamemodes/sandcastle/gamemode/wetsand/"

function T.lib(name)
	return dofile(T.ROOT .. "lib_" .. name .. ".lua")
end

function T.test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		T.passed = T.passed + 1
	else
		T.failed = T.failed + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end

function T.eq(actual, expected, what)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
	end
end

function T.near(actual, expected, epsilon, what)
	if math.abs(actual - expected) > (epsilon or 1e-6) then
		error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
	end
end

function T.finish()
	print(string.format("%d passed, %d failed", T.passed, T.failed))
	os.exit(T.failed == 0 and 0 or 1)
end

return T
