#!/bin/sh
# Builds the static website (playground + download) into bin/site, ready for
# any static host (Cloudflare Pages: every file stays below 25 MiB).
#
#   sh site/build.sh
#
# Needs: what backend/build.sh port needs (node, haxe/haxe), Emscripten (emcc
# on PATH, e.g. `. ~/emsdk/emsdk_env.sh`) and cosmocc on PATH (bench/COSMO.md).
# SKIP_PORT=1 reuses bin/backend/hih/prog.c; SKIP_COM=1 skips the APE binary;
# NO_DEPS=1 builds it without mbedtls and libuv.
set -eu
cd "$(dirname "$0")/.."
OUT=bin/site
B=bin/site-build
mkdir -p "$OUT" "$B/obj"

# 1. the port as C
[ -n "${SKIP_PORT:-}" ] || sh backend/build.sh port
C=bin/backend/hih/prog.c

# 2. the standard library subset the compiler needs for --interp, macros and HXB
rm -rf "$B/std"
mkdir -p "$B/std"
cp haxe/std/*.hx "$B/std/"
cp -r haxe/std/haxe haxe/std/sys haxe/std/eval "$B/std/"

# 3. WebAssembly. Compiled as C++ so RT_TRY is a native try/catch (wasm
# exception handling): Emscripten's setjmp lowering multiplies the code of
# functions with many try blocks past V8's 7.6 MB function size limit.
# wasm64: the runtime lays objects out in 8-byte slots holding 64-bit pointers
F="-O2 -w -fno-strict-aliasing -fwasm-exceptions -sMEMORY64=1 -I backend/rt"
if [ ! "$B/obj/prog.o" -nt "$C" ]; then em++ -x c++ $F -c "$C" -o "$B/obj/prog.o"; fi
# the runtime; sockets, mbedtls and libuv are stubs that throw when called
RT="rt rt_dyn rt_std rt_str rt_sys rt_net rt_ssl rt_uv rt_thread rt_census"
for f in $RT; do em++ -x c++ $F -DHXC_NO_NET -DHXC_NO_SSL -DHXC_NO_UV -c "backend/rt/$f.c" -o "$B/obj/$f.o"; done
em++ $F -o "$OUT/hih.js" "$B/obj/prog.o" $(for f in $RT; do echo "$B/obj/$f.o"; done) \
	-sMODULARIZE=1 -sEXPORT_NAME=createHih -sENVIRONMENT=web,worker,node \
	-sEXIT_RUNTIME=1 -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=64MB -sMAXIMUM_MEMORY=8GB -sSTACK_SIZE=8MB \
	-sFORCE_FILESYSTEM=1 -sEXPORTED_RUNTIME_METHODS=callMain,FS,ENV \
	--preload-file "$B/std@/lib/haxe/std"

# 4. the portable binary, with the std subset in its own zip (rt.c: /zip/std).
# sys.ssl and eval.luv use mbedtls and libuv built with cosmocc
# (backend/tools/cosmo-deps.sh); NO_DEPS=1 builds stubs that throw instead
if [ -z "${SKIP_COM:-}" ]; then
	DEPS=${COSMO_DEPS:-bin/cosmo-deps}
	if [ -z "${NO_DEPS:-}" ]; then
		sh backend/tools/cosmo-deps.sh "$DEPS"
		DEP_FLAGS="-I$DEPS/include"
		DEP_LIBS="-L$DEPS/lib -lmbedtls -lmbedx509 -lmbedcrypto -luv"
	else
		DEP_FLAGS="-DHXC_NO_SSL -DHXC_NO_UV"
		DEP_LIBS=
	fi
	if [ ! "$B/hih.com" -nt "$C" ] || [ "$(cat "$B/hih.com.deps" 2>/dev/null)" != "$DEP_FLAGS" ]; then
		cosmocc -O2 -w -fno-strict-aliasing $DEP_FLAGS -I backend/rt "$C" $(for f in $RT; do echo "backend/rt/$f.c"; done) -lm $DEP_LIBS -o "$B/hih.com"
		echo "$DEP_FLAGS" > "$B/hih.com.deps"
	fi
	cp "$B/hih.com" "$OUT/haxe-in-haxe.com"
	(cd "$B" && zip -qr -9 "../../$OUT/haxe-in-haxe.com" std)
fi

# 5. pages and build facts
cp site/index.html site/style.css site/playground.js site/worker.js site/bench.js "$OUT/"
# benchmark results (bench/run.py --json bench/results.json) for the Benchmarks section
cp bench/results.json "$OUT/bench.json"
rm -rf "$OUT/examples" && cp -r site/examples "$OUT/examples"
mb() { echo "$1" | awk '{printf "%.1f MB", $1 / 1048576}'; }
size() { stat -c %s "$1"; }
gz() { gzip -9c "$1" | wc -c; }
cat > "$OUT/build-info.json" <<EOF
{
	"date": "$(date -u +%Y-%m-%d)",
	"commit": "$(git rev-parse --short HEAD)",
	"wasmSize": "$(mb "$(size "$OUT/hih.wasm")")",
	"wasmGz": "$(mb "$(gz "$OUT/hih.wasm")")",
	"dataGz": "$(mb "$(gz "$OUT/hih.data")")",
	"comSize": "$( [ -f "$OUT/haxe-in-haxe.com" ] && mb "$(size "$OUT/haxe-in-haxe.com")" || echo "-")"
}
EOF
cat "$OUT/build-info.json"
ls -l "$OUT"
