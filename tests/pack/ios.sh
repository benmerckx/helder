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
exit $failed
