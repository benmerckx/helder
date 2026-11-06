#!/bin/sh
# (temporary diagnostics) the viewer-window lane's AT-SPI step, repeated: when the probe fails, what the viewer was doing
exe=apps/viewer/bin/linux-x86_64/viewer
for i in 1 2 3 4 5 6 7 8 9 10; do
	xvfb-run -a dbus-run-session -- sh -c '
		start=$(date +%s.%N)
		strace -f -tt -o /tmp/vs.'$i' -e trace=connect,sendmsg,recvmsg,poll,ppoll,read,write,futex,nanosleep,clock_nanosleep '$exe' --new --exit-after 30 "apps/viewer/tests/fixtures/folder/photo 2.jpg" > /tmp/vout.'$i' 2>&1 & p=$!
		bin/ui/linux-x86_64/AtspiProbe "photo 2" "image:photo 2.jpg · 5 / 6 · 1242×1048" "menu item:File" "menu item:View" > /tmp/pout.'$i' 2>&1; s=$?
		echo "viewer-diag '$i': probe exit $s after $(echo "$(date +%s.%N) - $start" | bc) s"
		if [ $s != 0 ]; then
			cat /tmp/pout.'$i'
			for t in /proc/$(pgrep -f "^'$exe'" | head -1)/task/*; do echo "$t $(cat $t/comm) $(cat $t/wchan) $(cat $t/stat | cut -d" " -f3)"; done
			pgrep -af viewer
			sudo gdb -batch -p $(pgrep -f "^'$exe'" | head -1) -ex "thread apply all bt 12" 2>&1 | grep -v "^\[New\|^warning" | head -80
		fi
		kill $p; sleep 1
		echo "viewer-diag '$i': viewer said:"; cat /tmp/vout.'$i'
		if [ $s != 0 ]; then echo "viewer-diag '$i': strace head"; head -60 /tmp/vs.'$i'; echo "...tail"; tail -80 /tmp/vs.'$i'; fi
	'
done
