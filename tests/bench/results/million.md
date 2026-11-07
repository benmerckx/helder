# A million rows (helder.ui's VirtualList)

examples/million: a million messages in a `VirtualList` (helder.ui's
`VirtualScroll` over a `HeightIndex`), each row as tall as its text
wraps (26 to 100 px), estimated until shown. `bun run test million-bench`
measures it two ways, 2026-11-07, a 4-core VM shared with other builds.

## The whole frame: `helder run --headless --stats`

A 480x640 window, the real renderer on Mesa's llvmpipe (a GPU in
software). The script (written by tests/Run.hx's millionBench) turns the
wheel 60 px a frame for 400 frames (rows made the first time), then back
and forth over 1,200 px for 400 (rows made before: shown again, none
made), taps End and Top 20 times (a jump: the rows there made and
measured), Insert 30 times (three rows put in above the first in view:
the program copies its million items, the list diffs them and splices),
then Down 120 times; tests/bench/million.mjs reads it.

| phase | frames | median ms | p95 ms | max ms | over 8 ms | GC bytes a frame (median) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| first frame (the program's million items, the view made) | 1 | 19.56 | | | 1 | 8,633,640 |
| wheel, rows made the first time | 400 | 0.84 | 4.36 | 234.76 | 6 | 55,944 |
| wheel over rows made before | 400 | 0.75 | 4.86 | 29.85 | 6 | 11,984 |
| End and Top (a jump, the rows there made) | 40 | 1.22 | 1.34 | 799.66 | 1 | 480,080 |
| three rows put in above the view | 60 | 3.34 | 6.21 | 94.01 | 1 | 12,084,872 |
| the keyboard's Down | 119 | 0.53 | 4.75 | 12.57 | 1 | 19,496 |
| idle | 54 | 0 | 0 | 0 | 0 | 80 |

The longest frames are llvmpipe's (as code-editor.md found: its shaders
compiled and glyphs uploaded the first time they are drawn); the list's
own work, below, is at most 2.4 ms in any of them. The first frame's 8.6 MB
are the program's array of a million numbers (8 MB); an insert's 12 MB
the program's copy of it.

## The list's own work: tests/bench/MillionBench.hx

The same program in a Ui of helder.text's engine painted into a canvas
that draws nothing, natively, each frame timed alone (after a Ui of ten
rows drawn first: the fonts loaded):

| workload | median ms | p95 ms | max ms | GC bytes a frame (median) |
| --- | ---: | ---: | ---: | ---: |
| the program's array of a million numbers (not the list's) | 4.53 (once) | | | 8,389,520 |
| the first frame: the view made, 12 rows made and measured, laid out, painted | 1.26 (once) | | | 1,038,616 |
| wheel, rows made the first time (60 px a frame) | 0.106 | 0.17 | 1.21 | 51,168 |
| wheel over rows made before (back and forth) | 0.039 | 0.043 | 0.087 | 10,672 |
| — its update alone (no paint) | 0.031 | 0.034 | 0.064 | 576 |
| — scrolled without an event, its update alone | 0.030 | 0.033 | 0.071 | 112 |
| a jump far into the list (scrollToIndex, a frame) | 0.72 | 0.87 | 2.37 | 591,512 |
| a jump to the last row (End: focusIndex, a frame) | 0.53 | 0.61 | 0.75 | 432,412 |
| three rows put in above the view (the diff, the splice, a frame) | 1.35 | 1.95 | 2.04 | 74,816 |
| — the program's copy of its million items with three put in | 3.68 | 4.06 | 5.09 | 12,000,088 |
| the keyboard's Down (the focus moved, a frame) | 0.145 | 0.185 | 1.47 | 58,552 |
| a frame with nothing changed | 0.012 | 0.014 | 0.042 | 9,928 |
| — its update alone (the list's settle: 0) | 0.002 | 0.002 | 0.003 | 48 |

What it holds after the run (1,000,150 rows, 2,403 measured): the height
index 437,072 bytes (0.44 a row: leaves of 128 rows, 4 bytes a measured
row, none for a leaf never measured); 81 rows made (17 in the window, 64
kept), 746 nodes in the tree; 3,493 rows made in all, 3,412 let go.

Scrolling over rows made before makes nothing: the rows are shown again
(their display, which no longer lays their text out again) and the
spacers' heights set (a value of their own, no style allocated); the
update allocates 112 bytes a frame (the Ui's 48 included), the wheel's
event 464 more. The 10 KB a frame of painting is Ui.paint's over these
nodes, as with nothing changed. An insert's diff compares the million
items from both ends in a loop typed for numbers and objects (1 ms; the
generic one took 5), the middle by key.
