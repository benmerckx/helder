#!/bin/sh
# Builds the HL/C output of the compiler (bin/bench/hlc, from `sh site/bench/build.sh hlc`)
# to WebAssembly with Emscripten, for Node.js:
#
#   HL_SRC=/path/to/hashlink ZLIB_SRC=/path/to/zlib-1.3.x sh site/bench/build-wasm.sh
#   HAXE_STD_PATH=$PWD/haxe/std node --liftoff-only --stack-size=60000 bin/bench/wasm/hih.js ...
#
# - Stock HashLink runtime (not site/bench/patches/libhl-allocator.patch), single-threaded
#   (HL_NO_THREADS: the compiler then runs its parallel loops inline).
# - Binaryen's --spill-pointers keeps pointers held in wasm locals visible to
#   libhl's conservative stack scan.
# - Native wasm setjmp/longjmp: Emscripten's default JS-based lowering takes
#   over 30 minutes on HL/C's large functions.
# - Of HashLink's fmt library only the zlib and digest primitives are used;
#   they are cut out of libs/fmt/fmt.c (the rest needs png/jpeg/vorbis).
# - Run with --liftoff-only: V8's optimizing tier spends ~20s on the large
#   functions and the program waits for it.
set -eu
cd "$(dirname "$0")/../.."
: "${HL_SRC:?HashLink source directory}" "${ZLIB_SRC:?zlib source directory}"
OUT=bin/bench/wasm
mkdir -p "$OUT/obj"
F="-O2 -std=c11 -w -DHL_NO_THREADS -fwasm-exceptions -sSUPPORT_LONGJMP=wasm -I $HL_SRC/src"
PCRE="-DPCRE2_CODE_UNIT_WIDTH=16 -DHAVE_CONFIG_H -I $HL_SRC/include/pcre -I $HL_SRC/include"

for f in "$HL_SRC"/src/gc.c "$HL_SRC"/src/std/*.c "$HL_SRC"/include/pcre/pcre2_*.c; do
	b=$(basename "$f" .c)
	case $b in sys_android|pcre2_jit_test|pcre2_dftables|pcre2_printint|pcre2_fuzzsupport|pcre2_jit_match|pcre2_jit_misc|pcre2_ucptables) continue;; esac
	emcc $F $PCRE -c "$f" -o "$OUT/obj/$b.o"
done
for f in adler32 compress crc32 deflate inffast inflate inftrees trees zutil uncompr; do
	emcc -O2 -w -c "$ZLIB_SRC/$f.c" -o "$OUT/obj/z_$f.o"
done

FMT=$HL_SRC/libs/fmt/fmt.c
zstart=$(grep -n 'typedef struct _fmt_zip fmt_zip;' "$FMT" | cut -d: -f1)
zend=$(grep -n 'DEFINE_PRIM(_BOOL, deflate_buffer' "$FMT" | cut -d: -f1)
cstart=$(grep -n -- '-- CRYPTO --' "$FMT" | cut -d: -f1)
cend=$(grep -n 'DEFINE_PRIM(_VOID, digest' "$FMT" | cut -d: -f1)
{
	echo '#define HL_NAME(n) fmt_##n'
	echo '#include <hl.h>'
	echo '#include <zlib.h>'
	sed -n "${zstart},${zend}p;${cstart},${cend}p" "$FMT"
} > "$OUT/fmt_min.c"
emcc $F -I "$ZLIB_SRC" -I "$HL_SRC/libs/fmt" -c "$OUT/fmt_min.c" -o "$OUT/obj/fmt_min.o"
emcc $F -c "$HL_SRC/libs/fmt/sha1.c" -o "$OUT/obj/sha1.o"

emcc $F -I bin/bench/hlc -c bin/bench/hlc/main.c -o "$OUT/main.o"

cat > "$OUT/pre.js" <<'EOF'
// Forward the host environment (HAXE_STD_PATH etc.) to getenv.
Module.preRun = (Module.preRun || []).concat([function() { for (var k in process.env) ENV[k] = process.env[k]; }]);
EOF
# -g2 keeps the names --spill-pointers needs to find the stack pointer; stripped afterwards.
emcc -O2 -g2 "$OUT/main.o" "$OUT"/obj/*.o -fwasm-exceptions -sSUPPORT_LONGJMP=wasm \
	-sNODERAWFS=1 -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=256MB -sMAXIMUM_MEMORY=4GB -sSTACK_SIZE=64MB \
	-sBINARYEN_EXTRA_PASSES=--spill-pointers -sEXIT_RUNTIME=1 --pre-js "$OUT/pre.js" -o "$OUT/hih.js"
"$(dirname "$(command -v emcc)")/../bin/wasm-opt" --mvp-features --enable-bulk-memory --enable-bulk-memory-opt --enable-call-indirect-overlong --enable-exception-handling --enable-multivalue --enable-mutable-globals --enable-nontrapping-float-to-int --enable-reference-types --enable-sign-ext --strip-debug --strip-producers "$OUT/hih.wasm" -o "$OUT/hih.wasm"
ls -l "$OUT/hih.js" "$OUT/hih.wasm"
