#!/bin/sh
# hxmc dev's host on macOS (docs/dev.md, "No reloads"; CI's gfx-macos job):
# the dev host (hxmc.dev.DevHost) runs DevHost1.dylib (DevHostTest.hx, -D
# hxmc.shared -D hxmc.dev-host) with HXMC_DEV_NEXT naming two later builds,
# which the running build hands over to in turn, in the same process, on
# the same window: each build's line shows its version, the count kept and
# one more, the process and the window's view.
#   sh packages/gfx/test/mac-dev.sh <dir with host, DevHost1.dylib, DevHost2.dylib, DevHost3.dylib>
set -u
dir=$(cd "$1" && pwd)
out="$dir/dev-out.txt"
failed=0
check() {
	if [ "$2" = 0 ]; then echo "mac-dev.sh: $1: ok"; else
		echo "mac-dev.sh: $1: FAIL"
		failed=1
	fi
}
rm -f "$out" "$dir/dev.snapshot"
HXMC_DEV_NEXT="$dir/DevHost2.dylib;$dir/DevHost3.dylib" HXMC_DEV_SNAPSHOT="$dir/dev.snapshot" "$dir/host" "$dir/DevHost1.dylib" > "$out" 2>&1 &
pid=$!
i=0
while [ $i -lt 60 ] && ! grep -q "DevHostTest: v3 " "$out" 2>/dev/null; do
	if ! kill -0 $pid 2>/dev/null; then break; fi
	sleep 1
	i=$((i + 1))
done
kill $pid 2>/dev/null
cat "$out"
grep -q "DevHostTest: v3 " "$out"
check "two builds swapped in" $?
l1=$(grep "DevHostTest: v1 " "$out" | head -1)
l2=$(grep "DevHostTest: v2 " "$out" | head -1)
l3=$(grep "DevHostTest: v3 " "$out" | head -1)
echo "$l1" | grep -q "n=1 " && echo "$l2" | grep -q "n=2 " && echo "$l3" | grep -q "n=3 "
check "the count kept across the builds (n=1, 2, 3)" $?
p1=$(echo "$l1" | grep -o "pid=[0-9]*")
[ -n "$p1" ] && [ "$p1" = "pid=$pid" ] && [ "$p1" = "$(echo "$l2" | grep -o "pid=[0-9]*")" ] && [ "$p1" = "$(echo "$l3" | grep -o "pid=[0-9]*")" ]
check "the same process, the host's ($p1)" $?
v1=$(echo "$l1" | grep -o "view=[0-9a-fA-F]*")
[ -n "$v1" ] && [ "$v1" != "view=0" ] && [ "$v1" = "$(echo "$l3" | grep -o "view=[0-9a-fA-F]*")" ]
check "the same window ($v1)" $?
exit $failed
