#!/bin/sh
# native.jni on the Android device or emulator adb reaches (CI's android
# job, on its emulator): tests/typescript/native/jni.ts built for the
# device's ABI by `helder run --target android`, installed, started, its
# line from logcat (Build.VERSION's SDK_INT and RELEASE, System's
# properties, a StringBuilder made and appended to).
#   sh tests/typescript/native/android.sh <helder> [out dir]
set -u
helder=$1
out=$(mkdir -p "${2:-bin/typescript/android}" && cd "${2:-bin/typescript/android}" && pwd)
line="native.jni: SDK_INT [0-9][0-9]* (true), release true, time true, vm [A-Za-z]*, jni 42 6"
adb wait-for-device
adb logcat -c
"$helder" run tests/typescript/native/jni.ts --target android > "$out/jni.txt" 2>&1
code=$?
cat "$out/jni.txt"
if [ $code != 0 ]; then
	echo "native/android.sh: helder run: FAIL ($code)"
	exit 1
fi
if grep -q "$line" "$out/jni.txt"; then echo "native/android.sh: native.jni's line: ok"; else
	echo "native/android.sh: native.jni's line: FAIL"
	adb logcat -d > "$out/logcat.txt"
	grep -E "hxmc|helder|AndroidRuntime|DEBUG|F libc" "$out/logcat.txt" | tail -60
	exit 1
fi
