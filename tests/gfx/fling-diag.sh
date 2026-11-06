#!/bin/sh
# (temporary diagnostics) flings on the running AndroidTest: input swipe, then evdev through su
set -u
adb shell getprop ro.build.type
adb shell getprop ro.debuggable
adb shell su 0 id
adb shell ls -l /system/xbin/su /system/bin/su
adb install -r bin/pack/AndroidTest.apk > /dev/null
adb logcat -c
adb shell am start -W -n org.helder.androidtest/android.app.NativeActivity
sleep 8
for i in 1 2 3 4 5 6 7 8 9 10; do
	adb shell input swipe 270 1200 810 1200 60
	sleep 2
done
# (evdev: each multi-touch device's name, then a swipe on _1)
for d in $(adb shell getevent -pl 2>/dev/null | tr -d '\r' | awk '/^add device/ {d = $NF} /name:.*multi_touch_1"/ {print d}'); do
	echo "fling-diag: device $d"
	for i in 1 2 3 4 5; do
		adb shell su 0 sh -c "'sendevent $d 3 47 0; sendevent $d 3 57 9; sendevent $d 3 53 8191; sendevent $d 3 54 16383; sendevent $d 3 58 512; sendevent $d 1 330 1; sendevent $d 0 0 0; sleep 0.016; sendevent $d 3 53 12287; sendevent $d 0 0 0; sleep 0.016; sendevent $d 3 53 16383; sendevent $d 0 0 0; sleep 0.016; sendevent $d 3 53 20479; sendevent $d 0 0 0; sleep 0.016; sendevent $d 3 53 24575; sendevent $d 0 0 0; sendevent $d 3 57 -1; sendevent $d 1 330 0; sendevent $d 0 0 0'"
		sleep 2
	done
done
adb logcat -d -s hxmc:I | grep "AndroidTest: \(diag P\|diag rel\|event P\|let go\)" | sed 's/  *[0-9]* *[0-9]* I hxmc    : AndroidTest://'
