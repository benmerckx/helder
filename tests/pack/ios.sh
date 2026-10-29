#!/bin/sh
# tests/pack/Hello.hx on an iPhone simulator (macOS with Xcode: CI's
# ios-simulator job; not run elsewhere): the .app checked with Apple's tools
# (codesign --verify --strict, plutil -lint), a simulator of the newest iOS
# runtime and iPhone made and booted, then `helder run --target ios -d
# <it>` (built, installed, launched with its output here: simctl launch
# --console) prints the hello line; the simulator deleted at the end.
#   sh tests/pack/ios.sh <helder> [out dir]
set -u
helder=$1
out=$(mkdir -p "${2:-bin/pack/ios}" && cd "${2:-bin/pack/ios}" && pwd)
line="hello from helder on .*: 998001 6 boom"
failed=0

check() {
	if [ "$2" = 0 ]; then echo "ios.sh: $1: ok"; else
		echo "ios.sh: $1: FAIL"
		failed=1
	fi
}

"$helder" build tests/pack/Hello.hx --target ios-sim -o "$out/Hello.app"
check "helder build --target ios-sim" $?
codesign --verify --strict --verbose=2 "$out/Hello.app"
check "codesign --verify --strict" $?
plutil -lint "$out/Hello.app/Info.plist"
check "plutil -lint Info.plist" $?

runtime=$(xcrun simctl list runtimes available | grep -o 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*' | sort -t- -k2,2n -k3,3n | tail -1)
type=$(xcrun simctl list devicetypes | grep -o 'com\.apple\.CoreSimulator\.SimDeviceType\.iPhone-[0-9][0-9]*)' | tr -d ')' | sort -t- -k2,2n | tail -1)
echo "ios.sh: $type on $runtime"
udid=$(xcrun simctl create helder-ios-hello "$type" "$runtime")
check "a simulator made" $?
cleanup() {
	xcrun simctl shutdown "$udid" > /dev/null 2>&1
	xcrun simctl delete "$udid" > /dev/null 2>&1
}
trap cleanup EXIT
# (helder run boots it: the simulator named is not booted yet)
"$helder" run tests/pack/Hello.hx --target ios -d "$udid" > "$out/run.txt" 2>&1
code=$?
cat "$out/run.txt"
# (the app prints its line and returns: simctl may report the launch as
# failed when it has ended before simctl was done; the line decides)
if [ $code != 0 ] && grep -q "$line" "$out/run.txt"; then
	echo "ios.sh: helder run: exit code $code, but the app ran and printed its line"
	code=0
fi
check "helder run --target ios -d <simulator>" $code
grep -q "$line" "$out/run.txt"
check "its line, from simctl launch --console" $?

# The assets (tests/asset/Checksum.hx: helder.asset's files in the app's
# assets/, sealed by CodeResources): Apple's codesign verifies the bundle,
# then `helder run` prints each file's size and CRC-32, an image's decoded
# pixels', the bundle's list: the lines of tests/asset/checksum.txt.
"$helder" build tests/asset/Checksum.hx --target ios-sim -o "$out/Checksum.app"
check "helder build tests/asset/Checksum.hx --target ios-sim" $?
codesign --verify --strict --verbose=2 "$out/Checksum.app"
check "codesign --verify --strict: the assets sealed" $?
"$helder" run tests/asset/Checksum.hx --target ios -d "$udid" > "$out/checksum.txt" 2>&1
code=$?
cat "$out/checksum.txt"
if [ $code != 0 ] && grep -q "pixels crc" "$out/checksum.txt"; then code=0; fi
check "helder run tests/asset/Checksum.hx --target ios" $code
while IFS= read -r l; do
	grep -qF "$l" "$out/checksum.txt"
	check "assets: $l" $?
done < tests/asset/checksum.txt

# The screen (tests/pack/Screen.hx) on the same simulator: launched with
# its output here (--console-pty, in the background: <out dir>/screen.txt),
# its window, safe area and the display's frames, the bars hidden; then the
# Settings app launched over it (the background) and it again (back); its
# lines checked by tests/pack/screen.mjs.
sid=org.helder.Screen
wait_for() {
	i=0
	while [ $i -lt "$2" ] && ! grep -q "$1" "$out/screen.txt"; do
		sleep 1
		i=$((i + 1))
	done
	grep -q "$1" "$out/screen.txt"
	check "screen: $1" $?
}
"$helder" build tests/pack/Screen.hx --target ios-sim -o "$out/Screen.app"
check "helder build tests/pack/Screen.hx --target ios-sim" $?
xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1
xcrun simctl install "$udid" "$out/Screen.app"
check "simctl install Screen.app" $?
: > "$out/screen.txt"
xcrun simctl launch --console-pty --terminate-running-process "$udid" $sid > "$out/screen.txt" 2>&1 &
console=$!
wait_for "screen: immersive" 60
sleep 2
xcrun simctl launch "$udid" com.apple.Preferences > /dev/null 2>&1
wait_for "screen: suspend" 20
sleep 2
xcrun simctl launch "$udid" $sid > /dev/null 2>&1
wait_for "first frame after resume" 30
sleep 1
xcrun simctl terminate "$udid" $sid > /dev/null 2>&1
kill $console > /dev/null 2>&1
node tests/pack/screen.mjs "$out/screen.txt" ios
check "the screen's lines (tests/pack/screen.mjs)" $?

# The golf example (examples/golf): built for the simulator, launched, its
# first frames drawn (its line), a screenshot kept in <out dir>/golf.png.
gid=org.helder.Golf
"$helder" build examples/golf/Golf.hx --target ios-sim -o "$out/Golf.app"
check "helder build examples/golf --target ios-sim" $?
xcrun simctl install "$udid" "$out/Golf.app"
check "simctl install Golf.app" $?
: > "$out/golf.txt"
xcrun simctl launch --console-pty --terminate-running-process "$udid" $gid > "$out/golf.txt" 2>&1 &
console=$!
i=0
while [ $i -lt 60 ] && ! grep -q "floating greens: 9 holes, drawing" "$out/golf.txt"; do
	sleep 1
	i=$((i + 1))
done
tail -20 "$out/golf.txt"
grep -q "floating greens: 9 holes, drawing" "$out/golf.txt"
check "golf: its first frames" $?
sleep 3
xcrun simctl io "$udid" screenshot "$out/golf.png" > /dev/null 2>&1
xcrun simctl terminate "$udid" $gid > /dev/null 2>&1
kill $console > /dev/null 2>&1
exit $failed
