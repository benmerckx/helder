# Jobs: a 4K PNG decoded while the main thread renders

The README's phase 3, "To prototype first, and what decides it": is a
GC-free job tier needed, and if so, on `helder.scoped`'s memory or on plain
off-heap memory? Measured by tests/bench/Jobs.hx (`bun run test jobs`),
2026-10-27, @hxmc/cli 0.1.0-nightly.20261027.8e54b1e, a shared 4-core Intel
Xeon VM.

**Verdict: off-heap memory is enough.** A GC job makes the main thread's
collections wait up to 35-55 ms, so the engine needs GC-free jobs. Those
jobs run on malloc'ed memory: compared with scoped memory, the decode is
1.45x faster, the variant adds 4 KB to the program instead of 149 KB, it
builds without the checker (1.0 s instead of 1.8 s), the compiler checks
that it never touches the GC heap (`@:hxmc.unsafe`), and the pixels cross
threads as a pointer. Both give the same frames. Scoped memory has no use
left here, as for text and physics (text.md, physics.md).

## Setup

- **The image**: tests/bench/photo.mjs, 3840x2160 RGBA8. A sky gradient, a
  sun's glow, hills, value noise at four octaves and grain. Each row's
  filter is chosen as libpng chooses it, then compressed with zlib level 6
  and stored as IDAT in 64 KB chunks: 11.6 MB, 33.2 MB of pixels.
- **The frame loop** (JobsFrame.hx): 60 fps. Each frame lays out a ui of
  about 2,000 nodes in full (Bench's cards, 20 sections; its width
  changes), then makes user code's garbage, about 190 KB a frame. A 50th of
  that garbage lives on in a ring of 20,000, so the old space fills too.
  Between frames the thread sleeps, which is a safe region.
- **The decode** starts at frame 60. Statistics cover the 90 frames from
  there, and further until the pixels are back.
- **A frame's time** is its work: the frame itself, plus on the frame where
  they happen the decode (a) or the pixels' arrival (a sample of them is
  read, as an upload would, then they are freed).
- **A frame's pause** is the collector's time in that frame plus the time
  it waited for the world to stop. Both come from hxmc.rt.Gc's
  minorSecs/majorSecs and Threads' stStwSecs, read through `@:access`,
  with `Gc.stats` and `Threads.thrStats` turned on. The longest stop is
  Threads' stStwMaxUs over the run.
- **Probe**: in addition, the main thread collects (`Gc.collect(false)`) at
  the end of every frame until the pixels are back. This samples every
  phase of the job at a frame's resolution: wherever a collection lands,
  how long does it wait? "Natural": only the garbage's own collections,
  about one in 90 frames.
- **Nursery settings**: the defaults, with no RT_ variables. The nursery
  starts at 8 MB (4 MB per allocating thread) and grew to 16 MB; TLABs are
  at most 64 KB.
- **A worker thread** exists in every variant, waiting on a Lock. Once a
  second thread starts, the runtime takes its leaf locks for good.
- Five runs of each variant, each in a process of its own. Cells are
  medians, with the spread (min-max).

The variants:

| | |
| --- | --- |
| a | PngDecoder on the main thread, between two frames |
| b | a GC job: PngDecoder on the worker, allocating normally, its Bytes handed back |
| c | a GC-free job, ScopedPng: the IDAT data, the inflate's state and codes, the rows and the pixels in Slices of the job's scope, in a safe region |
| d | a GC-free job, OffHeapPng: the same steps on malloc'ed memory, every function `@:hxmc.unsafe`, in a safe region |
| c0, d0 | c and d without the safe region |

- **c and d** have the same shape. They gather the IDAT chunks and inflate
  them the way hxmc's std does (InflateImpl's Fast: a 32-bit bit buffer,
  10-bit tables, canonical counts for longer codes). The output buffer
  holds the filtered rows, unfiltered in place, so the pixels are its first
  w*h*4 bytes. They handle RGBA8 without interlacing; PngDecoder handles
  every format. All three give the same 33,177,600 bytes (`Jobs ... check`).
