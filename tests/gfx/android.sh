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
#   - a tap and a key come back as events (a touch's PointerDown and
#     PointerUp, KeyDown of a), the tap without mouse events or scrolls;
#   - a drag held on the cube: its pointer turns the cube with the finger,
#     still while the finger rests, turning again once let go; a fling
#     flicks it on at the drag's speed after the lift; never a mouse event
#     or a scroll (a touch is its pointer's alone);
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
pkg=org.helder.androidtest
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
grep -q "event PointerDown [0-9]* touch .* primary" "$log" && grep -q "event PointerUp [0-9]* touch" "$log"
check "the tap: a touch's PointerDown and PointerUp" $?
! grep -q "event MouseDown\|event MouseUp\|event Scroll" "$log"
check "the tap: no mouse events, no scrolls (a touch is its pointer's alone)" $?
# a drag on the cube, held (input motionevent: down, moved, resting, up):
# the cube turned by the finger's pointer (a quarter of the window: a
# quarter turn), held still while the finger rests, turning again once
# let go; then a fling (a quick swipe): flicked on at the drag's speed
# after the finger lifted. No scrolls, no mouse events: the pointers alone.
angle() {
	adb logcat -d -s hxmc:I helder.os:D > "$log" 2>/dev/null
	grep -o "AndroidTest: spin $1 angle -*[0-9]*" "$log" | tail -1 | grep -o -- "-*[0-9]*$"
}
speed() {
	adb logcat -d -s hxmc:I helder.os:D > "$log" 2>/dev/null
	grep -o "AndroidTest: spin free angle -*[0-9]* speed -*[0-9]*" "$log" | tail -1 | grep -o -- "-*[0-9]*$"
}
size=$(grep -o "AndroidTest: window [0-9]*x[0-9]*" "$log" | head -1 | grep -o "[0-9]*x[0-9]*$")
W=${size%x*}
H=${size#*x}
x0=$((W / 4))
y0=$((H / 2))
ups=$(grep -c "event PointerUp" "$log")
before=$(angle free)
adb shell input motionevent DOWN $x0 $y0
adb shell input motionevent MOVE $((x0 + W / 8)) $y0
adb shell input motionevent MOVE $((x0 + W / 4)) $y0
wait_count "event PointerMove [0-9]* touch" 2 20
check "a drag: the finger's PointerMoves" $?
sleep 2
held1=$(angle held)
sleep 2
held2=$(angle held)
echo "android.sh: before $before, held: angle $held1, then $held2"
[ -n "$held1" ] && [ "$held1" = "$held2" ]
check "the cube held still under the resting finger" $?
[ -n "$before" ] && [ -n "$held1" ] && [ $((held1 - before)) -ge 600 ]
check "the cube turned with the finger (a quarter of the window: about 785 mrad)" $?
adb shell input motionevent UP $((x0 + W / 4)) $y0
wait_count "event PointerUp [0-9]* touch" $((ups + 1)) 20
check "let go: its PointerUp" $?
sleep 1
free1=$(angle free)
sleep 2
free2=$(angle free)
echo "android.sh: let go: angle $free1, then $free2"
[ -n "$free1" ] && [ "$free1" != "$free2" ]
check "the cube turning again once let go" $?
ups=$(grep -c "event PointerUp" "$log")
lines=$(wc -l < "$log")
adb shell input swipe $x0 $y0 $((x0 + W / 2)) $y0 60
wait_count "event PointerUp [0-9]* touch" $((ups + 1)) 20
check "a fling: its release" $?
# (the spin's first line after the release: within 20 frames)
sleep 1
adb logcat -d -s hxmc:I helder.os:D > "$log" 2>/dev/null
flick=$(tail -n +$((lines + 1)) "$log" | awk '/event PointerUp [0-9]* touch/ {r = 1; next} r && /AndroidTest: spin free/ {print; exit}' | grep -o -- "speed -*[0-9]*" | grep -o -- "-*[0-9]*$")
echo "android.sh: the fling's speed after it: $flick mrad/s (its own 600)"
[ -n "$flick" ] && [ "$flick" -ge 1500 ]
check "the fling carries the cube on at the drag's speed" $?
! grep -q "event MouseDown\|event MouseUp\|event Scroll" "$log"
check "the drags: no mouse events, no scrolls" $?
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
