#!/bin/sh
# xvfb-run, returning once its X server is gone. xvfb-run kills its Xvfb and
# returns without waiting for it: the server's lock (/tmp/.X99-lock) is often
# still there when it returns, so the next xvfb-run -a, a few hundred ms on,
# took :99 again while the last one was letting go of it, and its client got
# no display (the viewer-window lane's AT-SPI step: "cannot open the X
# display (DISPLAY=:99)", the probe then waiting 40 s for an application
# that had died). This waits (at most 10 s) for every lock the run made to
# be removed, the server's last act, its sockets closed before it. On a
# failure, what Xvfb said, the X servers' locks and sockets and the
# processes are printed.
#   sh tests/xvfb-run.sh [xvfb-run's options] <command...>
before=" $(ls /tmp/.X*-lock 2>/dev/null | tr '\n' ' ') "
err=$(mktemp /tmp/xvfb-run-err.XXXXXX)
xvfb-run -e "$err" "$@"
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
if [ $s != 0 ]; then
	echo "xvfb-run.sh: exit code $s; Xvfb's output:"
	# (xkbcomp's warnings about keysyms aside)
	grep -v "Could not resolve keysym\|keymap compiler (xkbcomp) reports\|Errors from xkbcomp are not fatal" "$err" | sed 's/^/  /'
	echo "xvfb-run.sh: the locks before: $before; now:"
	for f in /tmp/.X*-lock; do [ -e "$f" ] && echo "  $f: $(tr -d ' ' < "$f")"; done
	ls -la /tmp/.X11-unix 2> /dev/null | sed 's/^/  /'
	echo "xvfb-run.sh: the processes:"
	ps -eo pid,ppid,stat,etimes,args 2> /dev/null | grep -v " ps -eo" | cut -c1-200 | sed 's/^/  /'
fi
rm -f "$err"
exit $s
