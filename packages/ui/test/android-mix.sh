#!/bin/sh
# Mixing GPU and native views on the device or emulator adb reaches (CI's
# android job, after android-native.sh); the apps' lines from logcat (tag hxmc):
#   - AndroidMixTest.apk (views): a GpuView among views: its own checks
#     (frames, lit pixels, placed between the views, a button stopping and
#     starting its frames); a screenshot (<out>/mix-android.png); Home takes
#     its surface, the activity back gives a new one and frames go on;
#   - AndroidTextTest.apk (the window the program draws): text input on
#     shows the soft keyboard for its hidden EditText (dumpsys
#     input_method), keys typed by adb come as TextInput, an input method's
#     composition and commit as TextEditing and TextInput; off hides it.
#   sh packages/ui/test/android-mix.sh <AndroidMixTest.apk> <AndroidTextTest.apk> [out dir]
set -u
mix=$1
text=$2
out=${3:-.}
mkdir -p "$out"
log="$out/mix-logcat.txt"
failed=0

wait_for() {
	i=0
	while [ $i -lt "$2" ]; do
		adb logcat -d -s hxmc:I > "$log" 2>/dev/null
		grep -q "$1" "$log" && return 0
		if adb logcat -d 2>/dev/null | grep -q "Fatal signal\|FATAL EXCEPTION\|dlopen failed\|CANNOT LINK\|JNI DETECTED ERROR"; then
			echo "android-mix.sh: the app crashed or did not load:"
			adb logcat -d 2>/dev/null | grep -E -A40 "Fatal signal|FATAL EXCEPTION|dlopen failed|CANNOT LINK|JNI DETECTED ERROR" | head -120
			return 1
		fi
		sleep 1
		i=$((i + 1))
	done
	echo "android-mix.sh: no \"$1\" in $2 s"
	return 1
}

check() {
	if [ "$2" = 0 ]; then echo "android-mix.sh: $1: ok"; else
		echo "android-mix.sh: $1: FAIL"
		failed=1
	fi
}

ime() {
	adb shell dumpsys input_method | grep -q "$1"
}

adb wait-for-device
# a GPU view among views
adb logcat -c
adb install -r "$mix"
check "install AndroidMixTest" $?
adb shell am start -W -n org.hxmc.mixtest/org.hxmc.Activity
wait_for "AndroidMixTest: ready" 60
check "the GPU view's checks ran" $?
grep "AndroidMixTest: FAIL" "$log"
[ $? != 0 ]
check "the GPU view's checks pass" $?
adb exec-out screencap -p > "$out/mix-android.png"
check "screenshot" $?
adb shell input keyevent KEYCODE_HOME
wait_for "AndroidMixTest: no surface" 30
check "Home: the GPU view's surface goes" $?
adb shell am start -W -n org.hxmc.mixtest/org.hxmc.Activity
wait_for "AndroidMixTest: resumed" 40
check "back: a new surface, frames" $?
wait_for "AndroidMixTest: done" 30
check "the window closes" $?
grep -q "AndroidMixTest: [0-9]* checks, ok" "$log"
check "every check of the GPU view" $?
cp "$log" "$out/mix-logcat-gpu.txt"
cat "$log"
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
adb logcat -d > "$out/mix-logcat-all.txt" 2>/dev/null
cat "$log"
if [ $failed != 0 ]; then
	echo "android-mix.sh: the system's log around the apps:"
	grep -E "AndroidRuntime|DEBUG|JNI|hxmc|mixtest|texttest|System.err|InputMethod|ImeTracker" "$out/mix-logcat-all.txt" | tail -150
fi
exit $failed
