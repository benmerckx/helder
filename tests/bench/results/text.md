# The text pilot on helder.scoped: before and after

The README's phase 3, "The core on helder.scoped": text's hot internals
first (0054f37), measured against the baseline (baseline.md, before it) by
tests/bench/Bench.hx. Text's tests pass unchanged: sample.png and
sample-cff.png pixel for pixel, ui's golden images too (todo.png exact).

## What changed

- **On helder.scoped**: a glyph the atlas lacks is drawn by `Coverage`
  (Rasterizer's algorithm, its accumulation buffer a scoped slice) from
  the outline recorded in pixels by a path kept for the next glyph;
  `FontFile.outline` reads a TrueType glyph's points (flags, x, y, contour
  ends) into scoped slices; `TextLayout`'s marks are a scoped slice.
- **Plain Haxe, for the same aim** (no GC allocation per call): `IntTable`
  for the caches read per glyph (hxmc's `IntMap.get` allocates 12-16 bytes
  on every call), the atlas's faces found again without making their
  String key, its places and boxes without Arrays or objects.

## Before and after

Medians of five alternating runs of the old and new builds (each run: the
workload's median and p99 in ms over its runs), 2026-10-27, the same VM as
the baseline. GC: KB allocated a run, collections over the runs (majors),
the longest time collecting in one run (native only).

| workload | target | median ms | p99 ms | KB/run | GCs (majors) | longest GC ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| text.layout.latin | native | 0.082 → 0.079 (-4%) | 0.187 → 0.180 | 134.3 → 116.9 | 3 → 3 | 0.38 → 0.47 |
| text.layout.mixed | native | 0.077 → 0.074 (-4%) | 0.166 → 0.160 | 125.5 → 115.5 | 3 → 3 | 0.44 → 0.39 |
| text.atlas.cold | native | 5.565 → 5.883 (+6%) | 7.420 → 6.804 | 5743.4 → 1222.1 | 21 → 6 | 1.02 → 0.57 |
| text.atlas.warm | native | 0.058 → 0.031 (-47%) | 0.102 → 0.056 | 31.1 → 0 | 1 → 0 | 0.03 → 0 |
| ui.layout.10k | native | 16.22 → 16.12 (-1%) | 39.17 → 37.55 | 12182.6 → 10751.6 | 46 (2) → 41 (1) | 23.6 → 25.4 |
| ui.hit | native | 1.029 → 1.034 (0%) | 1.298 → 1.169 | 56.5 → 56.5 | 1 → 1 | 2.05 → 1.37 |
| text.layout.latin | wasm32 | 0.111 → 0.134 (+21%) | 0.476 → 0.439 | 154.7 → 137.4 | 3 → 3 | - |
| text.layout.mixed | wasm32 | 0.128 → 0.134 (+5%) | 0.456 → 0.469 | 145.9 → 135.9 | 3 → 3 | - |
| text.atlas.cold | wasm32 | 6.707 → 9.067 (+35%) | 11.23 → 12.36 | 6187.4 → 1736.8 | 11 (1) → 5 (1) | - |
| text.atlas.warm | wasm32 | 0.080 → 0.050 (-38%) | 0.191 → 0.084 | 31.1 → 0 | 1 → 0 | - |
| ui.layout.10k | wasm32 | 16.61 → 15.16 (-9%) | 32.92 → 30.98 | 12728.7 → 11024.6 | 23 (2) → 20 (2) | - |
| ui.hit | wasm32 | 1.636 → 1.623 (-1%) | 2.089 → 2.761 | 111.1 → 111.1 | 1 → 1 | - |

A cold atlas run makes a new 1 MB atlas: 1 MB of its 1.2 MB after is the
bitmap, the rest the cache (AtlasGlyph, IntTable). Per glyph drawn, 2.2 KB
went to 0 (the Rasterizer, its buffer, the points' arrays, the box Array,
the place's object). The other workloads (scene, physics) did not change:
the full run is below.

Builds (KB; seconds from nothing, without the checker: Todo best of three
alternating builds, Walker the lane's):

| program | target | size before | after | compile before | after |
| --- | --- | ---: | ---: | ---: | ---: |
| Todo | native | 1999 | 2041 (+2.1%) | 1.56 | 1.65 (+6%) |
| Todo | wasm32 | 1479 | 1515 (+2.4%) | 1.69 | 1.75 (+4%) |
| Walker | native | 705 | 705 | 0.9 | 0.9 |
| Walker | wasm32 | 524 | 524 | 1.1 | 1.2 |

## Where the time went: scoped against reused GC buffers

The same design with the two scoped buffers (Coverage's accumulation, the
glyph's points) as GC Vectors kept for the next call, instead of scoped
slices, allocates as little and is the fastest of the three
(text.atlas.cold, medians of three runs):

| | before | scoped (committed) | reused GC buffers |
| --- | ---: | ---: | ---: |
| native | 5.57 ms, 5743 KB | 5.94 ms, 1222 KB | 5.46 ms, 1222 KB |
| wasm32 | 6.63 ms, 6187 KB | 9.15 ms, 1737 KB | 6.58 ms, 1737 KB |

Measured apart (best of 30):
- **Natively**, reading the points through slices is 10% slower than
  through Vectors (outline of 1500 glyphs: 0.85 ms, 0.94 in one scope);
  each access reloads the store's base and checks its index (a view's
  check is on its cached length; unchecked only in `for (i in 0...s.length)`).
  The accumulation buffer costs nothing over a Vector. Recording the
  outline to replay it (scoped memory cannot be held by the Outline the
  font draws into: no field, no capture) costs about 3%. Entering the first
  scope from GC code (the pool's lock, claiming a buffer) costs 33 ns.
- **On wasm32** each access also reads the buffer's pointer and length
  from scoped's table and checks the offset: the points 1.7x slower than
  Vectors (2x before 8a91769 moved the table into raw memory), the
  accumulation buffer 17%. Without the check (not committed: wasm32's
  memory safety) the points are still 1.3x.
- text.layout on wasm32 is slower with IntTable for kerning, although
  kerning alone is 1.7x faster with it (8 ms against 14, in isolation):
  not understood (V8's tiering?).

## Why the rest of text stays on the GC heap

TextLayout's output is its API: a Glyph object per glyph (72 bytes) in
Arrays per line, which is most of what it allocates (13.3 of 24 MB in the
census of text.layout.latin) and what ui's full layout allocates (389 of
687 MB, 57%: 1000 paragraphs laid out again per window width). Scoped
memory cannot hold GC references, so arrays of Glyphs cannot move, and the
Int buffers go through FontFile's public `Array<Int>` API (ligature,
context). Taking them off the heap means a new output: glyph ids,
positions and clusters in flat arrays.

## The full run after the pilot

### linux-x86_64

| workload | runs | median | p99 | max | KB/run | GCs | majors | longest GC |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| text.layout.latin | 200 | 0.078 | 0.173 | 0.46 | 116.9 | 3 | 0 | 0.358 |
| text.layout.mixed | 200 | 0.068 | 0.135 | 0.379 | 115.5 | 3 | 0 | 0.265 |
| text.atlas.cold | 60 | 5.897 | 6.771 | 6.771 | 1222.1 | 6 | 0 | 0.686 |
| text.atlas.warm | 400 | 0.031 | 0.052 | 0.094 | 0 | 0 | 0 | 0 |
| ui.layout.10k | 60 | 15.936 | 39.591 | 39.591 | 10751.6 | 41 | 1 | 25.492 |
| ui.relayout | 300 | 0.007 | 0.012 | 0.069 | 0.1 | 0 | 0 | 0 |
| ui.hit | 300 | 1.039 | 1.795 | 2.53 | 56.5 | 1 | 0 | 1.494 |
| scene.world.10k | 200 | 11.258 | 18.489 | 22.062 | 0 | 0 | 0 | 0 |
| scene.world.100k | 40 | 113.23 | 126.58 | 126.58 | 0 | 0 | 0 | 0 |
| scene.cull.10k | 200 | 22.913 | 24.695 | 28.116 | 0 | 0 | 0 | 0 |
| physics.stacks | 60 | 38.979 | 42.732 | 42.732 | 9831.4 | 72 | 0 | 0.231 |
| physics.chains | 60 | 11.023 | 12.195 | 12.195 | 1337.3 | 10 | 0 | 0.135 |

### wasm32-wasi

| workload | runs | median | p99 | max | KB/run | GCs | majors | longest GC |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| text.layout.latin | 200 | 0.133 | 1.056 | 5.986 | 137.4 | 3 | 0 | - |
| text.layout.mixed | 200 | 0.139 | 1.081 | 8.435 | 135.9 | 3 | 0 | - |
| text.atlas.cold | 60 | 8.929 | 11.472 | 11.472 | 1736.8 | 5 | 1 | - |
| text.atlas.warm | 400 | 0.05 | 0.072 | 0.549 | 0 | 0 | 0 | - |
| ui.layout.10k | 60 | 14.68 | 29.075 | 29.075 | 11024.6 | 20 | 2 | - |
| ui.relayout | 300 | 0.01 | 0.029 | 0.041 | 0.1 | 0 | 0 | - |
| ui.hit | 300 | 1.611 | 1.931 | 9.283 | 111.1 | 1 | 0 | - |
| scene.world.10k | 200 | 21.377 | 22.891 | 24.581 | 0 | 0 | 0 | - |
| scene.world.100k (RT_OLD_MB=512) | 40 | 217.055 | 277.991 | 277.991 | 0 | 0 | 0 | - |
| scene.cull.10k | 200 | 44.484 | 58.951 | 74.524 | 0 | 0 | 0 | - |
| physics.stacks | 60 | 46.02 | 76.006 | 76.006 | 9831.4 | 72 | 0 | - |
| physics.chains | 60 | 12.773 | 21.459 | 21.459 | 1337.4 | 10 | 0 | - |

### Builds

Seconds to compile, without a compilation server: with scoped's checker (as -lib helder has it), from nothing (-D hxmc.no-module-cache) and with the module cache on disk; the same without the checker.

| program | target | size (KB) | checker | cached | no checker | cached |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Bench | linux-x86_64 | 1254 | 1.6 | 1.7 | 1 | 0.7 |
| Bench | wasm32-wasi | 935 | 1.7 | 1.9 | 1.3 | 0.9 |
| Todo | linux-x86_64 | 2041 | 2.4 | 2.5 | 1.7 | 0.8 |
| Todo | wasm32-wasi | 1515 | 2.9 | 2.7 | 1.8 | 1.1 |
| Walker | linux-x86_64 | 705 | 1.7 | 1.7 | 0.9 | 0.3 |
