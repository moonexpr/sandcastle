#!/bin/sh
# Run every tests/*_test.lua under LuaJIT from the repo root; nonzero if any fail.
cd "$(dirname "$0")/../.." || exit 2
status=0
for t in tests/*_test.lua; do
	echo "== $t"
	luajit "$t" || status=1
done
exit $status
