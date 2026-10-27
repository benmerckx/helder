#!/bin/sh
# hxmc dev's host on an iPhone simulator (docs/dev.md, "No reloads"; CI's
# ios-simulator job, after ios.sh): DevHostTest.app (DevHostTest.hx, -D
# hxmc.dev-host) launched with HXMC_DEV_NEXT naming two dylibs of later
# versions of it (-D hxmc.shared), which the running build hands over to in
# turn, in the same process, on the same view: each build's line shows its
# version, the count kept and one more, the process and the view.
#   sh tests/gfx/ios-dev.sh <dir with DevHostTest.app, DevHost2.dylib, DevHost3.dylib> [out dir]
set -u
dir=$(cd "$1" && pwd)
out=$(mkdir -p "${2:-.}" && cd "${2:-.}" && pwd)
id=org.hxmc.devhosttest
stdout="$out/dev-stdout.txt"
stderr="$out/dev-stderr.txt"
snapshot="$out/dev.snapshot"
failed=0

check() {
	if [ "$2" = 0 ]; then echo "ios-dev.sh: $1: ok"; else
		echo "ios-dev.sh: $1: FAIL"
		failed=1
	fi
}

wait_for() {
	i=0
	while [ $i -lt "$2" ]; do
		grep -q "$1" "$stdout" 2>/dev/null && return 0
		sleep 1
		i=$((i + 1))
	done
	echo "ios-dev.sh: no \"$1\" in $2 s"
	return 1
}

runtime=$(xcrun simctl list runtimes available | grep -o 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*' | sort -t- -k2,2n -k3,3n | tail -1)
type=$(xcrun simctl list devicetypes | grep -o 'com\.apple\.CoreSimulator\.SimDeviceType\.iPhone-[0-9][0-9]*)' | tr -d ')' | sort -t- -k2,2n | tail -1)
udid=$(xcrun simctl create hxmc-ios-dev "$type" "$runtime")
check "a simulator made" $?
cleanup() {
	xcrun simctl shutdown "$udid" > /dev/null 2>&1
	xcrun simctl delete "$udid" > /dev/null 2>&1
}
trap cleanup EXIT
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b > /dev/null
check "booted" $?
xcrun simctl install "$udid" "$dir/DevHostTest.app"
check "install" $?
rm -f "$stdout" "$stderr" "$snapshot"
SIMCTL_CHILD_HXMC_DEV_NEXT="$dir/DevHost2.dylib;$dir/DevHost3.dylib" SIMCTL_CHILD_HXMC_DEV_SNAPSHOT="$snapshot" \
	xcrun simctl launch --terminate-running-process --stdout="$stdout" --stderr="$stderr" "$udid" $id
check "launch" $?
wait_for "DevHostTest: v3 " 90
check "two builds swapped in" $?
cat "$stdout" "$stderr"
l1=$(grep "DevHostTest: v1 " "$stdout" | head -1)
l2=$(grep "DevHostTest: v2 " "$stdout" | head -1)
l3=$(grep "DevHostTest: v3 " "$stdout" | head -1)
echo "$l1" | grep -q "n=1 " && echo "$l2" | grep -q "n=2 " && echo "$l3" | grep -q "n=3 "
check "the count kept across the builds (n=1, 2, 3)" $?
p1=$(echo "$l1" | grep -o "pid=[0-9]*"); p3=$(echo "$l3" | grep -o "pid=[0-9]*")
[ -n "$p1" ] && [ "$p1" = "$(echo "$l2" | grep -o "pid=[0-9]*")" ] && [ "$p1" = "$p3" ]
check "the same process ($p1)" $?
v1=$(echo "$l1" | grep -o "view=[0-9a-fA-F]*"); v3=$(echo "$l3" | grep -o "view=[0-9a-fA-F]*")
[ -n "$v1" ] && [ "$v1" != "view=0" ] && [ "$v1" = "$v3" ]
check "the same view ($v1)" $?
xcrun simctl io "$udid" screenshot "$out/dev-ios.png" > /dev/null 2>&1
xcrun simctl terminate "$udid" $id
exit $failed