- **Their input** is the file in malloc'ed memory, as an I/O buffer holds
  it.
- **d's pixels** reach the main thread as a pointer, which it reads and
  frees (no copy).
- **c's pixels** are a scoped Slice, which cannot cross threads. Its
  address does: the job keeps its scope open, blocked on a Lock, until the
  main thread has read them.

## The safe region

The collector stops the world. A thread stops only at an allocation's slow
path, or is already stopped in a safe region: hxmc emits no polls in loops.

- **How Jobs.hx enters one**: the runtime's own markers,
  `hxmc.rt.C.Leaf.rt_blocking_enter()` and `rt_blocking_leave()` (class
  `Safe`). They are a public extern of the std, callable from user code
  with no `@:access`. The compiler counts them as GC points, so references
  that are live across them are spilled and read back after.
- **The rule**: between them the job allocates nothing and touches no GC
  object.
  - d's functions are `@:hxmc.unsafe`, so the compiler checks this for
    them.
  - c's are not, and cannot be. A Slice's index check throws, which is a
    GC point, so the rule holds for c by discipline, not by a check.
  - Scoped's allocation read its buffers' lengths from a GC Vector. Its
    native Store now keeps them in malloc'ed memory (Store.hx), so a Slice
    allocated inside the region touches no GC object.
  - The thread's first scope claims a buffer under a `sys.thread.Mutex`.
    That happens on entering the @:scoped job function, before the region.
- **Verified** (probe table): without the region, a collection the main
  thread asks for waits for the whole rest of the decode, 235 ms for c0
  and 176 ms for d0. With it, the longest pause is 0.29 ms for c and
  0.63 ms for d, as with no job at all (0.34 ms).

## linux-x86_64, a collection at every frame of the job

Milliseconds; GC heap KB/frame is all threads' growth over the window, by
whole allocation buffers.

| variant | frame median | p99 | max | longest pause | pauses | GCs | majors | decode | longest stop | GC heap KB/frame |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| none | 1.16 (1.1-1.27) | 1.94 (1.62-5.84) | 1.94 (1.62-5.84) | 0.34 (0.27-0.42) | 2.18 (2.04-2.38) | 90 | 0 | 0 | 0 | 254 |
| a | 1.2 (1.11-1.26) | 223.74 (219.99-246.23) | 223.74 (219.99-246.23) | 0.46 (0.37-0.48) | 0.76 (0.64-0.83) | 2 | 0 | 223.74 (219.99-246.23) | 0 | 1488 (1481-1488) |
| b | 1.27 (1.17-1.29) | 35.97 (34.62-56.04) | 35.97 (34.62-56.04) | **34.94 (33.19-54.85)** | 75.91 (65.94-95.13) | 13 (13-15) | 0 | 232.13 (218.75-245.88) | 34.91 (33.17-54.82) | 1510 (1509-1510) |
| c | 1.27 (1.23-1.34) | 3.11 (1.65-3.83) | 3.11 (1.65-3.83) | 0.29 (0.25-0.38) | 0.69 (0.64-0.78) | 16 (16-24) | 0 | 252.93 (249.72-388.26) | 0 | 225 |
| d | 1.29 (1.24-1.52) | 2.9 (2.37-3.77) | 2.9 (2.37-3.77) | 0.63 (0.45-1.15) | 1.41 (1.16-2.48) | 12 (11-21) | 0 | 181.39 (164.43-347.25) | 0 (0-14.02) | 216 (216-239) |
| c0 | 1.29 (1.26-1.32) | 236.85 (234.5-332.25) | 236.85 (234.5-332.25) | 234.74 (233.3-330.99) | 235.66 (234.4-331.85) | 3 | 0 | 251.37 (248.9-346.76) | 234.71 (233.26-330.97) | 212 |
| d0 | 1.27 (1.23-1.39) | 176.82 (159.45-185.86) | 176.82 (159.45-185.86) | 175.66 (158.29-184.83) | 176.83 (159.32-186.41) | 3 | 0 | 191.51 (173.77-200.34) | 175.62 (158.25-184.79) | 212 |

