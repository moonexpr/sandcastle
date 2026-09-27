local T = dofile("tests/harness.lua")

T.test("eq passes on equal values", function() T.eq(1 + 1, 2) end)
T.test("eq raises on different values", function()
	local ok = pcall(T.eq, 1, 2)
	T.eq(ok, false, "pcall result")
end)
T.test("near tolerates small error", function() T.near(0.1 + 0.2, 0.3, 1e-9) end)

T.finish()
