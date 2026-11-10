# Foundry

Make a font by drawing it. Foundry is for people who have never made a
font: you draw letters with a pen instead of placing Bézier points, letters
borrow shapes from each other, and the font is real from your first line.
Type in it while you draw, then export a `.ttf`. Agents can draw too, over
MCP.

```sh
bun run helder dev examples/foundry                   # a window, live-reloaded
bun run helder build examples/foundry --target web    # bin/web/Foundry.html
```

## How it works

- **Lines, not outlines.** A letter is a few pen lines. Each line is the
  path of the pen's centre through a few knots: smooth, unless a knot is a
  corner. Press and drag to draw one. The path is smoothed, thinned to the
  knots that shape it, and closed when it ends where it began (`Freehand`).
  Then it is snapped: a line is stretched so that its ink rests on the
  baseline and reaches the x-height (or the capitals, ascenders,
  descenders), its ends join other lines' knots, and a nearly upright
  stroke stands upright on a stem's line.
- **One pen for the whole font.** Weight, contrast (from a round marker to
  a flat calligraphy nib), the nib's angle and the ends are the font's,
  not a letter's. Change them and every letter follows. Knots resting on a
  guide stay on it when the pen or the proportions change, so dragging the
  x-height reshapes the whole font (`Workshop.refit`).
- **Letters borrow.** Until it is drawn, b is d mirrored, p and q are d
  turned and flipped, u is n turned, O, S, V, X and Z are their small
  letters grown to capitals, 6 and 9 are each other, `:` is two dots, and
  every accented letter is its letter plus its accent (`Charset`).
  Borrowed letters follow their source. "Make it its own" turns the
  borrowed lines into the letter's own to change; "Draw it myself" starts
  it empty.
- **Start with eight letters.** n, o, H, O, i, a, e and s set the stems,
  the bowls, the capitals and the hardest curve. The rest grows from them.
- **Spacing you can see.** The board shows the letter between its
  neighbours (n either side of a small letter, H of a capital), and its
  spacing handles under the baseline. A tracing letter (the interface's
  font) sits behind it, at the face's x-height.

The ink is the font. The pen sweeps each line as an ellipse; the outline
is the envelope's exact points, round or flat at the ends, then fitted
with TrueType's quadratics to within a font unit and a bit (`Ink`). The
board, the glyph grid, the preview and the exported file all draw these
same contours. After each edit `Draft` encodes the font
(`helder.text.FontEncoder`, a few milliseconds for the whole font) and
replaces the face the window's texts are set in, so the preview strip is
ordinary text in the font being drawn, laid out by `helder.text` like any
installed font.

## Controls

- **Draw (P)**: press and drag. Hold Shift for a straight line.
- **Adjust (V)**: drag a knot or a whole line. Double-click a knot to make
  it a corner. Delete removes what is selected; the arrow keys nudge it
  (Shift: five times as far).
- **Erase (E)**: drag over lines.
- **T** toggles the tracing letter, **[** and **]** step through the
  glyphs, **Ctrl/Cmd+Z** undoes, **Ctrl/Cmd+E** exports.
- **Export .ttf** writes the font to the Downloads folder (the browser's
  own download on the web). **Install** puts it among this user's fonts
  (macOS, Linux), so other apps can use it right away.

The font is kept between runs (`helder.os.Store`). File, New From Sample
starts again from Pebble, the round monoline sans the app opens with:
about fifty letters drawn as knots (`Sample`), the rest borrowed.

## Agents

The desktop app serves MCP on `127.0.0.1:7341` (`FOUNDRY_MCP_PORT`):

```sh
claude mcp add --transport http foundry http://127.0.0.1:7341/mcp
```

Agents are poor at drawing Bézier outlines, but good at the same skeleton
a person draws: a stem is two knots, a bowl eight on an ellipse, an arch
five or six. The pen, the snapping and the borrowing keep their letters
consistent. The server's instructions explain the model (units, guides,
the pen's reach), and every edit answers with a picture, so an agent can
judge its strokes and correct them as a person does at the board.

| Tool | Does |
|---|---|
| `font.read` | the name, pen, proportions, how far ink reaches past a knot, each character's state |
| `glyph.read {char}` | its lines (knots), what it borrows, its spacing and box, a picture on its guides |
| `glyph.draw {char, lines, mode?}` | its lines replaced (or added to), and a picture of the result |
| `glyph.borrow {char, parts}` | made from others: mirrored, turned, grown, an accent over a base |
| `glyph.clear`, `glyph.space` | back to empty or its default borrowing; its spacing either side |
| `pen.set`, `metrics.set` | the whole font's pen and proportions, letters following |
| `text.snap {text}` | a picture of text set in the font now |
| `font.export`, `font.rename`, `board.open` | the .ttf; its name; a glyph shown on the board |

Every edit goes through the app's history, so you can undo it in the
window, and it opens the glyph on the board, so you can watch the agent
work.

## What it uses

helder.ui and helder.view for the window: the studio's `Theme`, and its
`Controls` (`Slider`, `Segmented`), made for this app. helder.text writes
the font (`FontEncoder`) and lays the preview out. helder.canvas draws the
agents' pictures on the CPU. helder.os provides `Store`, and `Downloads`
for the export. helder.async serves MCP.

Not yet: kerning pairs (the encoder writes them, the app has no tool for
them), a second weight as a variable font, opening an existing font, and
a layout for phones.
