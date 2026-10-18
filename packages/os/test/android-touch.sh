#!/bin/sh
# Touch in a drawn UI on the device or emulator adb reaches (CI's android
# job, after android.sh, whose AndroidTest checks a drag held on the cube):
# AndroidTouchTest.apk (AndroidTouchTest.hx: a header over a scroll box),
# its lines from logcat (tag hxmc). A fling (a quick swipe up, from low in
# the box to over the header): the box follows the finger the whole way
# (the drag's scrolls at where it started), and glides on once let go;
# Back closes the window.
#   sh packages/os/test/android-touch.sh <AndroidTouchTest.apk> [out dir]
set -u
apk=$1
out=${2:-.}
mkdir -p "$out"
log="$out/touch-logcat.txt"
failed=0

wait_for() {
	i=0
	while [ $i -lt "$2" ]; do
		adb logcat -d -s hxmc:I > "$log" 2>/dev/null
		grep -q "$1" "$log" && return 0
		if adb logcat -d 2>/dev/null | grep -q "Fatal signal\|FATAL EXCEPTION\|dlopen failed\|CANNOT LINK"; then
			echo "android-touch.sh: the app crashed or did not load:"
			adb logcat -d 2>/dev/null | grep -E -A40 "Fatal signal|FATAL EXCEPTION|dlopen failed|CANNOT LINK" | head -120
			return 1
		fi
		sleep 1
		i=$((i + 1))
	done
	echo "android-touch.sh: no \"$1\" in $2 s"
	return 1
}

check() {
	if [ "$2" = 0 ]; then echo "android-touch.sh: $1: ok"; else
		echo "android-touch.sh: $1: FAIL"
		failed=1
	fi
}

adb wait-for-device
adb logcat -c
adb install -r "$apk"
check "install AndroidTouchTest" $?
adb shell am start -W -n org.hxmc.touchtest/android.app.NativeActivity
wait_for "AndroidTouchTest: ready" 60
check "the window" $?
sleep 1
# (the display's size: the swipe's ends)
size=$(adb shell wm size | grep -o "[0-9]*x[0-9]*" | tail -1)
W=${size%x*}
H=${size#*x}
echo "android-touch.sh: display ${W}x$H"
adb shell input swipe $((W / 2)) $((H * 85 / 100)) $((W / 2)) $((H * 5 / 100)) 120
wait_for "AndroidTouchTest: let go" 20
check "a fling: its release" $?
wait_for "AndroidTouchTest: settled" 30
check "the box settled" $?
grep -q "AndroidTouchTest: ok: the drag's scrolls at where it started" "$log"
check "the drag's scrolls at where it started" $?
grep -q "AndroidTouchTest: ok: the box followed the finger the whole drag" "$log"
check "the box followed the finger over the header" $?
grep -q "AndroidTouchTest: ok: the fling glides on once let go" "$log"
check "the fling glides on once let go" $?
adb exec-out screencap -p > "$out/touch-android.png"
check "screenshot" $?
adb shell input keyevent KEYCODE_BACK
wait_for "AndroidTouchTest: done" 30
check "Back closes the window" $?
adb logcat -d > "$out/touch-logcat-all.txt" 2>/dev/null
cat "$log"
exit $failed
