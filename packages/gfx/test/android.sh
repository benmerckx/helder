#!/bin/sh
# AndroidTest.apk (AndroidTest.hx) on the device or emulator adb reaches
# (CI's android job: an x86-64 emulator with KVM): installs it, starts its
# NativeActivity and reads the app's lines from logcat (hxmc.os sends what
# the app prints there, tag hxmc):
#   - the cube rendered headless on the device's GPU matches cube.png
#     (GfxTest's rule); the activity's window, waited for, has a size, and
#     its frame is lit;
#   - 120 frames drawn in the window;
#   - a tap and a key come back as events (MouseDown, KeyDown of a);
#   - Home takes the window (Suspend), starting the activity again gives it
#     back (Resume) and frames go on;
#   - a screenshot (screencap) to <out>/cube-android.png, the log to
#     <out>/logcat.txt; Back (Escape) closes the window and the app's main
#     returns.
#   sh packages/gfx/test/android.sh <AndroidTest.apk> [out dir]
set -u
apk=$1
out=${2:-.}
pkg=org.hxmc.gfxtest
mkdir -p "$out"
log="$out/logcat.txt"
failed=0

# wait <pattern> <seconds>: until the app's log has a line matching it
wait_for() {
	i=0
	while [ $i -lt "$2" ]; do
		adb logcat -d -s hxmc:I > "$log" 2>/dev/null
		grep -q "$1" "$log" && return 0
		if adb logcat -d 2>/dev/null | grep -q "Fatal signal\|FATAL EXCEPTION\|dlopen failed\|CANNOT LINK"; then
			echo "android.sh: the app crashed or did not load"
			return 1
		fi
		sleep 1
		i=$((i + 1))
	done
	echo "android.sh: no \"$1\" in $2 s"
	return 1
}

check() {
	if [ "$2" = 0 ]; then echo "android.sh: $1: ok"; else
		echo "android.sh: $1: FAIL"
		failed=1
	fi
}

adb wait-for-device
adb shell getprop ro.build.version.release
adb shell getprop ro.product.cpu.abi
adb logcat -c
adb install -r "$apk"
check "install" $?
adb shell am start -W -n $pkg/android.app.NativeActivity
wait_for "AndroidTest: frames 120" 120
check "120 frames in the window" $?
grep -q "AndroidTest: GfxTest: cube, android headless: ok\|GfxTest: cube, android headless: ok" "$log"
check "the headless cube matches cube.png" $?
grep -q "AndroidTest: window [1-9][0-9]*x[1-9]" "$log"
check "the window has a size" $?
grep -q "AndroidTest: window frame .*: lit" "$log"
check "the window's frame is lit" $?
adb shell input tap 300 300
adb shell input keyevent KEYCODE_A
wait_for "event KeyDown .* key 97" 20
check "a tap and a key as events" $?
grep -q "event MouseDown" "$log"
check "the tap: MouseDown" $?
adb exec-out screencap -p > "$out/cube-android.png"
check "screenshot" $?
adb shell input keyevent KEYCODE_HOME
wait_for "event Suspend" 30
check "Home: Suspend" $?
adb shell am start -W -n $pkg/android.app.NativeActivity
wait_for "event Resume" 30
check "back again: Resume" $?
frames=$(grep -o "frames [0-9]*" "$log" | tail -1 | cut -d' ' -f2)
wait_for "AndroidTest: frames $((frames + 60))" 60
check "frames after Resume" $?
adb shell input keyevent KEYCODE_BACK
wait_for "AndroidTest: done" 30
check "Back: the app's main returns" $?
adb logcat -d > "$out/logcat-all.txt" 2>/dev/null
cat "$log"
exit $failed
