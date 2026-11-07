#!/bin/sh
# helder.ui.platform's web view on the Android emulator adb reaches (CI's
# android job): examples/todo built for the web (the helder web build the
# web view loads), tests/platform/WebViewCheck.hx (a <webview> over a drawn
# window: a panel window) and WebShellCheck.hx (the web view as the
# activity's content) built for the emulator, installed, the web build put
# in each app's files/todo (run-as: the APKs are debuggable), started;
# their lines from logcat, each ending with "webview: <mode>: N checks,
# ok"; a screenshot of each in <out dir>.
#   sh tests/platform/webview-android.sh <helder> [out dir]
set -u
helder=$1
out=$(mkdir -p "${2:-bin/pack/android-webview}" && cd "${2:-bin/pack/android-webview}" && pwd)
failed=0

check() {
	if [ "$2" = 0 ]; then echo "webview-android.sh: $1: ok"; else
		echo "webview-android.sh: $1: FAIL"
		failed=1
	fi
}

"$helder" build examples/todo/Todo.hx --target web -o "$out/todo/Todo.wasm"
check "helder build examples/todo --target web" $?
"$helder" build tests/platform/WebViewCheck.hx --target android-x86_64 -o "$out/WebViewCheck.apk"
check "helder build tests/platform/WebViewCheck.hx" $?
"$helder" build tests/platform/WebShellCheck.hx --target android-x86_64 -o "$out/WebShellCheck.apk"
check "helder build tests/platform/WebShellCheck.hx" $?

adb wait-for-device
adb shell rm -rf /data/local/tmp/todo
adb push "$out/todo" /data/local/tmp/todo > /dev/null
adb shell dumpsys package com.google.android.webview 2>/dev/null | grep -m1 versionName
adb shell dumpsys package com.android.webview 2>/dev/null | grep -m1 versionName

seen() {
	adb logcat -d -v raw -s hxmc:I | grep -q "$1"
}

# one app: installed, the web build copied in, started; its lines in <out>/<name>.txt
run() {
	name=$1
	id=org.helder.$(echo "$name" | tr 'A-Z' 'a-z')
	activity=$2
	adb uninstall "$id" > /dev/null 2>&1
	adb install -r "$out/$name.apk"
	check "adb install $name.apk" $?
	adb shell "run-as $id mkdir -p files/todo"
	adb shell "cd /data/local/tmp/todo && tar cf - . | run-as $id tar xf - -C files/todo"
	adb shell "run-as $id ls files/todo"
	adb logcat -c
	adb shell am start -W -n "$id/$activity"
	i=0
	shot=0
	while [ $i -lt 150 ] && ! seen "webview: [a-z]*: [0-9]* checks"; do
		if [ $shot = 0 ] && seen "a snapshot of the page"; then
			adb exec-out screencap -p > "$out/$name.png"
			shot=1
		fi
		if [ $shot = 1 ] && seen "the helder web build ran"; then
			sleep 1
			adb exec-out screencap -p > "$out/$name-todo.png"
			shot=2
		fi
		sleep 1
		i=$((i + 1))
	done
	[ $shot = 0 ] && adb exec-out screencap -p > "$out/$name.png"
	adb logcat -d -v raw -s hxmc:I > "$out/$name.txt"
	adb logcat -d > "$out/$name-logcat.txt"
	grep "webview:" "$out/$name.txt"
	grep -E "chromium|AndroidRuntime|FATAL|JNI DETECTED|libc" "$out/$name-logcat.txt" | tail -30
	grep -q "webview: [a-z]*: [0-9]* checks, ok" "$out/$name.txt"
	check "$name: its checks" $?
	adb shell am force-stop "$id"
}
run WebViewCheck android.app.NativeActivity
run WebShellCheck org.hxmc.Activity
exit $failed
