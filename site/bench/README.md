# Benchmarks

How the numbers on the website were measured, and how to reproduce them.
Every timing counts only if the output matches the reference compiler's:
same HXB members with byte-identical payloads, or identical output files.

## Runners: the compiler built for each target (`run.py`, the Benchmarks section)

`run.py` times the reference and the port, built for HashLink, HL/C, JS, JVM,
C++, hxc and wasm, compiling three workloads to HXB (results: `results.json`).

Wall-clock time of the pinned reference compiler (native OCaml) vs. the
translated compiler (`haxe.Main`) built for different Haxe targets. Every run
compiles a workload to HXB with `-D disable-parallelism`. A runner's timing
only counts if its archive matches the reference: same members and
byte-identical `.hxb` payloads.

```sh
make -C haxe haxe
HAXE=haxe/haxe sh site/bench/build.sh js hl jvm   # needs hxnodejs, hxjava
# C++ needs hxcpp from git with site/bench/patches/hxcpp-single-thread-mark.patch:
CPP_FLAGS="-D HXCPP_SINGLE_THREAD_MARK" sh site/bench/build.sh cpp
# HL/C needs a compiler with site/bench/patches/hl2c-virtual-field-cast.patch and HashLink headers:
HAXE_HLC=/path/to/patched/haxe HL_INCLUDE=/path/to/hashlink/src sh site/bench/build.sh hlc
# with site/bench/patches/libhl-allocator.patch applied to HashLink (built with -ftls-model=initial-exec):
HL_STATIC="libhl.a fmt.o dxt.o sha1.o" sh site/bench/build.sh hlc   # static link
# the HashLink JIT loads libhl.so: point it at the patched build
LD_LIBRARY_PATH=/path/to/patched/hashlink HAXE_REFERENCE=haxe/haxe python3 site/bench/run.py -n 7
```

## Target generators (`targets.py`, the Target generators section)

```sh
python3 site/bench/targets.py -n 3 --json site/bench/targets-results.json
```

Both compilers build haxe-formatter (with its libraries, from `haxebench.py`'s
checkout) and the port's own source for every target, in the same directory,
with `-D disable-parallelism`; CPU is user + system time, best of 3, and every
output file is compared. C++ and HL/C stop at the generated sources.

## HaxeBenchmarks: hxc against the fast targets (2026-10-11)

