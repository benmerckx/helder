#!/bin/sh
# The triangle (packages/gfx/examples/Triangle.hx) against triangle.png
# (GfxTest.hx), headless, then in a window. Linux: on Mesa's llvmpipe, an EGL
# pbuffer, then an X11 window under Xvfb (needs libEGL, Mesa's drivers, Xvfb
# and xvfb-run). macOS: Metal, an offscreen texture (skipped without a Metal
# device: GfxTest exits with 3), then a Cocoa window (skipped outside a GUI
# session, which has no window server).
#   sh packages/gfx/test/check.sh <dir with GfxTest> [out dir]
set -e
bin=$1
out=${2:-$1}
here=$(dirname "$0")
if [ "$(uname -s)" = Darwin ]; then
	code=0
	"$bin/GfxTest" headless "$here/triangle.png" "$out/headless.png" || code=$?
	[ $code = 3 ] && exit 0
	[ $code = 0 ] || exit $code
	if [ "$(launchctl managername 2>/dev/null)" != Aqua ]; then
		echo "check.sh: not a GUI session (launchctl managername: $(launchctl managername 2>/dev/null)): no window test"
		exit 0
	fi
	"$bin/GfxTest" window "$here/triangle.png" "$out/window.png" 5
	exit 0
fi
export LIBGL_ALWAYS_SOFTWARE=1
env -u DISPLAY "$bin/GfxTest" headless "$here/triangle.png" "$out/headless.png"
xvfb-run -a -s "-screen 0 640x480x24" "$bin/GfxTest" window "$here/triangle.png" "$out/window.png" 5
