# Foundry

Make a font by drawing it. Foundry is for people who have never made a
font: you draw letters with a pen instead of placing Bézier points, letters
borrow shapes from each other, and the font is real from your first line.
Type in it while you draw, then export a `.ttf`. Start from scratch, from
Foundry's own Pebble, or from an open font traced into pen lines. Agents
can draw too, over MCP, and make fonts between fonts.

```sh
bun run helder dev examples/foundry                   # a window, live-reloaded
bun run helder build examples/foundry --target web    # bin/web/Foundry.html
```

## Where a font starts

The start screen (first run; File, New Font, Cmd/Ctrl+N) offers Pebble
(Foundry's own, drawn with the pen), the open fonts Foundry carries
(Inter, Hanken Grotesk, Geist Mono: SIL Open Font License 1.1), a font
file of your own (desktop) or a blank page. A font keeps its own outlines
(`Outlines`): each letter's contours exactly as the font has them
(TrueType's quadratics raised to cubics, then neighbouring curves merged
wherever one cubic follows both within a font unit, so there are points
to edit and not every joint of the original), its metrics, each letter's
place and advance. What you make from it is still a proper font: the
x-height slider moves outline points with the guides, and the Outline tab
edits them. A font made from an OFL font is shared under the OFL.

A letter can also be traced into pen lines (the Pen tab's "Trace into
pen lines", or `font.start {pen: true}` for a whole font), to restyle it
with the pen. `Trace` does that:

1. Each glyph is drawn on the CPU (helder.canvas).
2. It is thinned to its skeleton (Zhang and Suen's thinning, then the
   steps of a staircase taken out).
3. The skeleton is read as a graph: its ends, its junctions, the chains
   between them, its loops. Spurs that thinning leaves at corners are
   pruned.
4. Where a chain runs into a junction or ends on a slanted cut, thinning
   bends it, so the chain is cut back there and carried on straight.
5. Each chain becomes knots (`Freehand`'s), snapped to the guides.

What comes out looks drawn: one pen, round ends, no change of width. That
is the pen's style, not the font's.

## Pen and Outline

The board has two tabs. **Pen** draws and edits pen lines (below).
**Outline** edits the letter's outline as points: a point on the curve (a
square a corner, a circle smooth) and its handles. Drag them (Shift picks
several), double-click a point to make it smooth or a corner, double-click
a curve to put a point there (the curve unchanged), Delete removes points
(the curves either side made one), the arrows nudge. A letter can have
both: Hanken's outline and a pen swash over it. A pen letter opens in
Outline with "Edit as outline", which bakes its ink into points exactly
(the pen's contours are already its outline). Any letter's ink is its
outline plus its pen lines, and borrowing (b from d, é from e) moves both.

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
  glyphs, **Ctrl/Cmd+Z** undoes (Shift: redoes), **Ctrl/Cmd+E** exports,
  **Ctrl/Cmd+N** opens the start screen. Hover the eye for its tooltip.
- **Export .ttf** writes the font to the Downloads folder (the browser's
  own download on the web). **Install** puts it among this user's fonts
  (macOS, Linux), so other apps can use it right away.

The font is kept between runs (`helder.os.Store`). Pebble, the round
monoline sans on the start screen, is about fifty letters drawn as knots
(`Sample`), the rest borrowed.

## Agents

The desktop app serves MCP on `127.0.0.1:7341` (`FOUNDRY_MCP_PORT`).
Add it to any agent that speaks MCP as a Streamable HTTP server at
`http://127.0.0.1:7341/mcp`.

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
| `glyph.draw {char, lines?, outline?, mode?}` | its lines (or outline) replaced (or added to), and a picture of the result |
| `glyph.borrow {char, parts}` | made from others: mirrored, turned, grown, an accent over a base |
| `glyph.transform {chars, scaleX, scaleY, slant, dx, dy}` | letters' ink (outline points and knots) scaled, slanted or moved: "lowercase", "uppercase", "figures" or the letters |
| `glyph.clear`, `glyph.space` | back to empty or its default borrowing; its spacing either side |
| `pen.set`, `metrics.set` | the whole font's pen and proportions, letters following |
| `text.snap {text}` | a picture of text set in the font now |
| `sources.list` | the fonts to take from: current, Pebble, the bundled open fonts, every installed one |
| `font.start {from, pen?}` | the font started again from a source: its outlines, or traced into pen lines |
| `font.blend {a, b, t}` | the whole font between two sources |
| `glyph.blend {char, a, b?, t}` | one letter between two sources (or one's alone), fitted to this font |
| `font.export`, `font.rename`, `board.open` | the .ttf; its name; a glyph shown on the board |

Every edit goes through the app's history, so you can undo it in the
window, and it opens the glyph on the board, so you can watch the agent
work. An agent's letter is written out on the board along the pen's path,
in violet, sparks trailing the pen, then turns to ink. A pill says what it
did, and the cells it changed carry a violet sparkle until you edit them.

Other fonts are material. `sources.list` names them: the bundled ones and
every font installed here, by family. `font.blend` makes a whole font
between two (`Blend`). The pen, the proportions and the spacing are mixed.
Each letter is morphed: both letters' ink is laid on the box between
theirs, each becomes a signed distance field, the fields are mixed at `t`,
and the shape is traced back into pen lines. Letters built differently
morph all the same, so a serif or a slash only one has fades out. So "a
font between Inter and Geist Mono with a swirly x" is `font.blend {a:
"Inter", b: "Geist Mono", t: 0.4}`, then `glyph.read x` and `glyph.draw`
of a swirl, and `glyph.blend` for a letter whose blend looks wrong in
`text.snap`.

## What it uses

helder.ui and helder.view for the window: the studio's `Theme`, and its
`Controls` (`Slider`, `Segmented`, `Tip`), made for this app. helder.text writes
the font (`FontEncoder`) and lays the preview out. helder.canvas draws the
agents' pictures on the CPU. helder.os provides `Store`, and `Downloads`
for the export. helder.async serves MCP.

Not yet: kerning pairs (the encoder writes them, the app has no tool for
them), variable fonts (masters of the same letter: pen letters drawn with
two pens, outline letters with their points moved; the encoder's fvar and
gvar, an axis over the board), the pen's width per knot and flat joins,
and a layout for phones.
