#!/bin/sh
# IosTest.app (IosTest.hx) on an iPhone simulator (macOS with Xcode; CI's
# ios-simulator job): checks the bundle with Apple's tools (codesign
# --verify, plutil -lint), makes and boots a simulator of the newest iOS
# runtime and iPhone, installs the app and launches it with its stdout and
# stderr in files (what the app prints: its lines), then:
#   - the cube rendered headless on the simulator's Metal matches cube.png
#     (GfxTest's rule); the window has a size, and its frame is lit;
#   - 120 frames drawn in the window;
#   - a tap on the Simulator's window (SimTap: a click posted as an HID
#     event, the simulator's touch) comes back as MouseDown and MouseUp;
#     a fling (SimTap's quick drag) as scrolls at where it started with
#     Mods.TOUCH, a scroll of nothing without it, then its glide's;
#   - a screenshot (simctl io) to <out>/cube-ios.png;
#   - another app (Settings) sends it to the background (Suspend), launching
#     it again brings it back (Resume) and frames go on;
#   - the system log of the app's process to <out>/log.txt; the simulator is
#     deleted at the end.
#   sh tests/gfx/ios.sh <IosTest.app> [out dir] [SimTap]
set -u
app=$1
out=$(mkdir -p "${2:-.}" && cd "${2:-.}" && pwd)
tap=${3:-}
id=org.hxmc.gfxtest
stdout="$out/stdout.txt"
failed=0

check() {
	if [ "$2" = 0 ]; then echo "ios.sh: $1: ok"; else
		echo "ios.sh: $1: FAIL"
		failed=1
	fi
}

# wait_for <pattern> <seconds>: until the app's stdout has a line matching it
wait_for() {
	i=0
	while [ $i -lt "$2" ]; do
		grep -q "$1" "$stdout" 2>/dev/null && return 0
		if grep -q "Uncaught exception\|hxmc: " "$out/stderr.txt" 2>/dev/null; then
			echo "ios.sh: the app failed:"
			cat "$out/stderr.txt"
			return 1
		fi
		sleep 1
		i=$((i + 1))
	done
	echo "ios.sh: no \"$1\" in $2 s"
	return 1
}

codesign --verify --strict --verbose=2 "$app"
check "codesign --verify" $?
plutil -lint "$app/Info.plist"
check "plutil -lint Info.plist" $?

runtime=$(xcrun simctl list runtimes available | grep -o 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*' | sort -t- -k2,2n -k3,3n | tail -1)
type=$(xcrun simctl list devicetypes | grep -o 'com\.apple\.CoreSimulator\.SimDeviceType\.iPhone-[0-9][0-9]*)' | tr -d ')' | sort -t- -k2,2n | tail -1)
echo "ios.sh: $type on $runtime"
udid=$(xcrun simctl create hxmc-ios-test "$type" "$runtime")
check "a simulator made" $?
cleanup() {
	xcrun simctl shutdown "$udid" > /dev/null 2>&1
	xcrun simctl delete "$udid" > /dev/null 2>&1
}
trap cleanup EXIT
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b > /dev/null
check "booted" $?
# (the Simulator app's window: what SimTap clicks)
open -a Simulator --args -CurrentDeviceUDID "$udid"
xcrun simctl install "$udid" "$app"
check "install" $?
rm -f "$stdout" "$out/stderr.txt"
xcrun simctl launch --terminate-running-process --stdout="$stdout" --stderr="$out/stderr.txt" "$udid" $id
check "launch" $?
wait_for "IosTest: frames 120" 120
check "120 frames in the window" $?
grep -q "GfxTest: cube, ios headless: ok" "$stdout"
check "the headless cube matches cube.png" $?
grep -q "IosTest: window [1-9][0-9]*x[1-9]" "$stdout"
check "the window has a size" $?
grep -q "IosTest: window frame .*: lit" "$stdout"
check "the window's frame is lit" $?
xcrun simctl io "$udid" screenshot "$out/cube-ios.png"
check "screenshot" $?
if [ -n "$tap" ]; then
	sleep 2
	"$tap"
	wait_for "event MouseUp" 20
	check "a tap: MouseDown and MouseUp" $?
	grep -q "event MouseDown" "$stdout"
	check "the tap: MouseDown" $?
	# a fling (a quick drag up): its scrolls at where it started with
	# Mods.TOUCH, a scroll of nothing without it once let go, then the
	# glide's scrolls
	"$tap" 0.5 0.7 0.5 0.35
	wait_for "event Scroll .* by 0,0 mods 0" 20
	check "a fling: scrolls, then its release" $?
	sleep 3
	grep "event Scroll .* mods 16" "$stdout" | grep -o "Scroll [0-9]*,[0-9]* by [0-9.e-]*,[0-9.e-]* " | sed "s/ by .*//" | sort -u > "$out/drag-at.txt"
	[ "$(wc -l < "$out/drag-at.txt")" -eq 1 ]
	check "the fling's scrolls with Mods.TOUCH, at where it started" $?
	glides=$(grep "event Scroll" "$stdout" | awk '/by 0,0 mods 0/ {r = 1; next} r && / mods 0[[:space:]]*$/ {g++} END {print g + 0}')
	echo "ios.sh: the fling's glide: $glides scrolls"
	[ "$glides" -ge 3 ]
	check "the fling glides on after the finger lifted" $?
fi
xcrun simctl launch "$udid" com.apple.Preferences > /dev/null
wait_for "event Suspend" 30
check "another app: Suspend" $?
xcrun simctl launch "$udid" $id > /dev/null
wait_for "event Resume" 30
check "back again: Resume" $?
frames=$(grep -o "frames [0-9]*" "$stdout" | tail -1 | cut -d' ' -f2)
wait_for "IosTest: frames $((frames + 60))" 60
check "frames after Resume" $?
xcrun simctl spawn "$udid" log show --last 10m --style compact --predicate 'process == "IosTest"' > "$out/log.txt" 2>&1
xcrun simctl terminate "$udid" $id
cat "$stdout"
exit $failed
