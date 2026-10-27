#!/bin/sh
# AndroidTest.apk (AndroidTest.hx) on the device or emulator adb reaches
# (CI's android job: an x86-64 emulator with KVM): installs it, starts its
# NativeActivity and reads the app's lines from logcat (helder.os sends what
# the app prints there, tag hxmc; with its own lifecycle lines, tag helder.os
# at the debug level: each activity callback, the window's size):
#   - the cube rendered headless on the device's GPU matches cube.png
#     (GfxTest's rule); the activity's window, waited for, has a size, and
#     its frame is lit;
#   - 120 frames drawn in the window;
#   - a tap and a key come back as events (MouseDown, KeyDown of a);
#   - a drag held on the cube: scrolls at where it started with Mods.TOUCH,
#     the cube still while the finger rests, a scroll of nothing once let
#     go and the cube turning again; a fling glides on after the lift;
#   - Home takes the window (Suspend), starting the activity again gives it
#     back (Resume) and frames go on;
#   - a relaunch (the font scale changed: a configuration change the
#     manifest does not take, as an install's ApplicationInfo update at a
#     first launch is): the activity is destroyed without finishing and made
#     again in the running process, the program goes on in the new one's
#     window (Suspend, Resume, frames), twice (the scale set back);
#   - a screenshot (screencap) to <out>/cube-android.png, the log to
#     <out>/logcat.txt; Back (Escape) closes the window and the app's main
#     returns.
#   sh tests/gfx/android.sh <AndroidTest.apk> [out dir]
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
		adb logcat -d -s hxmc:I helder.os:D > "$log" 2>/dev/null
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

# wait_count <pattern> <count> <seconds>: until the app's log has count lines matching it
wait_count() {
	i=0
	while [ $i -lt "$3" ]; do
		adb logcat -d -s hxmc:I helder.os:D > "$log" 2>/dev/null
		[ "$(grep -c "$1" "$log")" -ge "$2" ] && return 0
		sleep 1
		i=$((i + 1))
	done
	echo "android.sh: not $2 \"$1\" in $3 s"
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
# a drag on the cube, held (input motionevent: down, moved, resting, up):
# its scrolls at where it started with Mods.TOUCH, the cube held still while
# the finger rests, a scroll of nothing without it once let go, the cube
# turning again; then a fling (a quick swipe): the drag glides on after the
# finger lifted (scrolls without Mods.TOUCH)
angle() {
	adb logcat -d -s hxmc:I helder.os:D > "$log" 2>/dev/null
	grep -o "AndroidTest: spin $1 angle -*[0-9]*" "$log" | tail -1 | grep -o -- "-*[0-9]*$"
}
size=$(grep -o "AndroidTest: window [0-9]*x[0-9]*" "$log" | head -1 | grep -o "[0-9]*x[0-9]*$")
W=${size%x*}
H=${size#*x}
x0=$((W / 4))
y0=$((H / 2))
adb shell input motionevent DOWN $x0 $y0
adb shell input motionevent MOVE $((x0 + W / 8)) $y0
adb shell input motionevent MOVE $((x0 + W / 4)) $y0
wait_count "event Scroll .* mods 16" 2 20
check "a drag: scrolls with Mods.TOUCH" $?
grep "event Scroll .* mods 16" "$log" | grep -o "Scroll [0-9]*,[0-9]* by -[0-9.]*,0 " | sed "s/ by .*//" | sort -u > "$out/drag-at.txt"
[ "$(wc -l < "$out/drag-at.txt")" -eq 1 ]
check "the drag's scrolls at where it started, the content following the finger" $?
sleep 2
held1=$(angle held)
sleep 2
held2=$(angle held)
echo "android.sh: held: angle $held1, then $held2"
[ -n "$held1" ] && [ "$held1" = "$held2" ]
check "the cube held still under the resting finger" $?
adb shell input motionevent UP $((x0 + W / 4)) $y0
wait_for "event Scroll .* by 0,0 mods 0" 20
check "let go: a scroll of nothing without Mods.TOUCH" $?
sleep 1
free1=$(angle free)
sleep 2
free2=$(angle free)
echo "android.sh: let go: angle $free1, then $free2"
[ -n "$free1" ] && [ "$free1" != "$free2" ]
check "the cube turning again once let go" $?
released=$(grep -c "event Scroll .* by 0,0 mods 0" "$log")
adb shell input swipe $x0 $y0 $((x0 + W / 2)) $y0 60
wait_count "event Scroll .* by 0,0 mods 0" $((released + 1)) 20
check "a fling: its release" $?
sleep 3
adb logcat -d -s hxmc:I helder.os:D > "$log" 2>/dev/null
glides=$(grep "event Scroll" "$log" | awk -v n=$((released + 1)) '/by 0,0 mods 0/ {r++; next} r >= n && / mods 0[[:space:]]*$/ {g++} END {print g + 0}')
echo "android.sh: the fling's glide: $glides scrolls"
[ "$glides" -ge 3 ]
check "the fling glides on after the finger lifted" $?
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
relaunch() {
	adb logcat -d -s hxmc:I helder.os:D > "$log" 2>/dev/null
	made=$(grep -c "onCreate: a new activity" "$log")
	resumed=$(grep -c "event Resume" "$log")
	adb shell settings put system font_scale "$1"
	wait_count "onCreate: a new activity" $((made + 1)) 30
	check "font scale $1: the activity made again in the process" $?
	wait_count "event Resume" $((resumed + 1)) 30
	check "font scale $1: the new activity's window (Resume)" $?
	grep -q "onDestroy: finishing\|AndroidTest: done" "$log"
	check "font scale $1: the program goes on" $((1 - $?))
	frames=$(grep -o "frames [0-9]*" "$log" | tail -1 | cut -d' ' -f2)
	wait_for "AndroidTest: frames $((frames + 60))" 60
	check "font scale $1: frames after the relaunch" $?
}
relaunch 1.15
relaunch 1.0
adb shell input keyevent KEYCODE_BACK
wait_for "AndroidTest: done" 30
check "Back: the app's main returns" $?
adb logcat -d > "$out/logcat-all.txt" 2>/dev/null
cat "$log"
exit $failed
