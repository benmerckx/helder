#!/bin/sh
# AndroidNativeTest.apk (AndroidNativeTest.hx: helder.ui.native on Android's
# views) on the device or emulator adb reaches (CI's android job, after
# tests/gfx/android.sh); reads the app's lines from logcat (tag hxmc):
#   - the app's own checks (made, measured, placed, driven by the views'
#     calls, signals both ways) pass;
#   - accessibility: the views as the system's tools see them (uiautomator's
#     dump: the field, the checkbox, the button, the slider, the labels);
#   - real input at the dump's positions: a tap on the checkbox, on Submit
#     (enabled by it), on the field and text through the input method, each
#     logged by the app as its signals follow, and the label read back;
#   - a screenshot to <out>/native-android.png, the dumps and the log next
#     to it; the app closes its window and its main returns.
#   sh tests/ui/android-native.sh <AndroidNativeTest.apk> [out dir]
set -u
apk=$1
out=${2:-.}
pkg=org.hxmc.nativetest
mkdir -p "$out"
log="$out/native-logcat.txt"
failed=0

# wait_for <pattern> <seconds>: until the app's log has a line matching it
wait_for() {
	i=0
	while [ $i -lt "$2" ]; do
		adb logcat -d -s hxmc:I > "$log" 2>/dev/null
		grep -q "$1" "$log" && return 0
		if adb logcat -d 2>/dev/null | grep -q "Fatal signal\|FATAL EXCEPTION\|dlopen failed\|CANNOT LINK\|JNI DETECTED ERROR"; then
			echo "android-native.sh: the app crashed or did not load:"
			adb logcat -d 2>/dev/null | grep -E -A40 "Fatal signal|FATAL EXCEPTION|dlopen failed|CANNOT LINK|JNI DETECTED ERROR" | head -120
			return 1
		fi
		sleep 1
		i=$((i + 1))
	done
	echo "android-native.sh: no \"$1\" in $2 s"
	return 1
}

check() {
	if [ "$2" = 0 ]; then echo "android-native.sh: $1: ok"; else
		echo "android-native.sh: $1: FAIL"
		failed=1
	fi
}

# the views on screen, as accessibility services see them
dump() {
	adb shell uiautomator dump /sdcard/hxmc-ui.xml > /dev/null 2>&1
	adb shell cat /sdcard/hxmc-ui.xml > "$out/$1"
}

# tap <dump> <attributes>: at the centre of the first view whose attributes match
tap() {
	b=$(grep -io "<node [^>]*$2[^>]*>" "$out/$1" | head -1 | grep -o 'bounds="[^"]*"' | tr -c '0-9\n' ' ')
	if [ -z "$b" ]; then
		echo "android-native.sh: no view $2 in $1; its buttons:"
		grep -o '<node [^>]*Button[^>]*>' "$out/$1"
		return 1
	fi
	set -- $b
	adb shell input tap $((($1 + $3) / 2)) $((($2 + $4) / 2))
}

adb wait-for-device
adb logcat -c
adb install -r "$apk"
check "install" $?
adb shell am start -W -n $pkg/org.hxmc.Activity
wait_for "AndroidNativeTest: ready for input" 120
check "the app's checks ran" $?
grep "AndroidNativeTest: FAIL" "$log"
[ $? != 0 ]
check "the app's checks pass" $?
dump ui-native.xml
grep -o '<node [^>]*Button[^>]*>' "$out/ui-native.xml"
grep -qi 'class="android.widget.EditText"' "$out/ui-native.xml"
check "accessibility: the field (EditText)" $?
grep -qi 'text="I agree to the terms"[^>]*class="android.widget.CheckBox"' "$out/ui-native.xml"
check "accessibility: the checkbox" $?
grep -qi 'text="Submit"[^>]*class="android.widget.Button"[^>]*enabled="false"' "$out/ui-native.xml"
check "accessibility: Submit, disabled" $?
grep -qi 'class="android.widget.SeekBar"' "$out/ui-native.xml" && grep -qi 'text="Native controls"[^>]*class="android.widget.TextView"' "$out/ui-native.xml"
check "accessibility: the slider and the labels" $?
tap ui-native.xml 'class="android.widget.CheckBox"' && wait_for "input: .*agree true" 20
check "a tap on the checkbox" $?
dump ui-native-agreed.xml
tap ui-native-agreed.xml 'text="Submit"[^>]*class="android.widget.Button"[^>]*enabled="true"' && wait_for "input: .*submitted 1" 20
check "a tap on Submit, enabled" $?
tap ui-native-agreed.xml 'class="android.widget.EditText"' && sleep 2 && adb shell input text Linus && wait_for 'input: name "Linus"' 20
check "text typed through the input method" $?
wait_for "AndroidNativeTest: input done" 30
check "the app saw the input" $?
dump ui-native-typed.xml
grep -qi 'text="Hello, Linus!"' "$out/ui-native-typed.xml"
check "accessibility: the label follows" $?
adb exec-out screencap -p > "$out/native-android.png"
check "screenshot" $?
wait_for "AndroidNativeTest: done" 30
check "the window closes, main returns" $?
grep -q "AndroidNativeTest: [0-9]* checks, ok" "$log"
check "every check" $?
adb logcat -d > "$out/native-logcat-all.txt" 2>/dev/null
cat "$log"
if [ $failed != 0 ]; then
	echo "android-native.sh: the system's log around the app:"
	grep -E "AndroidRuntime|DEBUG|JNI|hxmc|nativetest|System.err|VerifyError|Rejecting|linker" "$out/native-logcat-all.txt" | tail -150
fi
exit $failed
