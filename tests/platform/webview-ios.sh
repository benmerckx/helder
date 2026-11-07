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

# (DejaVu Sans for the web build's text: a page has no system fonts, the Mac no DejaVu)
if [ ! -f "$out/fonts/DejaVuSans.ttf" ]; then
	mkdir -p "$out/fonts"
	curl -sSfL --retry 3 https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.tar.bz2 | tar xjf - -C "$out/fonts" --strip-components 2 dejavu-fonts-ttf-2.37/ttf/DejaVuSans.ttf dejavu-fonts-ttf-2.37/ttf/DejaVuSans-Bold.ttf
fi
HELDER_FONT_DIRS="$out/fonts" "$helder" build examples/todo/Todo.hx --target web -o "$out/todo/Todo.wasm"
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

# the newest crash report of the apps here: its exception, the crashed thread's frames
report() {
	r=$(ls -t ~/Library/Logs/DiagnosticReports/WebViewCheck*.ips ~/Library/Logs/DiagnosticReports/WebShellCheck*.ips 2> /dev/null | head -1)
	[ -n "$r" ] && python3 -c 'import json,sys; t=open(sys.argv[1]).read().split("\n",1)[1]; d=json.loads(t); th=[x for x in d["threads"] if x.get("triggered")][0]; im=d["usedImages"]; print(d.get("exception")); [print(f.get("imageOffset"), im[f["imageIndex"]].get("name"), f.get("symbol")) for f in th["frames"][:30]]' "$r"
}

# one app: installed, launched with its output in <out>/<name>.txt, its last line awaited
run() {
	name=$1
	id=org.helder.$name
	base=$name${2:+-scheme}
	xcrun simctl install "$udid" "$out/$name.app"
	check "simctl install $name.app" $?
	: > "$out/$base.txt"
	launch() {
		SIMCTL_CHILD_HELDER_WEBVIEW_LOCAL=${2:-} SIMCTL_CHILD_HELDER_WEB_DIR="$out/todo" xcrun simctl launch --console-pty --terminate-running-process "$udid" "$id" > "$out/$base.txt" 2>&1 &
		console=$!
	}
	launch "$@"
	# (nothing from it within 30 s, as a first launch on a just booted simulator may: its crash
	# report, then once more)
	i=0
	while [ $i -lt 30 ] && ! grep -q "webview:" "$out/$base.txt"; do
		sleep 1
		i=$((i + 1))
	done
	if ! grep -q "webview:" "$out/$base.txt"; then
		echo "webview-ios.sh: $base: no output; launched again"
		report
		kill $console > /dev/null 2>&1
		launch "$@"
	fi
	# (from outside the web view, the Mac's curl: the simulator's loopback is the Mac's; its
	# server refuses a request without its secret, a guessed one, and the bridge)
	i=0
	while [ $i -lt 20 ] && ! grep -q "webview: content at" "$out/$base.txt"; do
		sleep 0.5
		i=$((i + 1))
	done
	origin=$(grep -o "webview: content at http://127.0.0.1:[0-9]*" "$out/$base.txt" | head -1 | sed 's/webview: content at //')
	if [ -n "$origin" ]; then
		echo "webview-ios.sh: $base: from outside: $origin"
		s=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$origin/index.html")
		[ "$s" = 403 ]
		check "$base: curl without the secret: 403 ($s)" $?
		s=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$origin/0000000000000000000000000000000000000000000000000000000000000000/index.html")
		[ "$s" = 403 ]
		check "$base: curl with a guessed secret: 403 ($s)" $?
		s=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST -H "Origin: $origin" --data "shello" "$origin/__helder/post")
		[ "$s" = 403 ]
		check "$base: curl posting to the bridge without the secret: 403 ($s)" $?
	elif [ -z "${2:-}" ]; then
		check "$base: the loopback's origin printed" 1
	fi
	i=0
	shot=0
	while [ $i -lt 150 ] && ! grep -q "webview: [a-z]*: [0-9]* checks" "$out/$base.txt"; do
		if [ $shot = 0 ] && grep -q "a snapshot of the page" "$out/$base.txt"; then
			sleep 1
			xcrun simctl io "$udid" screenshot "$out/$base.png" > /dev/null 2>&1
			shot=1
		fi
		if [ $shot = 1 ] && grep -q "the helder web build ran" "$out/$base.txt"; then
			sleep 1
			xcrun simctl io "$udid" screenshot "$out/$base-todo.png" > /dev/null 2>&1
			shot=2
		fi
		sleep 1
		i=$((i + 1))
	done
	[ $shot = 0 ] && xcrun simctl io "$udid" screenshot "$out/$base.png" > /dev/null 2>&1
	grep "webview:" "$out/$base.txt"
	grep -q "webview: [a-z]*: [0-9]* checks, ok" "$out/$base.txt"
	r=$?
	check "$base: its checks" $r
	[ $r = 0 ] || report
	xcrun simctl terminate "$udid" "$id" > /dev/null 2>&1
	kill $console > /dev/null 2>&1
}
run WebViewCheck
run WebShellCheck
# (the same through WKURLSchemeHandler's app:// instead of the loopback's HTTP: WebContent.local false)
run WebShellCheck 0
exit $failed
