#!/bin/sh
# Compile every Lua file under addon/ with LuaJIT, then run the LuaJIT tests and
# print the summed totals; nonzero if any file fails to compile or any test fails.
cd "$(dirname "$0")/../.." || exit 2
status=0
count=0
for f in $(find addon tests -name '*.lua'); do
	count=$((count + 1))
	luajit -b "$f" /dev/null || status=1
done
echo "compiled $count files"
out=$(.devtools/bin/run_lua_tests.sh 2>&1) || status=1
echo "$out" | grep -E '^FAIL'
echo "$out" | awk '/passed/ { p += $1; f += $3 } END { print "TOTAL " p " passed, " f " failed" }'
exit $status
