# The code editor against its budget (helder.ui.code)

The studio's plan (3b) gives the code editor 8 ms from a keystroke to the
screen, and smooth typing and scrolling on a 10,000-line file with no
garbage in the steady state. `bun run test code-bench` measures it two
ways, on a TSX file of 10,000 lines (examples/ts-todo's app repeated,
each repetition's lines marked with its number so no two lines are
alike), 2026-11-07, a 4-core VM, three runs (the ranges below).

## The whole frame: `helder run --headless --stats`

examples/code-editor in a 900x640 window, run headless (the real
renderer on Mesa's llvmpipe, a GPU in software) with `--stats`: each
frame's work from its script events to the frame drawn, and the GC bytes
it allocated. The script goes to line 5,000's end, types a key a frame
(240 keys, an Enter every 40th), then turns the wheel 80 px a frame for
600 frames down and 600 back up (tests/bench/code.mjs reads it).

| phase | frames | median ms | p95 ms | max ms | over 8 ms | GC bytes a frame (median) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| keystroke to its frame | 240 | 1.48–1.49 | 7.7–9.2 | 186–191 | 12–13 | 11,744 |
| wheel down (lines laid out the first time) | 601 | 1.15–1.19 | 1.7 | 71–86 | 4–5 | 30,624 |
| wheel back up (the steady state) | 599 | 1.24–1.35 | 2.4–3.3 | 5.7–6.9 | 0 | 2,656 |
| idle (the caret blinking) | 48 | 0 | 0 | 2.8 | 0 | 264 |

The frames over 8 ms are llvmpipe's: a profile of the run (perf, llvmpipe
on one thread) has 69% of its samples in llvmpipe's JIT-compiled shaders
and 10% in libgallium, 1.8% in the program; examples/todo typing into its
field has the same kind of frames (10 of 240 over 8 ms, the longest 27
ms). The idle editor draws twice a second (the caret's blink), nothing
between.

## The editor's own work: tests/bench/CodeBench.hx

The same file in a Ui of helder.text's engine painted into a canvas that
draws nothing (no renderer), natively, each frame timed alone:

| workload | median ms | p95 ms | max ms | GC bytes a frame (median) |
| --- | ---: | ---: | ---: | ---: |
| open 10,001 lines, the first frame | 13.7–14.8 (once) | | | |
| keystroke: a character typed (key down, text, key up, the frame) | 0.026–0.027 | 0.044 | 0.1 | 16,424 |
| — the Ui's key down and up alone | 0 | 0.002 | 0.005 | 816 |
| — the edit alone (CodeModel.type) | 0.007 | 0.008 | 0.05 | 3,904 |
| keystroke: Enter (a line added, through the keymap) | 0.165 | 0.18 | 0.24 | 7,672 |
| keystroke: Backspace (through the keymap) | 0.158 | 0.18 | 0.19 | 5,024 |
| a backquote opened at a line's start (the rest of the file a template: read again a thousand lines a tick) | 0.46 | 0.51 | 2.2 | 135,432 |
| the wheel, lines laid out the first time | 0.027 | 0.05 | 2.2 | 21,584 |
| the wheel back up (steady state) | 0.004 | 0.005 | 0.075 | 544 |
| — scrolled 60 px without an event | 0.003 | 0.004 | 0.012 | 48 |
| a frame with nothing changed | 0.003 | 0.003 | 0.03 | 48 |

So the editor takes well under a tenth of the budget; the frame is the
renderer's. Keys bound in the keymap (Enter, Backspace, arrows) cost
0.13 ms more than a typed character, which the editor takes before the
keymap: that is Ui's keymap match.

## What allocates

- **Scrolling over lines laid out**: nothing of the editor's: 48 bytes a
  frame, as a frame with nothing changed (the Ui's); a wheel event adds
  ~500 bytes (its Event), 2.6 KB a frame with the renderer.
- **Scrolling to lines never shown**: each new line's layout (a
  TextLayout and its paragraph, the spans' TextRuns, the line's text
  string and tokens), ~7 KB a line, kept with the line after.
- **A keystroke** (16 KB): the edit (3.9 KB: its Change and inverse,
  selections, the history's snapshot, the rope's chunk rebuilt, ~1 KB of
  UTF-16), the edited line laid out again (a new paragraph: its old one
  may be shared with lines alike, so it is not reused), the Ui's key and
  text events (~0.8 KB).
- **Highlighting**: none for a line read again (its tokens' array is
  kept, states are interned); a line's text string the first time it is
  read.

## Not measured here

A real GPU (the renderer's draw and present: in CI llvmpipe only), the
time from the OS's key event to the window's frame (a headless run's
events are its script's), and the web (wasm32 in a browser).
