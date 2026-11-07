#!/bin/sh
# xvfb-run, returning once its X server is gone. xvfb-run kills its Xvfb and
# returns without waiting for it: the server's lock (/tmp/.X99-lock) is often
# still there when it returns, so the next xvfb-run -a, a few hundred ms on,
# took :99 again while the last one was letting go of it, and its client got
# no display (the viewer-window lane's AT-SPI step: "cannot open the X
# display (DISPLAY=:99)", the probe then waiting 40 s for an application
# that had died). This waits (at most 10 s) for every lock the run made to
# be removed, the server's last act, its sockets closed before it.
#   sh tests/xvfb-run.sh [xvfb-run's options] <command...>
before=" $(ls /tmp/.X*-lock 2>/dev/null | tr '\n' ' ') "
xvfb-run "$@"
s=$?
i=0
while [ $i -lt 100 ]; do
	left=""
	for f in /tmp/.X*-lock; do
		[ -e "$f" ] || continue
		case "$before" in *" $f "*) ;; *) left=$f ;; esac
	done
	[ -z "$left" ] && break
	sleep 0.1
	i=$((i + 1))
done
exit $s
