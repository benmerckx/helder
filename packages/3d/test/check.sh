#!/bin/sh
# packages/3d's frames (Scenes.hx) against <scene>.png, headless (RenderTest:
# Linux on Mesa's llvmpipe through an EGL pbuffer; macOS on Metal, skipped
# without a device; Windows on D3D11's WARP), as packages/gfx/test/check.sh.
#   sh packages/3d/test/check.sh <dir with RenderTest> [out dir]
set -e
bin=$1
out=${2:-$1}
here=$(dirname "$0")
export LIBGL_ALWAYS_SOFTWARE=1 HXMC_GFX_SOFTWARE=1
for s in gltf orbits shadows physics instances skin overlay textured packed spot sky; do
	g=$s
	# (the packed sample draws the glTF one's frame)
	[ $s = packed ] && g=gltf
	if [ -f "$bin/RenderTest.exe" ]; then
		"$bin/RenderTest.exe" $s "$here/$g.png" "$out/$s.png"
	else
		env -u DISPLAY "$bin/RenderTest" $s "$here/$g.png" "$out/$s.png"
	fi
done
