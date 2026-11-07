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
# (a crash: the system's report, its thread that crashed)
r=$(ls -t ~/Library/Logs/DiagnosticReports/WebViewCheck*.ips 2> /dev/null | head -1)
if [ -n "$r" ]; then
	cp "$r" "$out/crash.ips"
	python3 -c 'import json,sys; t=open(sys.argv[1]).read().split("\n",1)[1]; d=json.loads(t); th=[x for x in d["threads"] if x.get("triggered")][0]; im=d["usedImages"]; print(d.get("exception")); [print(f.get("imageOffset"), im[f["imageIndex"]].get("name"), f.get("symbol")) for f in th["frames"][:40]]' "$r"
fi
exit $failed