`python3 site/bench/haxebench.py [-n RUNS] [-t targets] [-c cases] [--clean] [--json out]`
builds and runs the cases of
[HaxeBenchmarks/benchmark-runner](https://github.com/HaxeBenchmarks/benchmark-runner)
(cloned into `bin/haxebench`, with crypto and the formatter's libraries at
the revisions the runner pins) on hxc and the other targets, with the pinned
`haxe/haxe`. hxc builds use the native backend tool (`hxc/tools/dev-tool.sh`:
the lowering no longer goes through Node). Wall time in seconds, best of 3,
clean builds, 4 cores; bold: the fastest. hxcpp is 4.3.0 from git, HL/C uses
HashLink master (2.0.0, 3b7bd74) with `gcc -O2`, the HL JIT the same
build, JVM is OpenJDK 21, JS is Node 22 with hxnodejs.

| case | hxc before | hxc (clang) | hxc (tcc) | hxcpp | HL/C | HL JIT | JVM | JS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| alloc | 1.17 | 1.80 | **1.37** | 1.71 | 2.48 | 2.52 | 2.03 | 12.08 |
| bcrypt | 2.53 | 2.59 (2.46 with unchecked Vector reads) | 10.26 | **2.41** | 3.56 | 5.01 | 2.55 | 2.97 |
| binarytrees | 1.22 | 0.76 | 1.99 | 0.81 | 4.15 | 4.36 | **0.67** | 1.30 |
| json | broken | 0.42 | 1.03 | 0.58 | 1.37 | 1.52 | 0.54 | **0.30** |
| mandelbrot | 1.52 | **0.50** | 3.37 | 1.36 | 22.78 | 23.68 | 1.08 | 0.90 |
| mandelbrot_anon | 1.52 | 0.95 | 4.95 | 8.08 | 32.79 | 34.21 | 1.12 | **0.89** |
| nbody | 0.92 | 0.75 | 2.77 | **0.72** | 1.14 | 1.58 | 0.81 | 0.92 |
| sha256 | 0.22 | 0.21 | 0.64 | 0.23 | 0.34 | 0.65 | **0.16** | 0.26 |
| sha512 | 0.17 | 0.13 (0.018 with native Int64) | 0.54 | **0.03** | 0.05 | 0.08 | 0.13 | 0.32 |
| formatter_noio | 6.48 | **5.07** | 12.63 | crashes | 16.52 | 17.18 | 5.18 | 17.35 |

"Before" is hxc at the start of this work (bcrypt, sha512 and formatter_noio:
the first measurement, after the first changes; the earlier harness rounded
to about 50 ms). Build time (s) of a few, clean:

| case | hxc (clang) | hxc (tcc) | hxcpp | HL/C | JVM |
| --- | --- | --- | --- | --- | --- |
| alloc | 0.9 | 0.2 | 33.2 | 2.9 | 0.5 |
| nbody | 0.9 | 0.2 | 31.3 | 3.0 | 0.5 |
| json | 1.0 | 0.2 | 37.7 | 3.1 | 0.5 |
| formatter_noio | 5.0 | 1.1 | crashes | 14.8 | 1.3 |

What changed, by case:

- mandelbrot (1.52 → 0.50): the `Math` natives are inline (`sqrt` is one
  instruction), and calls to functions that never reach a GC point
  (`EmitC.findNoGc`: the constructors here) are not GC points, so the
  objects stay in registers instead of shadow-stack slots.
- mandelbrot_anon (1.52 → 0.95): structural reads check the literal layout
  of the static type first (one type-index compare, a constant slot).
- json (failed → 0.42): `StringTools.isEof` tested `#if hxc`, which a custom
  target does not define (it defines `target.name`), so the parser read past
  the end; then field names added at run time by hash instead of a linear
  `strcmp` scan (31% of the time), field-name strings made once, an inline
  `StringBuf.addChar` fast path.
- binarytrees (1.22 → 0.76): the nursery doubles (to 32 MB) while much of it
  survives each minor collection: the tree being built was copied at every
  one.
- formatter_noio (6.48 → 5.07, the JVM's 5.18): the regex engine skips start
  positions a match cannot begin at, tries anchored patterns once and caches
  parsed patterns; `Array.concat` in one copy; `indexOf` by first unit.
- everywhere: cold sites (the references live across an allocation or array
  store are stored in the shadow stack only on its slow path) and frames
  without zeroing (the collector zeroes the slots above the stack top).

The self-compile: 5.2 s → about 4.9–5.0 s CPU (same HXB output; peak RSS
455 → 468 MB).

Later the same day: `haxe.Int64` is native on hxc (`hxc.I64`, an `int64_t`;
it was a class of two Ints, so every operation allocated) and reads through
`haxe.ds.Vector` skip the bounds check: sha512 0.13 → **0.018** s (hxcpp
0.025), bcrypt 2.59 → 2.46 s (hxcpp 2.41).

Not done: alloc keeps up to 500 MB live and varies between 1.2 and 2.2 s
with when the copying major collections happen. hxcpp crashes on
formatter_noio (the case's own comment says so). hxc's
`EReg.replace`/`split` differ from Eval (PCRE) around zero-width matches
(`(?=b)` with `g`, splitting `""`), as before these changes.

## Refresh after OS threads and the memory work (2026-10-09, night)

`site/bench/run.py -n 3 --json site/bench/results.json reference hxc hxc-o2 hxc-clang hxc-cosmo`
(load 1-1.4; the other runners' entries are from the earlier runs). Self-compile, CPU min of 3:
reference 5.95 s / 539 MB, hxc clang -O2 5.19 s / 456 MB, gcc -O2 5.22 s / 454 MB,
tcc 13.2 s / 464 MB, **cosmocc 8.25 s / 447 MB**.

The cosmocc build regressed (it was on par with the reference, 5.05 s, before
the memory and threads work): on the older snapshot workload it takes 6.5 s
against 4.4 s for clang/gcc. Not the thread model (an `-DRT_GREEN_THREADS`
cosmocc build is as slow) and not the GC (RT_STATS: 0.74 s vs 0.61 s of GC
time); the extra time is in the mutator code cosmocc generates. To investigate.

## hxc OS threads: sequential cost and parallel mode (2026-10-09, late)

`self` (a snapshot of `src`), clang -O2 builds, minimum of 3 runs per
round; 4-core Xeon @ 2.10 GHz, load 1.0–1.4 (one other job). "Before" is
commit 54799e3 (green threads only), "after" 66d8f9d (1:1 OS threads,
thread-local runtime state, safepoints). Parallel mode is the compiler
without `-D disable-parallelism`; the port's pool has
`NUMBER_OF_PROCESSORS` − 1 workers besides the calling thread, the
reference uses its default domain count (4). Every archive matched the
sequential reference after normalizing variable IDs (test/TESTING.md).

| Run | wall | CPU | peak RSS |
| --- | ---: | ---: | ---: |
| before, sequential (2 rounds) | 5.21 / 5.19 s | 5.16 / 5.15 s | 454 MB |
| after, sequential (2 rounds) | 5.20 / 5.21 s | 5.16 / 5.16 s | 469 MB |
| after, parallel, 1 thread | 5.33 s | 5.27 s | 469 MB |
| after, parallel, 2 threads | 4.52 s | 5.53 s | 501 MB |
| after, parallel, 4 threads | 4.18 s | 5.91 s | 536 MB |
| reference, sequential | 6.11 s | 6.03 s | 531 MB |
| reference, parallel (4 domains) | 4.03 s | 6.72 s | 592 MB |

- No sequential regression: the thread-local variables use the local-exec
  TLS model (one `%fs`-relative access, like a global), and with one thread
  a TLAB is the whole nursery. stdlib 0.20 → 0.21 s, hello 0.12 → 0.12 s.
  (The "after" binary also links mbedtls and libuv; "before" does not.)
- Parallel mode saves 20% wall time with 4 threads (the reference: 34%):
  only the filters, analyzer, DCE marking and HXB writing are parallel,
  typing is not. The port in parallel mode is within 4% of the reference in
  parallel mode, and 32% faster than the reference sequentially.

## A real program: haxe-formatter built with hxc (2026-10-09)

[haxe-formatter](https://github.com/haxecheckstyle/haxe-formatter) (pinned in
`site/bench/formatter.sh`) built with the hxc haxelib package and, for comparison,
by the reference compiler for its other targets; formatting upstream's
`haxe/std` (2583 files, 14 MB) in place with `hxformat.json`, CPU time min of 3
(load 1-2):

| Build | CPU | wall | peak RSS | output |
| --- | ---: | ---: | ---: | --- |
| hxc, gcc -O2 | 3.65 s | 3.67 s | | identical |
| hxc, clang -O2 | 3.81 s | 3.85 s | 183 MB | reference for the others |
| C++ (hxcpp) | 6.34 s | 6.00 s | 212 MB | identical |
| JS (Node 22) | 9.12 s | 6.15 s | 124 MB | identical |
| hxc, tcc | 8.16 s | 8.29 s | 184 MB | identical |
| HL/C | 8.58 s | 7.04 s | | identical |
| HashLink JIT | — | — | | crashes (SIGSEGV in stock `hl`) |

hxc's optimized builds format 1.6× faster than C++ and Node and 2.3× faster
than HL/C (CPU), with byte-identical output. Building it exposed and fixed
three hxc bugs: `Exception.caught/thrown` removed by `-dce full`,
`StringTools.isEof`, and `String.split` holding the delimiter across an
allocation (a moving-GC bug).

## hxc memory: below the OCaml compiler's peak RSS (2026-10-09, night)

Peak RSS and CPU time (user + system), minimum of 3–5 interleaved runs,
`-D disable-parallelism --interp --no-output --hxb`; `self` compiles a
snapshot of `src`; every archive byte-identical to the reference. Before:
commit d2bbaad; after: 4dc6b64 (details in hxc/README.md, "Memory").
The machine was slower than in the sections below (the reference took
5.7–5.9 s for `self`).

| Workload | reference | hxc-o2 before | hxc-o2 after | hxc (tcc) after |
| --- | ---: | ---: | ---: | ---: |
| hello | 0.12 s / 39 MB | 0.11 s / 51 MB | 0.10 s / 32 MB | 0.26 s / 39 MB |
| stdlib | 0.24 s / 53 MB | 0.23 s / 51 MB | 0.22 s / 42 MB | 0.55 s / 49 MB |
| self | 5.78 s / 531 MB | 5.72 s / 837 MB | 4.98 s / 467 MB | 12.4 s / 477 MB |

`RT_CENSUS=1` (heap census at exit, after a major collection) on `self`:

| | before | after |
| --- | ---: | ---: |
| live heap | 214 MB, 6.82M objects | 170 MB, 6.53M objects |
| same data in OCaml's representation (estimate) | 154 MB | 142 MB |
| enum values (2.0M) | 54 MB (a tag slot each) | 39 MB |
| `core.Pos` (753k) | 23 MB (32 B) | 17 MB (24 B, Int fields packed) |
| arrays (946k, 511k of them empty) | 29 + 22 MB data (32 B headers, slack 9 MB) | 22 + 16 MB (24 B, slack 3 MB) |
| strings | 410k, 13.6 MB (32.8k distinct) | 120k, 5.5 MB |
| remembered set (malloc) | 16 MB (128 MB with a 16 MB nursery) | 0.2 MB |

What it was, in order of effect on the peak:

- **GC memory policy** (837 → 565 MB, and −0.8 s): the from-space of the
  copying major collection stayed resident and the to-space was faulted in
  up to the from-space's size; both are now returned or faulted in on
  demand. `Array.insert` at the front of large arrays (the port's
  translation of `x :: l`) re-recorded every young element in the
  remembered set at each call (700M slot checks, 16M entries); a long
  range now remembers the object once.
- **Representation** (565 → 467 MB): no enum tag slot, no array capacity
  slot, exact array literals and growth from 2, Int/Bool fields packed two
  per slot, identifiers interned per file by the lexer.
- Not kept: a GC that deduplicates promoted strings (−3 MB more live) breaks
  HXB conformance, because string identity is observable in the port
  (`StrTools.physNeq`); a larger nursery (8 MB: −14 MB on `self`, +8 MB on
  hello and stdlib); a different old-space limit (128 MB first / 2.5× live
  instead of 256 MB / 3×: 436 MB on `self`, tuned to one workload).

With a copying old generation the peak is at least the old space at a
major collection plus what survives it. Simulated with an experimental
limit factor (old space limit = f × live after a major; not committed):

| f | majors | major time | peak RSS (copying) | old space before a major (≈ peak in place) |
| ---: | ---: | ---: | ---: | ---: |
| 3 (default) | 1 | 0.26 s | 467 MB | 415 MB (at exit) |
| 2 | 2 | 0.49 s | 562 MB | 360 MB |
| 1.5 | 3 | 0.73 s | 476 MB | 275 MB |

A mark-sweep or mark-compact old generation (planned after the OS threads
work) would bring the peak down to the last column plus the nursery and
binary (~30 MB): about 390 MB at f = 2 or 305 MB at f = 1.5, for 0.25–0.5 s
more collection time if marking costs what copying does.
