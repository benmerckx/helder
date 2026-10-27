# TextLayout's flat glyphs: ui's text without garbage

The README's phase 3, after the text pilot (text.md): TextLayout's output
as flat glyph data instead of `Glyph` objects, ui's renderer following,
measured by tests/bench/Bench.hx against the commit before it (da5680a).
The tests pass: text's (sample.png, sample-cff.png pixel for pixel), ui's
layout cases, ui-draw's golden images (todo.png exact, the others as
before).

## What changed

- **TextLayout's output** (3c5bafc), as HarfBuzz's glyph infos and
  positions: the lines' glyphs in one buffer (`glyphCount`), each line's
  in visual order from `TextLine.glyphStart` to `glyphEnd`, read by index:
  `glyphId`, `glyphFont`, `glyphFontSet`, `glyphX` (the pen from the
  line's start), `glyphAdvance`, `glyphOffsetX` and `Y` (a mark's place),
  `glyphCluster`, `glyphLength`, `glyphChar`, `glyphParts`, `glyphLevel`,
  `glyphRun`, `glyphHidden`. No Glyph objects, and no compatibility
  accessor: the callers (the renderer, DrawParagraph.runs, the tests, the
  bench) read the indices directly.
- **Shaping on columns**: the glyphs in logical order as Int and Float
  Vectors (face, id, character, cluster, length, run, flags with the bidi
  level, advance), Arabic's forms and ligatures, GSUB, colour sequences,
  marks and bidi worked in place (a ligature takes its parts out); a mark's
  attachment and a tab's stops in columns made only when the text has
  them. The lines: each a shaped glyph placed (its index, x, advance; a
  mark's offset). About 56 bytes a glyph, kept with the layout.
- **Kept buffers**: `wrap(maxWidth, maxLines, cut)` lays the same shaped
  text out at another width (shaping depends on no width: SkParagraph's
  `layout(width)`, cosmic-text's Buffer), `reset(...)` shapes another text
  into the same buffers; TextLines are kept and reused.
- **ui**: `TextEngine.layout` takes the paragraph a TextNode lets go
  (`into`). DrawText wraps it again when its text and fonts are the same,
  else reshapes it in place; the paragraphs it shares between nodes of the
  same text are left alone. TextNode hands back its last paragraph and its
  max-content one when they are not the same. NativeText and the tests'
  MonoText take the argument and ignore it.
- **The next garbage** (the rest of a full layout once the text was gone):
  `Size` is an hxmc struct, so measureContent's result is a value, and
  `contentInk` returns `Size.NONE` instead of null (a `Null<Size>` struct is
  boxed): 97 KB a full layout to 0.9 KB; then a resize's breakpoints read
  from an Array instead of the Map's iterator (a4a6da2): 0.9 KB to 94 bytes.

## Before, flat and after

Medians of five alternating runs of the three builds, each workload in a
process of its own (as the lane runs them), 2026-10-27, the same VM.
Before: da5680a (text on reused buffers, Glyph objects); flat: 3c5bafc's
output with TextNode handing no paragraph back (a new TextLayout each
layout, as before); after: a4a6da2. Each cell is before / flat / after,
the change from before in brackets.

| workload | target | median ms | p99 ms | KB/run | GCs (majors) |
| --- | --- | ---: | ---: | ---: | ---: |
| text.layout.latin | native | 0.078 / 0.082 / 0.083 (+6%) | 0.197 / 0.177 / 0.157 | 119.4 / 72.1 / 68.2 | 3 / 2 / 2 |
| text.layout.mixed | native | 0.068 / 0.063 / 0.063 (-7%) | 0.131 / 0.118 / 0.112 | 116.9 / 92.7 / 90.8 | 3 / 2 / 2 |
| text.atlas.cold | native | 5.225 / 5.324 / 5.202 (0%) | 7.212 / 6.810 / 6.183 | 1250.3 / 1250.5 / 1250.5 | 5 / 6 / 6 |
| text.atlas.warm | native | 0.031 / 0.031 / 0.031 (0%) | 0.045 / 0.045 / 0.048 | 0 / 0 / 0 | 0 / 0 / 0 |
| ui.layout.10k | native | 16.52 / 11.32 / 4.21 (-74%) | 39.64 / 15.89 / 4.54 | 11049.1 / 7665.7 / 0.1 | 42 (1) / 28 / 0 |
| ui.relayout | native | 0.008 / 0.007 / 0.008 (0%) | 0.014 / 0.012 / 0.012 | 0.1 / 0.1 / 0.1 | 0 / 0 / 0 |
| ui.hit | native | 1.057 / 1.052 / 1.045 (-1%) | 1.321 / 1.509 / 1.536 | 56.5 / 56.5 / 56.5 | 1 / 1 / 2 |
| text.layout.latin | wasm32 | 0.134 / 0.114 / 0.113 (-16%) | 0.542 / 0.369 / 0.508 | 139.9 / 92.6 / 88.6 | 3 / 2 / 2 |
| text.layout.mixed | wasm32 | 0.133 / 0.125 / 0.124 (-7%) | 0.367 / 0.342 / 0.372 | 137.4 / 113.2 / 111.2 | 3 / 2 / 2 |
| text.atlas.cold | wasm32 | 6.313 / 6.309 / 6.313 (0%) | 8.203 / 8.411 / 8.778 | 1738.0 / 1739.2 / 1739.3 | 5 (1) / 5 (1) / 5 (1) |
| text.atlas.warm | wasm32 | 0.050 / 0.049 / 0.050 (0%) | 0.084 / 0.087 / 0.076 | 0 / 0 / 0 | 0 / 0 / 0 |
| ui.layout.10k | wasm32 | 15.43 / 13.52 / 4.91 (-68%) | 33.08 / 25.73 / 5.47 | 11322.1 / 7665.6 / 0.1 | 20 (2) / 14 (1) / 0 |
| ui.relayout | wasm32 | 0.010 / 0.010 / 0.010 (0%) | 0.024 / 0.030 / 0.026 | 0.1 / 0.1 / 0.1 | 0 / 0 / 0 |
| ui.hit | wasm32 | 1.644 / 1.654 / 1.637 (0%) | 2.261 / 2.050 / 2.659 | 111.1 / 111.1 / 111.1 | 1 / 1 / 1 |

- **ui.layout.10k** (the window's width changed: 1000 paragraphs wrapped
  again, 2000 texts measured): 11 MB of garbage a full layout to 94 bytes,
  no collection in 60 runs (42 before, the longest 27 ms), 3.9x faster
  natively and 3.1x on wasm32, the p99 8.7x and 6x. The flat output alone,
  with a new layout each time, takes 31% of the garbage (the Glyph objects
  and their Arrays against the columns, the shaping's slices and copies),
  not the Glyph share of 57% the pilot's census gave: a new layout's
  buffers and the shaping's own temporaries (GSUB's lookup keys, ligature
  and context results) stay. Laying the paragraph out again in its own
  buffers takes the rest, and the shaping with it: a width change only
  wraps (5.4 us for two paragraphs of 200 characters, against 38 to shape
  them again).
- **text.layout** (a new TextLayout for each of four paragraphs a run):
  40% less garbage; on wasm32 7-16% faster; natively mixed text 7% faster,
  Latin 6% slower in the median run. The new code runs 17% fewer
  instructions, 9% fewer branch mispredictions and half the D1 misses
  (cachegrind, the same run), and the per-run time is lower once a
  collection's cost is counted: in a loop of 2000 layouts of two
  paragraphs, 41.3 us against 46.5 (-11%), 38 with `reset` (-18%), 5.4 with
  `wrap`. With a nursery that fits the cache (RT_MINOR_KB=1024) the median
  is 0.066 against 0.069 ms: the default 8 MB nursery's fresh memory is
  what the median run pays for, a cost of allocating at all. Kept layouts
  (`reset` each run) allocate 1.6 KB a run of text.layout.latin.
- **ui.hit** and **ui.relayout**: unchanged (no text laid out).

## Builds

examples/todo, KB, and seconds from nothing without the checker (best of
three alternating builds):

| program | target | size before | after | compile before | after |
| --- | --- | ---: | ---: | ---: | ---: |
| Todo | native | 2003 | 2016 (+0.6%) | 1.61 | 1.63 |
| Todo | wasm32 | 1490 | 1500 (+0.7%) | 1.75 | 1.72 |

## What allocates now

- **ui.layout.10k**: 94 bytes a full layout, in `Ui.update`, not per node.
- **ui.hit**: 56.5 KB a run natively, all of it the 100 pointer moves (578
  bytes each; the 1000 hit tests allocate nothing): `Ui.setHover`'s two
  Arrays of the old and new hover paths at each change of the node under
  the pointer, the PointerMove Event each move (the API's object; Enter
  and Leave too where a node listens) and the restyles a change of hover
  queues. The next to take: the paths without Arrays (walking up to the
  common ancestor); the events are the API's.
- **text.layout**: a new layout's buffers (about 56 bytes a glyph) and
  the shaping's temporaries in FontFile (`gsubLookupsFor`'s key String per
  segment, `ligature`'s and `context`'s result objects, Bidi's Arrays for
  right-to-left text). Kept layouts: 1.6 KB a run.
- **text.atlas.cold**: the new atlas and a cache entry per glyph; a CFF
  glyph (Inter, not the bench's font) still makes a Charstring.

## hxmc

- wasm32-wasi: Bench running two or three of the ui workloads in one
  process (each building a new tree of 10k nodes, the last one garbage)
  segfaults in node, at every commit measured here, the one before the
  pilot too, with or without RT_OLD_MB=512 and --stack-size; each alone
  runs. The lane runs each workload in a process of its own; this file's
  numbers too.
- A `Null<T>` of an `@:hxmc.struct` is boxed when returned (contentInk's
  24 bytes a call), as expected of a value type: the API takes a sentinel.