(d's one 14 ms stop was outside the window: no frame of the window paused
more than 1.15 ms.)

## linux-x86_64, collections from the garbage alone

| variant | frame median | p99 | max | longest pause | pauses | GCs | majors | decode | longest stop | GC heap KB/frame |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| none | 1.27 (1.18-1.52) | 2.33 (2.13-3.91) | 2.33 (2.13-3.91) | 0.72 (0.57-0.81) | 0.72 (0.57-0.81) | 1 | 0 | 0 | 0 | 196 (191-196) |
| a | 1.24 (1.2-1.31) | 226.69 (223.78-260.08) | 226.69 (223.78-260.08) | 0.48 (0.46-0.75) | 0.89 (0.78-1.01) | 2 | 0 | 226.69 (223.77-260.08) | 0 | 1481 (1481-1488) |
| b | 1.26 (1.18-1.28) | 2.13 (1.83-5.19) | 2.13 (1.83-5.19) | 0.43 (0.34-0.5) | 0.43 (0.34-0.5) | 1 | 0 | 232.02 (221.31-274.64) | 0 | 1500 (1489-1500) |
| c | 1.36 (1.33-1.57) | 3.17 (2.01-5.61) | 3.17 (2.01-5.61) | 0.65 (0.48-0.72) | 0.65 (0.48-0.72) | 1 | 0 | 252.29 (248.45-279.62) | 0 | 191 |
| d | 1.28 (1.23-1.42) | 4.47 (2.26-7.38) | 4.47 (2.26-7.38) | 0.6 (0.57-0.75) | 0.6 (0.57-0.75) | 1 | 0 | 167.68 (162.55-183.44) | 0 | 196 (191-196) |
| c0 | 1.31 (1.23-1.55) | 2.41 (1.9-3.61) | 2.41 (1.9-3.61) | 0.64 (0.49-1.17) | 0.64 (0.49-1.17) | 1 | 0 | 258.91 (248.79-314.69) | 0 | 191 (191-196) |
| d0 | 1.32 (1.29-1.38) | 2.82 (2.1-2.92) | 2.82 (2.1-2.92) | 0.63 (0.51-0.71) | 0.63 (0.51-0.71) | 1 | 0 | 175.87 (165.4-193.58) | 0 | 191 (191-196) |

At 190 KB a frame, a collection came about every 1.5 s, and in these runs
none landed during a decode. That is luck, not a property of the job:
the probe table shows what happens when one does.

## The job alone (the main thread waiting), five decodes in one process

| job | ms | min | max | GC heap growth (bytes) | worker's allocation (bytes) |
| --- | ---: | ---: | ---: | ---: | ---: |
| b | 240.8 | 220.7 | 266.8 | 120,408,032 | (refilled) |
| c | 240.3 | 239.1 | 256.1 | 542,296 | 0 |
| d | 168.6 | 165.2 | 186.4 | 542,296 | 0 |

- **The worker's allocation** is how far its allocation pointer moved
  during the job. It is exact while the pointer stays within one buffer: 0
  for c and d.
- **The heap growth** counts the nursery by whole TLABs. The 0.5 MB
  for c and d is the main thread's, not the job's.
- **b's 120 MB**: IDAT gathered in a BytesBuffer, the 33 MB inflate
  output and the 33 MB of pixels go straight to the old space as large
  objects.
- **Phases**, from a timed build, not part of the lane:
  - c: inflate 200 ms, unfilter 58 ms;
  - d: inflate 135 ms, unfilter 31 ms.
  - Scoped's accessors cost about 1.5x malloc'ed memory's. Marking the
    inline helpers `@:scoped` made c slower (292 ms); the macro refuses
    one with a return ("Cannot inline a not final return").
- **Fresh pages**: each run decodes into fresh memory. On this VM, first
  touching 33 MB costs 15-140 ms, against 4 ms for warm pages, so a pool
  of buffers would take most of that off every variant.

