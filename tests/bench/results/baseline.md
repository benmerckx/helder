# Benchmarks

tests/bench/Bench.hx (`bun run test bench`), 2026-10-27, Intel(R) Xeon(R) Processor, 4 cores.

Milliseconds per run (median, p99, max), GC heap bytes allocated per run, collections (all runs; majors), the longest time collecting in one run (natively; wasm32's collector does not time itself).

## linux-x86_64

| workload | runs | median | p99 | max | KB/run | GCs | majors | longest GC |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| text.layout.latin | 200 | 0.082 | 0.252 | 0.496 | 134.3 | 3 | 0 | 0.367 |
| text.layout.mixed | 200 | 0.076 | 0.19 | 0.573 | 125.5 | 3 | 0 | 0.448 |
| text.atlas.cold | 60 | 6.051 | 10.399 | 10.399 | 5743.4 | 21 | 0 | 1.32 |
| text.atlas.warm | 400 | 0.059 | 0.103 | 0.129 | 31.1 | 1 | 0 | 0.031 |
| ui.layout.10k | 60 | 16.323 | 41.596 | 41.596 | 12182.6 | 46 | 2 | 25.976 |
| ui.relayout | 300 | 0.007 | 0.012 | 0.066 | 0.1 | 0 | 0 | 0 |
| ui.hit | 300 | 1.033 | 1.126 | 3.177 | 56.5 | 1 | 0 | 2.123 |
| scene.world.10k | 200 | 11.55 | 16.317 | 19.833 | 0 | 0 | 0 | 0 |
| scene.world.100k | 40 | 114.99 | 145.901 | 145.901 | 0 | 0 | 0 | 0 |
| scene.cull.10k | 200 | 22.867 | 29.19 | 41.927 | 0 | 0 | 0 | 0 |
| physics.stacks | 60 | 39.636 | 40.584 | 40.584 | 9831.4 | 72 | 0 | 0.233 |
| physics.chains | 60 | 11.152 | 19.199 | 19.199 | 1337.3 | 10 | 0 | 0.14 |

## wasm32-wasi

| workload | runs | median | p99 | max | KB/run | GCs | majors | longest GC |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| text.layout.latin | 200 | 0.181 | 0.606 | 1.167 | 154.7 | 3 | 0 | - |
| text.layout.mixed | 200 | 0.127 | 0.362 | 0.972 | 145.9 | 3 | 0 | - |
| text.atlas.cold | 60 | 6.656 | 10.204 | 10.204 | 6187.4 | 11 | 1 | - |
| text.atlas.warm | 400 | 0.081 | 0.187 | 0.263 | 31.1 | 1 | 0 | - |
| ui.layout.10k | 60 | 15.51 | 31.933 | 31.933 | 12728.7 | 23 | 2 | - |
| ui.relayout | 300 | 0.01 | 0.025 | 0.035 | 0.1 | 0 | 0 | - |
| ui.hit | 300 | 1.62 | 2.104 | 9.253 | 111.1 | 1 | 0 | - |
| scene.world.10k | 200 | 21.212 | 37.42 | 37.696 | 0 | 0 | 0 | - |
| scene.world.100k (RT_OLD_MB=512) | 40 | 216.013 | 244.061 | 244.061 | 0 | 0 | 0 | - |
| scene.cull.10k | 200 | 42.375 | 58.868 | 77.606 | 0 | 0 | 0 | - |
| physics.stacks | 60 | 46.199 | 73.893 | 73.893 | 9831.4 | 72 | 0 | - |
| physics.chains | 60 | 12.691 | 13.955 | 13.955 | 1337.3 | 10 | 0 | - |

## Builds

Seconds to compile, without a compilation server: with scoped's checker (as -lib helder has it), from nothing (-D hxmc.no-module-cache) and with the module cache on disk; the same without the checker.

| program | target | size (KB) | checker | cached | no checker | cached |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Bench | linux-x86_64 | 1213 | 1.6 | 1.6 | 1 | 0.3 |
| Bench | wasm32-wasi | 904 | 1.7 | 1.7 | 1.2 | 0.5 |
| Todo | linux-x86_64 | 1991 | 2.4 | 2.4 | 1.5 | 0.6 |
| Todo | wasm32-wasi | 1479 | 2.6 | 2.6 | 1.6 | 0.9 |
| Walker | linux-x86_64 | 705 | 1.7 | 1.7 | 0.9 | 0.3 |
| Walker | wasm32-wasi | 524 | 1.7 | 1.7 | 1.1 | 0.4 |

## Notes

The baseline, before any of the core is on helder.scoped. A shared 4-core
VM, with other builds running at times: medians move by about 10% from run
to run, p99s and maxima more.

- **How the collector is read** (tests/bench/GcStats.hx): natively,
  hxmc.rt.Gc's own counters, those RT_STATS prints (the bytes each minor
  collection found in the nursery, plus the nursery's part in use; the
  seconds spent collecting, turned on for the run). wasm32's collector
  counts collections but neither bytes nor time: its bytes are the
  nursery's progress plus its size at each collection, and there is no
  pause time.
- **Where the GC heap is used**: ui's full layout (12 MB a run: 46
  collections over 60 runs, 2 major, the longest 26 ms, which is the p99's
  2.5x the median); physics (330 KB a step for 200 crates, 45 KB for 300
  linked balls); text's cold atlas (5.7 MB to rasterize every glyph of the
  paragraphs at 3 sizes and 4 offsets); text layout (about 130 KB for four
  paragraphs of 150-250 characters, mostly the Glyph objects it returns).
  A warm atlas allocates 31 KB a frame of 3000 lookups (the face's key, a
  String, made at each change of size). Relayout after a small change and
  scene's world matrices and culling allocate nothing (hxmc's struct
  Vec3, Mat4 and Quat, the world's flat arrays).
- **wasm32-wasi, scene.world.100k**: hxmc's wasm runtime crashes in a
  major collection that copies an array of tens of MB (an Array<Float>
  pushed to 8M elements: `RangeError: Maximum call stack size exceeded` in
  Heap.tryRegionAligned under Gc.majorGc; with node's --stack-size=65500 a
  segfault; at 6M it spins). The lane runs that workload again with an old
  space it fits in (RT_OLD_MB=512) and node's default stack size.
- **Compile times**: scoped's checker takes 0.8-1.3 s of these builds, and
  with it the module cache saves nothing. (Before this baseline it overflowed
  the stack on Todo's recursive typedefs and took 5.7 s of Todo's 7.1 s:
  fixed in bc3c2dc.)
