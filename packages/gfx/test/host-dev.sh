#!/bin/sh
# hxmc dev's host on a desktop (docs/dev.md, "No reloads"; CI: gfx-macos,
# gfx-windows): the dev host (hxmc.dev.DevHost) runs DevHost1.<ext>
# (DevHostTest.hx, -D hxmc.shared -D hxmc.dev-host) with HXMC_DEV_NEXT
# naming two later builds, which the running build hands over to in turn,
# in the same process, on the same window: each build's line shows its
# version, the count kept and one more, the process and the window.
#   sh packages/gfx/test/host-dev.sh <dir with the host and DevHost1..3.<ext>> [dylib|dll|so] [host]
set -u
dir=$(cd "$1" && pwd)
ext=${2:-dylib}
host=${3:-host}
out="$dir/dev-out.txt"
failed=0
check() {
	if [ "$2" = 0 ]; then echo "host-dev.sh: $1: ok"; else
		echo "host-dev.sh: $1: FAIL"
		failed=1
	fi
}
# (Windows: the loader's paths, not MSYS's)
native=$dir
if command -v cygpath > /dev/null 2>&1; then native=$(cygpath -w "$dir"); fi
sep=/
case "$native" in *\\*) sep=\\ ;; esac
rm -f "$out" "$dir/dev.snapshot"
HXMC_DEV_NEXT="$native${sep}DevHost2.$ext;$native${sep}DevHost3.$ext" HXMC_DEV_SNAPSHOT="$native${sep}dev.snapshot" \
	"$dir/$host" "$native${sep}DevHost1.$ext" > "$out" 2>&1 &
pid=$!
i=0
while [ $i -lt 90 ] && ! grep -q "DevHostTest: v3 " "$out" 2>/dev/null; do
	if ! kill -0 $pid 2>/dev/null; then break; fi
	sleep 1
	i=$((i + 1))
done
kill $pid 2>/dev/null
sleep 1
cat "$out"
grep -q "DevHostTest: v3 " "$out"
check "two builds swapped in" $?
l1=$(grep "DevHostTest: v1 " "$out" | head -1)
l2=$(grep "DevHostTest: v2 " "$out" | head -1)
l3=$(grep "DevHostTest: v3 " "$out" | head -1)
echo "$l1" | grep -q "n=1 " && echo "$l2" | grep -q "n=2 " && echo "$l3" | grep -q "n=3 "
check "the count kept across the builds (n=1, 2, 3)" $?
p1=$(echo "$l1" | grep -o "pid=[0-9]*")
[ -n "$p1" ] && [ "$p1" = "$(echo "$l2" | grep -o "pid=[0-9]*")" ] && [ "$p1" = "$(echo "$l3" | grep -o "pid=[0-9]*")" ]
check "the same process ($p1)" $?
v1=$(echo "$l1" | grep -o "view=[0-9]*")
[ -n "$v1" ] && [ "$v1" != "view=0" ] && [ "$v1" = "$(echo "$l3" | grep -o "view=[0-9]*")" ]
check "the same window ($v1)" $?
exit $failed