## Sizes and builds (linux-x86_64)

Each variant alone in the program (`-D jobs_only`), with the ui and without
it (`-D jobs_bare`). Builds from nothing (`-D hxmc.no-module-cache`) and
with the module cache; c's with scoped's checker, which it needs.

| variant | size (KB) | without the ui | build (s) | cached |
| --- | ---: | ---: | ---: | ---: |
| none | 995.8 | 228.2 | 0.98 | 0.43 |
| a | 1081.1 | 328.3 | 1.03 | 0.47 |
| b | 1081.1 | 328.3 | 1.00 | 0.45 |
| c | 1144.4 | 380.9 | 1.82 | 1.88 |
| d | 1000.2 | 240.6 | 1.00 | 0.45 |

- **What each adds**: PngDecoder (a, b), every format plus InflateImpl, is
  85-100 KB. ScopedPng (c) is 149-153 KB. OffHeapPng (d) is 4-12 KB.
- **Scoped's runtime alone** is 7 KB: a program that allocates one Slice
  grows from 89 to 96 KB. The rest of c's size is the expanded slice
  accesses (header loads, checks, the loops' scopes).
- **Lines** (code, without comments): OffHeapPng 344, ScopedPng 337. Scoped
  reads as Haxe (`b[d + x]`), off-heap as calls (`Mem.getU8(b, d + x)`); the
  logic is the same.
- **The checker** doubles c's build, and with it the module cache saves
  nothing.

## wasm32-wasi, a worker instance (node 22, worker_threads)

There, a worker is an isolate: tests/bench/jobs.mjs instantiates the same
compiled module again in a worker thread, with its own linear memory and GC
heap, and frames are the host's (setTimeout, as requestAnimationFrame calls
them).

- **a** decodes on the main instance between two frames.
- **b'** posts the job to the worker, which runs PngDecoder and copies the
  pixels out of its memory into an ArrayBuffer. The buffer is transferred
  (no copy); the main thread copies it into its own instance's memory,
  reads it and frees it.

| variant | frame median | p99 | max | GCs | decode | worker's copy out | main's copy in | longest task |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| none | 1.52 (1.44-1.84) | 11.18 (10.41-12.11) | 11.18 (10.41-12.11) | 1 | 0 | 0 | 0 | 11.18 (10.41-12.11) |
| a | 1.45 (1.38-1.5) | 443.34 (433.19-477.31) | 443.34 (433.19-477.31) | 2 | 443.33 (433.18-477.3) | 0 | 0 | 443.34 (433.19-477.31) |
| b' | 1.53 (1.49-1.82) | 6.93 (5.67-7.69) | 6.93 (5.67-7.69) | 1 | 445.15 (424.11-496.44) | 17.27 (16.47-18.09) | 15.54 (15.07-16.75) | 15.54 (15.07-16.75) |

- **Frames**: the worker's decode and collections never touch the main
  thread's frames. What the main thread pays is one copy into its linear
  memory, 15 ms for 33 MB; with fresh pages it was up to 125 ms in earlier
  runs.
- **Avoiding that copy**: in a browser the pixels can be uploaded straight
  from the transferred ArrayBuffer (texImage2D, writeTexture), or copied
  into a buffer the main instance keeps (warm pages).
- **How pixels can move**:
  - a copy out of the worker's memory into a transferred ArrayBuffer, as
    here, with no cross-origin isolation needed;
  - or a SharedArrayBuffer both sides see. That needs COOP/COEP, and still
    one copy out of the worker's linear memory, unless that memory is
    itself shared (wasm threads).
- **Not run on wasm32**: c and d. With no shared heap there, a worker's
  collections never stop the main thread, so the GC-free tier matters only
  natively. An off-heap job would still save the worker's own GC work.
