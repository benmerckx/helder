#!/bin/sh
# tests/pack/Hello.hx on the Android device or emulator adb reaches (CI's
# android job, on its emulator; not run elsewhere): `helder run --target
# android` (the device's ABI, built, installed, started, its output from
# logcat) prints the hello line; then the APK by adb alone, as hxmc's
# android.sh did: uninstalled, installed, started, the line in logcat;
# logcat kept in <out dir>/logcat.txt.
#   sh tests/pack/android.sh <helder> [out dir]
set -u
helder=$1
out=$(mkdir -p "${2:-bin/pack/android}" && cd "${2:-bin/pack/android}" && pwd)
id=org.helder.hello
line="hello from helder on .*: 998001 6 boom"
failed=0

check() {
	if [ "$2" = 0 ]; then echo "android.sh: $1: ok"; else
		echo "android.sh: $1: FAIL"
		failed=1
	fi
}

adb wait-for-device
adb uninstall $id > /dev/null 2>&1
"$helder" run tests/pack/Hello.hx --target android > "$out/run.txt" 2>&1
check "helder run --target android" $?
cat "$out/run.txt"
grep -q "$line" "$out/run.txt"
check "helder run: the app's line, from logcat" $?

apk=$(ls bin/android/Hello.apk)
adb uninstall $id > /dev/null 2>&1
adb install -r "$apk"
check "adb install" $?
adb logcat -c
adb shell am start -W -n $id/android.app.NativeActivity
check "am start" $?
i=0
while [ $i -lt 60 ] && ! adb logcat -d -s hxmc:I | grep -q "hello from helder on"; do
	sleep 1
	i=$((i + 1))
done
adb logcat -d > "$out/logcat.txt"
grep "hxmc" "$out/logcat.txt" | tail -20
grep -q "$line" "$out/logcat.txt"
check "its line in logcat" $?

# The assets (tests/asset/Checksum.hx: helder.asset's files in the APK's
# assets/, read through AAssetManager): `helder run` prints each file's
# size and CRC-32, an image's decoded pixels', the bundle's list: the lines
# of tests/asset/checksum.txt, which every other build prints too.
adb uninstall org.helder.checksum > /dev/null 2>&1
"$helder" run tests/asset/Checksum.hx --target android > "$out/checksum.txt" 2>&1
check "helder run tests/asset/Checksum.hx" $?
cat "$out/checksum.txt"
while IFS= read -r l; do
	grep -qF "$l" "$out/checksum.txt"
	check "assets: $l" $?
done < tests/asset/checksum.txt

# The screen (tests/pack/Screen.hx, for the emulator's ABI): started
# upright, its window, safe area and the display's frames, the bars hidden;
# then turned (user_rotation 1, the sensor off), sent to the background
# (Home) and started again; its lines (logcat's, in <out dir>/screen.txt)
# checked by tests/pack/screen.mjs.
sid=org.helder.screen
seen() {
	adb logcat -d -v raw -s hxmc:I | grep -q "$1"
}
wait_for() {
	i=0
	while [ $i -lt "$2" ] && ! seen "$1"; do
		sleep 1
		i=$((i + 1))
	done
	seen "$1"
	check "screen: $1" $?
}
"$helder" build tests/pack/Screen.hx --target android-x86_64 -o "$out/Screen.apk"
check "helder build tests/pack/Screen.hx" $?
adb uninstall $sid > /dev/null 2>&1
adb install -r "$out/Screen.apk"
check "adb install Screen.apk" $?
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 0
adb logcat -c
adb shell am start -W -n $sid/android.app.NativeActivity
wait_for "screen: immersive" 60
sleep 2
adb shell settings put system user_rotation 1
wait_for "screen: resize" 20
sleep 3
adb shell input keyevent KEYCODE_HOME
wait_for "screen: suspend" 20
sleep 2
adb shell am start -n $sid/android.app.NativeActivity
wait_for "first frame after resume" 30
sleep 1
adb logcat -d -v raw -s hxmc:I > "$out/screen.txt"
adb logcat -d -s helder.os:D > "$out/screen-lifecycle.txt"
adb shell am force-stop $sid
adb shell settings put system user_rotation 0
node tests/pack/screen.mjs "$out/screen.txt" android
check "the screen's lines (tests/pack/screen.mjs)" $?

# The golf example (examples/golf): built for the emulator, started, its
# first frames drawn (its line), a screenshot kept in <out dir>/golf.png.
gid=org.helder.golf
"$helder" build examples/golf/Golf.hx --target android-x86_64 -o "$out/Golf.apk"
check "helder build examples/golf" $?
adb uninstall $gid > /dev/null 2>&1
adb install -r "$out/Golf.apk"
check "adb install Golf.apk" $?
adb logcat -c
adb shell am start -W -n $gid/android.app.NativeActivity
i=0
while [ $i -lt 60 ] && ! seen "floating greens: 9 holes, drawing"; do
	sleep 1
	i=$((i + 1))
done
seen "floating greens: 9 holes, drawing"
check "golf: its first frames" $?
sleep 3
adb exec-out screencap -p > "$out/golf.png"
adb logcat -d > "$out/golf-logcat.txt"
adb logcat -d -v raw -s hxmc:I | tail -20
adb shell am force-stop $gid
exit $failed
