#!/bin/sh
# A swipe on the device's touchscreen as its own events (written to its
# input device as sendevent does: the kernel's timestamps, read by Android's
# InputReader as a finger's), from x0,y0 to x1,y1 (the display's pixels) in
# about ms, a move each 16 ms, lifted where it last moved.
#   sh tests/os/android-swipe.sh x0 y0 x1 y1 ms
set -u
x0=$1
y0=$2
x1=$3
y1=$4
ms=$5
info=$(adb shell getevent -lp 2>/dev/null | tr -d '\r')
# (the first device with a finger's two axes: its node, their ranges, what else it reports)
dev=$(printf '%s\n' "$info" | awk '
	/^add device/ { if (d != "" && x != "" && y != "") exit; d = $NF; x = ""; y = "" }
	/ABS_MT_POSITION_X/ { x = 1 }
	/ABS_MT_POSITION_Y/ { y = 1 }
	END { if (x != "" && y != "") print d }')
if [ -z "$dev" ]; then
	echo "android-swipe.sh: no touchscreen among the input devices:"
	printf '%s\n' "$info"
	exit 1
fi
block=$(printf '%s\n' "$info" | awk -v d="$dev" '/^add device/ { on = ($NF == d) } on')
range() {
	printf '%s\n' "$block" | grep "$1 " | head -1 | sed 's/.*min \(-*[0-9]*\), max \(-*[0-9]*\).*/\1 \2/'
}
set -- $(range ABS_MT_POSITION_X)
xmin=$1
xmax=$2
set -- $(range ABS_MT_POSITION_Y)
ymin=$1
ymax=$2
size=$(adb shell wm size | grep -o "[0-9]*x[0-9]*" | tail -1)
W=${size%x*}
H=${size#*x}
# (a pixel's raw value: TouchInputMapper scales the axis's min..max + 1 to the display)
rx() { echo $((xmin + $1 * (xmax - xmin + 1) / W)); }
ry() { echo $((ymin + $1 * (ymax - ymin + 1) / H)); }
extra=""
printf '%s\n' "$block" | grep -q "ABS_MT_PRESSURE " && { set -- $(range ABS_MT_PRESSURE); extra="$extra sendevent $dev 3 58 $(($2 / 2));"; }
printf '%s\n' "$block" | grep -q "ABS_MT_TOUCH_MAJOR " && { set -- $(range ABS_MT_TOUCH_MAJOR); m=$2; [ "$m" -gt 1000 ] && m=1000; extra="$extra sendevent $dev 3 48 $((m / 4));"; }
key=""
printf '%s\n' "$block" | grep -q "BTN_TOUCH" && key=1
n=$((ms / 16))
[ $n -lt 1 ] && n=1
echo "android-swipe.sh: $dev (x $xmin..$xmax, y $ymin..$ymax; ${W}x$H), $n moves"
# (EV_ABS 3: ABS_MT_SLOT 47, _TRACKING_ID 57, _POSITION_X 53, _Y 54; EV_KEY 1: BTN_TOUCH 330; EV_SYN 0)
script="sendevent $dev 3 47 0; sendevent $dev 3 57 7; sendevent $dev 3 53 $(rx $x0); sendevent $dev 3 54 $(ry $y0);$extra"
[ -n "$key" ] && script="$script sendevent $dev 1 330 1;"
script="$script sendevent $dev 0 0 0;"
i=1
while [ $i -le $n ]; do
	script="$script sleep 0.016; sendevent $dev 3 53 $(rx $((x0 + (x1 - x0) * i / n))); sendevent $dev 3 54 $(ry $((y0 + (y1 - y0) * i / n))); sendevent $dev 0 0 0;"
	i=$((i + 1))
done
script="$script sendevent $dev 3 57 -1;"
[ -n "$key" ] && script="$script sendevent $dev 1 330 0;"
script="$script sendevent $dev 0 0 0"
adb shell "$script"