- **A node bug, worked around**: node 22.22's WASI `fd_write` is a fast API
  call. It allocates through uvwasi, which reports external memory to V8,
  and V8 can start a garbage collection inside the fast call and crash
  (SIGSEGV in `InnerPointerToCodeCache::GetCacheEntry`). Large linear
  memory makes this likely.
  - Repro: read a 10 MB file, allocate, print. 10, 12 and 32 MB crash;
    8 and 16 MB do not.
  - `node --no-turbo-fast-api-calls` avoids it, and the lane passes it.
  - It is node's bug, not hxmc's, and may be behind other wasm32 crashes
    seen under node.

## Why b fails

- **Where it waits**: b's inflate allocates per block, so it reaches a
  safepoint every few blocks. But the Adler-32 and unfilter passes run tens
  of milliseconds with no allocation at all, and a collection that lands
  there waits for the whole pass (time-to-safepoint).
- **With natural collections**: these rarely landed in such a pass, which
  is why b looks harmless in that table. Its worst case is still 35-55 ms.
- **Further pauses**: b's 120 MB of large objects grow the old space, so
  the next major collection comes sooner.
- **The fix is the compiler's**: loop back-edge safepoints (Go's problem
  before 1.14) would make GC jobs safe. Without them, a GC job's pause is
  bounded only by its longest allocation-free loop.

## What the API should look like

This is a description; no API was added to helder.async.

- **GC-free jobs, the engine's default**: a job is an `@:hxmc.unsafe` static
  function over owned off-heap buffers. It takes an input buffer and a few
  Ints and returns a buffer, or an error code. For example:
  `Jobs.run(OffHeapPng.decode, input):Task<Buf>`, where `Buf` is a pointer,
  a length and a free.
  - The runtime runs the job on a pool thread inside a safe region.
  - A Buf moves; it is never shared. The caller frees what comes back, or
    reads it as a zero-copy `Bytes` view first.
  - The job is named by its function's address: natively a pointer, on the
    web the same index in every instance's table.
- **On the web**: a worker instance of the same module. Input Bufs are
  copied into the worker's memory and outputs copied out as transferred
  ArrayBuffers. They arrive as a Buf in the main instance's memory, or as
  the ArrayBuffer itself for an upload that needs no copy.
- **GC jobs**:
  - On the web they are cheap isolates and fine.
  - Natively they are allowed only for code whose allocation-free loops are
    short. Until hxmc polls at loop back-edges, that cannot be checked, so
    natively GC jobs should be documented as able to stall frames by their
    longest loop.
- **Scoped**: nothing in this API needs it, so GC-free jobs give scoped no
  role.

## How the workarounds map to hxmc 025cb79

hxmc's main has these since 025cb79. They are not in the pinned nightly,
and no newer nightly is published (`next` is 0.1.0-nightly.20261027.8e54b1e,
the pinned one), so they were not tried.

| here | hxmc 025cb79 |
| --- | --- |
| `Safe.enter()`/`leave()` over `hxmc.rt.C.Leaf.rt_blocking_enter`/`leave` | `hxmc.unsafe.Blocking.enter()`/`leave()`; `@:hxmc.blocking` on extern fields |
| the PNG in `LibC.malloc` memory, copied in through `BytesPtr.of` | an `hxmc.unsafe.IoBuffer`, read into, blit from `Bytes` |
| OffHeapPng's buffers (`LibC.malloc`/`free`, `Mem.getU8`/`setI8`) | `IoBuffer`s, explicit `free`; their range-checked get/set, or `Mem` on their pointer in the hot loops |
| the pixels to the main thread as a raw pointer, read with `Mem.getU8`, then `LibC.free` | an `IoBuffer` handed over; `view()` a zero-copy `Bytes` for GC code (an upload, PngDecoder's callers) until `free` |

## What hxmc should still expose

- **A checked safe region for Haxe code.** Something like
  `@:hxmc.blocking` on an `@:hxmc.unsafe` Haxe function, not only on
  externs: calls to it are wrapped in enter/leave, as a non-fast C call is,
  and the compiler's GC-freedom check makes the region safe by
  construction. `Blocking.enter()`/`leave()` alone leave the rule to
  discipline.
- **Nesting.** `rt_blocking_leave` sets RUNNING unconditionally. A blocking
  call inside a job's region (a Lock, a file read) would end the region
  early, and the rest of the job would run without safepoints. Either
  `enter():Int` returns the previous state and `leave(prev)` restores it,
  or the region keeps a depth count.
- **A debug check.** Under RT_VERIFY, an allocation's slow path (or a TLAB
  refill) in a thread whose state is SAFE should be a fatal error. Today it
  silently marks the thread RUNNING, in `safepoint` and then `stopHere`.
