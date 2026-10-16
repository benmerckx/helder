#!/bin/sh
# The triangle (packages/gfx/examples/Triangle.hx) against triangle.png, on
# Mesa's llvmpipe: headless (an EGL pbuffer), then in an X11 window under
# Xvfb (GfxTest.hx). Needs libEGL, Mesa's drivers, Xvfb and xvfb-run.
#   sh packages/gfx/test/check.sh <dir with GfxTest> [out dir]
set -e
bin=$1
out=${2:-$1}
here=$(dirname "$0")
export LIBGL_ALWAYS_SOFTWARE=1
env -u DISPLAY "$bin/GfxTest" headless "$here/triangle.png" "$out/headless.png"
xvfb-run -a -s "-screen 0 640x480x24" "$bin/GfxTest" window "$here/triangle.png" "$out/window.png" 5
