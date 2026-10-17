#!/bin/sh
# The examples (packages/gfx/examples: Triangle.hx, Cube.hx, Instances.hx)
# against triangle.png, cube.png and instances.png (GfxTest.hx), headless,
# then in a window. Linux: on Mesa's llvmpipe, an EGL pbuffer, then an X11 window under Xvfb (needs
# libEGL, Mesa's drivers, Xvfb and xvfb-run). macOS: Metal, an offscreen
# texture (skipped without a Metal device: GfxTest exits with 3), then a
# Cocoa window (skipped outside a GUI session, which has no window server).
# Windows (GfxTest.exe): D3D11 on WARP, an offscreen texture, then a Win32
# window; on Linux, under Wine (WINE, by default /usr/lib/wine/wine64:
# wined3d over Mesa's llvmpipe, under Xvfb).
#   sh packages/gfx/test/check.sh <dir with GfxTest> [out dir]
set -e
bin=$1
out=${2:-$1}
here=$(dirname "$0")
if [ -f "$bin/GfxTest.exe" ]; then
	export HXMC_GFX_SOFTWARE=1
	case "$(uname -s)" in
	MINGW* | MSYS* | CYGWIN*) run() { "$@"; } ;;
	*)
		export LIBGL_ALWAYS_SOFTWARE=1 WINEDEBUG=-all
		run() { xvfb-run -a -s "-screen 0 640x480x24" "${WINE:-/usr/lib/wine/wine64}" "$@"; }
		;;
	esac
	for s in triangle cube instances; do
		run "$bin/GfxTest.exe" headless $s "$here/$s.png" "$out/$s-headless.png"
		run "$bin/GfxTest.exe" window $s "$here/$s.png" "$out/$s-window.png" 5
	done
	exit 0
fi
if [ "$(uname -s)" = Darwin ]; then
	for s in triangle cube instances; do
		code=0
		"$bin/GfxTest" headless $s "$here/$s.png" "$out/$s-headless.png" || code=$?
		[ $code = 3 ] && exit 0
		[ $code = 0 ] || exit $code
	done
	if [ "$(launchctl managername 2>/dev/null)" != Aqua ]; then
		echo "check.sh: not a GUI session (launchctl managername: $(launchctl managername 2>/dev/null)): no window test"
		exit 0
	fi
	for s in triangle cube instances; do
		"$bin/GfxTest" window $s "$here/$s.png" "$out/$s-window.png" 5
	done
	exit 0
fi
export LIBGL_ALWAYS_SOFTWARE=1
for s in triangle cube instances; do
	env -u DISPLAY "$bin/GfxTest" headless $s "$here/$s.png" "$out/$s-headless.png"
	xvfb-run -a -s "-screen 0 640x480x24" "$bin/GfxTest" window $s "$here/$s.png" "$out/$s-window.png" 5
done
