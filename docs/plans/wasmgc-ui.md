# WasmGC and the UI stack

The WasmGC experiment (hxmc's docs/plans/targets.md, "WasmGC") measured
on the packages here: the UI stack and the site's examples, built as linear
memory and as WasmGC modules. Moved from hxmc's plan at the split (hxmc
a994ea3).

## A real program: the UI stack

(As of the 17th; both build and run now: "The hybrid module" below.)
Neither ui-counter nor gfx-cube builds. `HXMC_GC_SURVEY=1` lists what each
lacks (=2 writes the module, those functions trapping):

- ui-counter, 34 constructs, all at the browser boundary, none in the
  ui, text and view code: imports that take pointers (`@hxmc/os`'s canvas
  window, text input, clipboard and cursor; the accessibility mirror;
  WebGPU's shader, buffer and texture uploads; the page's fonts read into
  a Bytes), raw memory (`Mem`, `malloc`/`free`, `Arena`, `CString`,
  strings as UTF-8 through memory), and the GL back end (reached because
  `Device` picks its back end at run time; its calls take pointers too).
  Imports of numbers only are now supported (`scale`,
  `prefers_dark`, `font_count`...).
- gfx-cube, 31: the same, plus `@:hxmc.struct` values (the shaders' Vec2,
  Vec3, Vec4 and Mat4 data, written into GPU buffers through field
  addresses).

