#!/bin/sh
# Text input in a window the program draws, on the device or emulator adb
# reaches; the app's lines from logcat (tag hxmc):
#   - AndroidTextTest.apk: text input on shows the soft keyboard for its
#     hidden EditText (dumpsys input_method), keys typed by adb come as
#     TextInput, an input method's composition and commit as TextEditing
#     and TextInput; off hides it.
#   sh tests/os/android-text.sh <AndroidTextTest.apk> [out dir]
set -u
text=$1
out=${2:-.}
mkdir -p "$out"
log="$out/text-logcat.txt"
failed=0

wait_for() {
	i=0
	while [ $i -lt "$2" ]; do
		adb logcat -d -s hxmc:I > "$log" 2>/dev/null
		grep -q "$1" "$log" && return 0
		if adb logcat -d 2>/dev/null | grep -q "Fatal signal\|FATAL EXCEPTION\|dlopen failed\|CANNOT LINK\|JNI DETECTED ERROR"; then
			echo "android-text.sh: the app crashed or did not load:"
			adb logcat -d 2>/dev/null | grep -E -A40 "Fatal signal|FATAL EXCEPTION|dlopen failed|CANNOT LINK|JNI DETECTED ERROR" | head -120
			return 1
		fi
		sleep 1
		i=$((i + 1))
	done
	echo "android-text.sh: no \"$1\" in $2 s"
	return 1
}

check() {
	if [ "$2" = 0 ]; then echo "android-text.sh: $1: ok"; else
		echo "android-text.sh: $1: FAIL"
		failed=1
	fi
}

ime() {
	adb shell dumpsys input_method | grep -q "$1"
}

adb wait-for-device
# text input in a drawn window
adb logcat -c
adb install -r "$text"
check "install AndroidTextTest" $?
adb shell am start -W -n org.hxmc.texttest/android.app.NativeActivity
wait_for "AndroidTextTest: window" 60
check "the window" $?
sleep 2
ime "mInputShown=true"
check "text input on: the soft keyboard shown" $?
adb shell dumpsys input_method | grep -q "mServedView=.*EditText"
check "for the hidden EditText" $?
adb shell input text hello
wait_for 'AndroidTextTest: typed "hello"' 20
check "keys typed: TextInput" $?
wait_for "AndroidTextTest: text input off" 20
check "an input method's composition and commit" $?
grep -q "AndroidTextTest: ok: the input method's composition and commit" "$log"
check "as TextEditing and TextInput" $?
sleep 2
ime "mInputShown=false"
check "text input off: the keyboard hidden" $?
wait_for "AndroidTextTest: end" 30
check "the window closes" $?
adb logcat -d > "$out/text-logcat-all.txt" 2>/dev/null
cat "$log"
if [ $failed != 0 ]; then
	echo "android-text.sh: the system's log around the app:"
	grep -E "AndroidRuntime|DEBUG|JNI|hxmc|texttest|System.err|InputMethod|ImeTracker" "$out/text-logcat-all.txt" | tail -150
fi
exit $failed
