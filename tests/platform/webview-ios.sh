#!/bin/sh
# helder.ui.platform's web view on an iPhone simulator (macOS with Xcode:
# CI's ios-simulator job): examples/todo built for the web (the helder web
# build the web view loads), tests/platform/WebViewCheck.hx (a <webview>
# in a drawn window) and WebShellCheck.hx (the web view on the whole
# screen) built for the simulator, launched with their output here
# (simctl launch --console-pty; HELDER_WEB_DIR: the web build, read from
# the Mac's disk), each ending with "webview: <mode>: N checks, ok"; a
# screenshot of each in <out dir>.
#   sh tests/platform/webview-ios.sh <helder> [out dir]
set -u
helder=$1
out=$(mkdir -p "${2:-bin/pack/ios-webview}" && cd "${2:-bin/pack/ios-webview}" && pwd)
failed=0

check() {
	if [ "$2" = 0 ]; then echo "webview-ios.sh: $1: ok"; else
		echo "webview-ios.sh: $1: FAIL"
		failed=1
	fi
}

"$helder" build examples/todo/Todo.hx --target web -o "$out/todo/Todo.wasm"
check "helder build examples/todo --target web" $?
ls "$out/todo"
"$helder" build tests/platform/WebViewCheck.hx --target ios-sim -o "$out/WebViewCheck.app"
check "helder build tests/platform/WebViewCheck.hx --target ios-sim" $?
"$helder" build tests/platform/WebShellCheck.hx --target ios-sim -o "$out/WebShellCheck.app"
check "helder build tests/platform/WebShellCheck.hx --target ios-sim" $?

runtime=$(xcrun simctl list runtimes available | grep -o 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*' | sort -t- -k2,2n -k3,3n | tail -1)
type=$(xcrun simctl list devicetypes | grep -o 'com\.apple\.CoreSimulator\.SimDeviceType\.iPhone-[0-9][0-9]*)' | tr -d ')' | sort -t- -k2,2n | tail -1)
echo "webview-ios.sh: $type on $runtime"
udid=$(xcrun simctl create helder-ios-webview "$type" "$runtime")
check "a simulator made" $?
cleanup() {
	xcrun simctl shutdown "$udid" > /dev/null 2>&1
	xcrun simctl delete "$udid" > /dev/null 2>&1
}
trap cleanup EXIT
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1

# one app: installed, launched with its output in <out>/<name>.txt, its last line awaited
run() {
	name=$1
	id=org.helder.$name
	xcrun simctl install "$udid" "$out/$name.app"
	check "simctl install $name.app" $?
	: > "$out/$name.txt"
	SIMCTL_CHILD_HELDER_WEB_DIR="$out/todo" xcrun simctl launch --console-pty --terminate-running-process "$udid" "$id" > "$out/$name.txt" 2>&1 &
	console=$!
	i=0
	shot=0
	while [ $i -lt 150 ] && ! grep -q "webview: [a-z]*: [0-9]* checks" "$out/$name.txt"; do
		if [ $shot = 0 ] && grep -q "a snapshot of the page" "$out/$name.txt"; then
			xcrun simctl io "$udid" screenshot "$out/$name.png" > /dev/null 2>&1
			shot=1
		fi
		sleep 1
		i=$((i + 1))
	done
	[ $shot = 0 ] && xcrun simctl io "$udid" screenshot "$out/$name.png" > /dev/null 2>&1
	grep "webview:" "$out/$name.txt"
	grep -q "webview: [a-z]*: [0-9]* checks, ok" "$out/$name.txt"
	check "$name: its checks" $?
	xcrun simctl terminate "$udid" "$id" > /dev/null 2>&1
	kill $console > /dev/null 2>&1
}
run WebViewCheck
run WebShellCheck
exit $failed