What does build is the engine itself. StressTest's list of 1000 rows
without the GPU (markup, signals, styles, flex layout, text shaped with
DejaVu Sans by `@hxmc/text`, the accessibility tree; a program outside the
repository: the fonts added from a file, the page's font lookup skipped),
median of 5, node 22:

| | native | linear | WasmGC |
| --- | --- | --- | --- |
| mount (markup to nodes) ms | 17 | 39 | 32 |
| first layout (styles, flex, text) ms | 33 | 59 | 61 |
| toggle, relabel, scroll, append (each) ms | 0.7-1 | 0.6-1.1 | 0.5-1.3 |
| 5 accessibility trees ms | 7 | 7 | 8 |
| whole run (5 rounds) s | 0.32 | 0.72 | 0.73 |
| peak RSS MB | 102 | 261 | 204 |
| module KB (gzip -9) | 2163 | 1609 (396) | 775 (251) |

Frame times (an update's layout and text) are at parity with linear
memory, the module half the size; painting and the GPU's part could not be
measured. Getting there needed four fixes found by this program (a
structural call to a method of another representation, Vector reads in
generic code, Std.int out of range, BytesBuffer) and the identity hashes.

## The site's examples, both ways

Built as the site builds them (`-D hxmc.wasm-eh=legacy`, no name
section), the linear builds with main's startup memory fix (010fa12):

| example | linear KB | gzip -9 | WasmGC KB | gzip -9 | WasmGC / linear |
| --- | --- | --- | --- | --- | --- |
| gfx-cube | 193.0 | 53.0 | 100.8 | 37.1 | 0.52 (0.70 gzipped) |
| ui-counter | 1226.9 | 319.3 | 824.0 | 273.3 | 0.67 (0.86) |
| ui-gallery | 2275.9 | 530.0 | 1481.0 | 466.5 | 0.65 (0.88) |

(ui-counter's WasmGC module: code 688 KB, string literals as globals 54
KB, the dispatch table's elements 21 KB, a dense class-by-selector matrix
linear memory overlays.)

Run in Chromium 141, Firefox 142 (headed, under Xvfb: headless Firefox
has no WebGL) and WebKit 26.0 by Playwright, 3 runs each, the medians:
ready (fetch, compile, instantiate and main), the first frame, the frame
callbacks' time while the cube turns, the counter is clicked 30 times or
the gallery scrolled 30 times; memory: the linear memory plus, in
Chromium, the JS heap (which holds WasmGC's objects; the others give no
such number, so their WasmGC column shows the linear memory only); RSS:
the browser's own processes above an empty page. WebGPU on SwiftShader in
Chromium, WebGL2 elsewhere (llvmpipe, Mesa); no GPU, a shared 4-core
machine:

| browser | example | build | ready ms | first frame ms | frame mean ms | frame p90 ms | memory MB | browser RSS MB |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Chromium | gfx-cube | linear | 70 | 80 | 0.43 | 0.9 | 12.6 | 62 |
| Chromium | gfx-cube | WasmGC | 61 | 81 | 0.36 | 0.7 | 3.6 | 62 |
| Chromium | ui-counter | linear | 117 | 177 | 0.57 | 2.1 | 23.9 | 88 |
| Chromium | ui-counter | WasmGC | 147 | 199 | 0.56 | 2.1 | 9.5 | 96 |
| Chromium | ui-gallery | linear | 161 | 270 | 2.12 | 5.1 | 24.8 | 130 |
| Chromium | ui-gallery | WasmGC | 237 | 465 | 1.99 | 5.0 | 17.8 | 131 |
| Firefox | gfx-cube | linear | 121 | 123 | 0.31 | 1.0 | 10.3 | 85 |
| Firefox | gfx-cube | WasmGC | 173 | 175 | 0.25 | 1.0 | (1.3) | 89 |
| Firefox | ui-counter | linear | 279 | 316 | 0.59 | 2.0 | 21.6 | 117 |
| Firefox | ui-counter | WasmGC | 309 | 378 | 0.49 | 2.0 | (2.3) | 125 |
| Firefox | ui-gallery | linear | 445 | 581 | 3.54 | 12.0 | 21.8 | 144 |
| Firefox | ui-gallery | WasmGC | 422 | 575 | 3.43 | 9.0 | (3.3) | 164 |
| WebKit | gfx-cube | linear | 118 | 146 | 2.72 | 3.0 | 10.3 | 53 |
| WebKit | gfx-cube | WasmGC | 93 | 115 | 2.93 | 4.0 | (1.3) | 55 |
| WebKit | ui-counter | linear | 198 | 262 | 0.44 | 1.0 | 21.6 | 104 |
| WebKit | ui-counter | WasmGC | 210 | 263 | 0.40 | 1.0 | (2.3) | 106 |
| WebKit | ui-gallery | linear | 350 | 540 | 1.63 | 4.0 | 21.8 | 118 |
| WebKit | ui-gallery | WasmGC | 331 | 664 | 2.64 | 6.0 | (3.3) | 217 |

(Firefox and WebKit time in whole milliseconds.) Before main's startup fix
the linear builds took 98-106 MB of linear memory at start; against the
fixed ones the difference in memory is a few MB, and the browsers' RSS
shows none (WebKit's gallery: WasmGC's larger).

What it says:

- **Size**: the modules are a half to two thirds of linear memory's, but
  gzip narrows it (0.70-0.88): linear memory's code compresses better.
  What a visitor downloads shrinks by 16-65 KB per example.
- **Frame times**: at parity in Chromium and Firefox (the UI engine's
  layout, text and drawing, and the cube's per-frame work, including
  the copies of uniforms through the memory); in WebKit the gallery's
  frames are 60% slower (2.64 against 1.63 ms) and its RSS higher.
- **Startup**: the cube starts as fast or faster; the UI examples' first
  frame is slower in Chromium (gallery 465 against 270 ms) and in WebKit
  (664 against 540): a larger part of a UI program runs before the first
  frame (styles, layout, text, its strings made from globals at
  instantiation), and how the engines tier WasmGC code up is not
  measured here.
- **Memory**: a few MB less than the fixed linear builds' linear memory,
  none in the browsers' RSS.
- **WebKit's trap**: in 108 runs in WebKit 26.0 (54 per build, the three
  examples), one failed, a WasmGC ui-counter on its first frame:
  "RuntimeError: Out of bounds array.set" under the callbacks' table's
  call, not reproduced in the 53 other WasmGC runs nor in Chromium and
  Firefox; the linear builds had none. It fits the intermittent WebKit
  trap the playground shows (believed an engine bug), but one in 54 is
  not enough to tell; it needs its own investigation before WebKit users
  get WasmGC by default.

HaxeBenchmarks under node 22 after all of the above, median of 5 (`make
bench`'s targets hxmc, hxmc-wasm, hxmc-wasmgc; every check identical; the
linear builds with main's startup memory fix):

| case | native s | linear s | WasmGC s | / linear | native MB | linear MB | WasmGC MB | linear KB | WasmGC KB |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| alloc | 1.71 | 2.58 | 2.85 | 1.10 | 749 | 1467 | 667 | 42 | 8 |
| bcrypt | 2.97 | 3.37 | 3.12 | 0.93 | 4 | 58 | 54 | 278 | 131 |
| binarytrees | 0.74 | 1.10 | 1.15 | 1.04 | 117 | 119 | 85 | 38 | 7 |
| json | 0.52 | 0.75 | 0.83 | 1.11 | 140 | 245 | 191 | 103 | 39 |
| mandelbrot | 0.79 | 0.99 | 0.70 | 0.71 | 11 | 64 | 53 | 42 | 8 |
| mandelbrot_anon | 1.31 | 2.40 | 1.01 | 0.42 | 11 | 64 | 53 | 44 | 8 |
| nbody | 0.79 | 1.03 | 1.05 | 1.02 | 0 | 52 | 50 | 42 | 10 |
| sha256 | 0.20 | 0.30 | 0.34 | 1.14 | 21 | 75 | 69 | 250 | 114 |
| sha512 | 0.03 | 0.11 | 0.08 | 0.70 | 9 | 58 | 56 | 255 | 118 |
| formatter_noio | 6.55 | 8.22 | 9.39 | 1.14 | 262 | 193 | 101 | 1045 | 507 |

Against the table above: linear memory got faster and smaller (the
startup fix: sha256 0.35 to 0.30 s, json 0.79 to 0.75 s, peak RSS 58-75 MB
instead of 150), so the memory lead is now small except where much is
allocated (alloc, json, formatter_noio), and four cases are 10-14% slower
than linear memory instead of within 10%. Part of it is WasmGC's own:
formatter_noio 8.86 to 9.39 s, of which about 3% is the local set from
Dynamic that is no longer given a type (correctness: a String local may
hold a closure, as view's text holes do), the rest not yet attributed.

