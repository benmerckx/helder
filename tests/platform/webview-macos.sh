#!/bin/sh
# helder.ui.platform's web view on macOS (CI's desktop-macos job): the
# WKWebView of tests/platform/WebViewCheck.hx in a drawn window (the same
# AppleWebView as iOS's), its page, wasm, bridge and snapshot, then
# examples/todo's web build in it; its last line "webview: embedded: N
# checks, ok".
#   sh tests/platform/webview-macos.sh <helder> [out dir]
set -u
helder=$1
out=$(mkdir -p "${2:-bin/pack/macos-webview}" && cd "${2:-bin/pack/macos-webview}" && pwd)
failed=0

check() {
	if [ "$2" = 0 ]; then echo "webview-macos.sh: $1: ok"; else
		echo "webview-macos.sh: $1: FAIL"
		failed=1
	fi
}

if [ ! -f "$out/fonts/DejaVuSans.ttf" ]; then
	mkdir -p "$out/fonts"
	curl -sSfL --retry 3 https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.tar.bz2 | tar xjf - -C "$out/fonts" --strip-components 2 dejavu-fonts-ttf-2.37/ttf/DejaVuSans.ttf dejavu-fonts-ttf-2.37/ttf/DejaVuSans-Bold.ttf
fi
HELDER_FONT_DIRS="$out/fonts" "$helder" build examples/todo/Todo.hx --target web -o "$out/todo/Todo.wasm"
check "helder build examples/todo --target web" $?
"$helder" build tests/platform/WebViewCheck.hx -o "$out/WebViewCheck"
check "helder build tests/platform/WebViewCheck.hx" $?
HELDER_WEB_DIR="$out/todo" "$out/WebViewCheck" > "$out/WebViewCheck.txt" 2>&1 &
p=$!
# (from outside the web view, as another process of the machine: its loopback
# server refuses a request without its secret, a guessed one, and the bridge)
i=0
while [ $i -lt 60 ] && ! grep -q "webview: content at http://127.0.0.1:" "$out/WebViewCheck.txt"; do
	sleep 0.5
	i=$((i + 1))
done
origin=$(grep -o "webview: content at http://127.0.0.1:[0-9]*" "$out/WebViewCheck.txt" | head -1 | sed 's/webview: content at //')
outsider() {
	if [ -z "$origin" ]; then
		check "the loopback's origin printed" 1
		return
	fi
	echo "webview-macos.sh: from outside: $origin"
	s=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$origin/index.html")
	[ "$s" = 403 ]
	check "curl without the secret: 403 ($s)" $?
	s=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$origin/0000000000000000000000000000000000000000000000000000000000000000/index.html")
	[ "$s" = 403 ]
	check "curl with a guessed secret: 403 ($s)" $?
	s=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST -H "Origin: $origin" --data "shello" "$origin/__helder/post")
	[ "$s" = 403 ]
	check "curl posting to the bridge without the secret: 403 ($s)" $?
}
outsider
i=0
while [ $i -lt 120 ] && ! grep -q "webview: [a-z]*: [0-9]* checks" "$out/WebViewCheck.txt"; do
	kill -0 $p 2> /dev/null || break
	sleep 1
	i=$((i + 1))
done
kill $p > /dev/null 2>&1
cat "$out/WebViewCheck.txt"
grep -q "webview: [a-z]*: [0-9]* checks, ok" "$out/WebViewCheck.txt"
check "WebViewCheck: its checks" $?
# (a failure: run again under lldb, the crashed thread's backtrace)
if ! grep -q "checks, ok" "$out/WebViewCheck.txt"; then
	HELDER_WEB_DIR="$out/todo" perl -e "alarm 120; exec @ARGV" lldb --batch -o run -k "thread backtrace" -k "register read" -k quit -- "$out/WebViewCheck" 2>&1 | tail -80
fi
exit $failed