- **Loop safepoints.** An opt-in poll at loop back-edges, per function or
  `-D hxmc.loop-safepoints`. That would let GC jobs run freely natively,
  and b would then be worth measuring again.
- **Pause statistics without `@:access`.**
  - Today: Gc's minorSecs, majorSecs, youngBytes, promotedBytes and
    collections, and Threads' stStwSecs and stStwMaxUs, through
    `@:access`; the thread statistics only with RT_STATS or
    `Threads.thrStats` forced on.
  - Wanted: a public `hxmc.Gc.stats()`, plus a per-collection record (its
    start, time to stopped, end, kind), or a hook an engine can read to
    see each pause.
  - Wanted: per-thread allocated bytes, since a TLAB-granular nursery
    pointer is all there is now.
- **Owned buffers across threads.** IoBuffer covers this, if it can be
  handed to another thread and freed there. In the browser the same
  type's transfer is an ArrayBuffer.

## The step before: scoped's checker opt-in (0c8f26c)

extraParams.hxml no longer runs `helder.scoped.Check.enable()`; a build
that uses scoped passes it. Native builds, medians of 3, cold
(`-D hxmc.no-module-cache`) and warm:

| | with the checker | | without | |
| --- | ---: | ---: | ---: | ---: |
| | cold | warm | cold | warm |
| Todo | 2.99 | 2.91 | 1.60 | 0.47 |
| Walker | 1.84 | 1.84 | 0.98 | 0.30 |

Without the checker, the module cache saves 70%; with it, nothing.

## Reproduce

```sh
bun run test jobs                    # everything: bin/jobs/results.md (RUNS=5, JOBS="none a b c d c0 d0")
node tests/bench/photo.mjs bin/jobs/photo.png
haxe -cp src -cp tests/bench -main Jobs --macro "helder.scoped.Check.enable()" \
  -D hxmc.target=linux-x86_64 -D hxmc.libc=glibc --custom-target hxmc=bin/jobs/Jobs
bin/jobs/Jobs bin/jobs/DejaVuSans.ttf bin/jobs/photo.png check
bin/jobs/Jobs bin/jobs/DejaVuSans.ttf bin/jobs/photo.png b probe
bin/jobs/Jobs bin/jobs/DejaVuSans.ttf bin/jobs/photo.png alone d
haxe -cp src -cp tests/bench -main JobsWasm -D hxmc.target=wasm32-wasi --custom-target hxmc=bin/jobs/JobsWasm.wasm
node --no-turbo-fast-api-calls --stack-size=65500 tests/bench/jobs.mjs bin/jobs/JobsWasm.wasm bin/jobs/DejaVuSans.ttf bin/jobs/photo.png b
```

## After hxmc 8841f02

Jobs.hx on the nightly's API (@hxmc/cli 0.1.0-nightly.20261027.ec71785):
`hxmc.unsafe.Blocking.enter`/`leave` for d's region (not
`@:hxmc.blocking` on the decode: a blocking function's callees must all
be, which would put d0's decode in a region too), the PNG, the IDAT data,
the rows and the scratch memory in `IoBuffer`s (the pixels freed by the
main thread), the counters from `hxmc.GcStats` (no `@:access`, no
`Gc.stats`; the longest stop from its records). One run of each: the
numbers hold. Probe: d's longest pause 0.61 ms (0.54-0.86), decode 168 ms;
d0 154 ms; b 35 ms (32-47); the worker's allocation for b now exact (119 MB).
