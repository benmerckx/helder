# Foundry: where it goes next

Foundry draws fonts with a pen and edits real outlines. Two things are
still missing: a whole font, and the tools a type designer reaches for
every minute. The steps are ordered so that each makes the next possible,
and each says how the established editors do the same. They are the
reference, not something to copy: Glyphs (macOS, the most used),
FontLab, RoboFont (minimal, scripted), Fontra (in the browser,
variable-first), Glyphr Studio and BirdFont (for beginners), FontForge
(open, old).

What Foundry keeps through all of it: no expert mode, the font real from
the first line, the pen for structure and outlines for quality, and
agents using the same model as a person.

## 1. The canvas: zoom, grid, snapping, measuring

Outline points need precision the fixed view cannot give: at fit, a
font unit is about a third of a pixel.

- Zoom: Cmd/Ctrl and the wheel or a pinch, about the pointer; pan with
  two fingers or Space and a drag; Cmd/Ctrl+0 fits, Cmd/Ctrl+1 shows a
  unit as a pixel, Cmd/Ctrl+plus and minus step it; a key zooms to the
  selection. Opening another letter keeps the zoom, so the same detail
  can be compared letter by letter.
- A grid only when zoomed in (10 units, then 50), off at fit. Points
  stay on whole units, as fonts store them.
- Snapping that knows type: the guides, other points' x and y (stems in
  line, curves' extremes level), as RoboFont and Glyphs do.
- Measuring: Alt shows the distances from the pointer to the points and
  guides around it (a stem's width, an overshoot, a sidebearing).
  Glyphs' measurement tool, without a tool to switch to.

Small, and it makes everything after it easier.

## 2. The whole font

Today only Foundry's own 127 characters exist. Starting from Hanken
drops the rest of Hanken, and its kerning and features with them.

- Every glyph of the font: the grid lists the font's own characters.
  Glyphs and FontLab group them by category (letters, figures,
  punctuation, symbols) and by script; Glyphr Studio by Unicode block.
  Foundry groups by category within each script, with a search ("ł",
  "U+0142", "arrow"). Glyphs without a character (alternates, ligatures'
  parts) get a group of their own, by name.
- Coverage by language, not by Unicode: "Polish, Czech, Turkish..."
  shows what each language needs and what is missing, as Glyphs'
  language sidebar does. For a beginner this is the question that
  matters ("does my font work in Polish?"); Unicode blocks are for
  experts.
- Untouched glyphs pass through exactly. Proportions and transforms
  still reach them, since they are points.
- The glyph order kept, and with it the font's GSUB, GPOS and GDEF
  tables (ligatures, alternates, tabular figures, kerning) copied into
  the export as they are: they name glyphs by number. Hanken UI keeps
  Hanken's typography without Foundry having to understand every lookup.
- Font info: names, version, license (OFL by default for a font made
  from an OFL one), vendor.

This is what makes a font made from a real one shippable.

## 3. Editing in context: a line of text, spacing, kerning

Every serious editor edits letters among other letters. Glyphs' edit
view is a line of text you type ("nanbnc HOHAH"): double-click a letter
to edit it in place, the others drawn around it. Fontra's canvas is the
same. RoboFont's Space Center is a separate preview where sidebearings
are dragged.

- The board becomes a line of text: type a spacing string, click any
  letter in it to edit it (the rest drawn quieter), Tab moves to the
  next. The one-letter board with its neighbours is that line at its
  simplest.
- Spacing on the line: a letter's sidebearings dragged (as now), and
  metrics keys for consistency ("o's left is n's", Glyphs' =n).
- Kerning: click between two letters and drag, or Alt and the arrows
  (Glyphs). Kerning groups (A, À, Á kern alike), written to GPOS. A
  list of the pairs, worst first, for agents and people to check.

## 4. Anchors and composites

Accented letters are a base and a mark. Glyphs places the mark by
anchors: a letter has a "top" point, the acute an "_top" point, and
they are put on each other. Every editor works this way.

- Anchors on letters and marks (top, bottom, ogonek's, cedilla's),
  placed by default from the ink and moved by hand.
- Every accented letter in the chosen languages composed from Unicode's
  decomposition (ą, ţ, ǫ, ő, ẞ's lowercase...): draw about 20 marks and
  the bases, and Latin Extended fills in. Composites follow their parts,
  as borrowing does now.
- Mark positioning (GPOS mark and mkmk) written from the anchors, so
  marks typed separately stack too.

## 5. A pen that draws closer to a real font

The pen draws a consistent font quickly, but it looks drawn: round ends,
one width, joins swelling where lines meet.

- Flat ends by default for sans styles; round, angled or with an inktrap
  as a choice.
- A width per knot: a stroke thinning into a join, swelling on a curve.
  The tracer measures these from a source font.
- "Edit as outline" merges overlapping lines into one clean outline,
  joins thinned.
- Better curves: fewer knots, smoother fitting.

After this, drawing from scratch then refining as outline is
refinement, not repair.

## 6. Variable fonts

Fontra is the reference: a font has axes (Weight, Width), each glyph has
sources (masters) at places on them, and sliders show any point in
between, live. Glyphs calls them masters and shows them as tabs; FontLab
matches incompatible masters for you.

- Axes and masters: Weight 300 and 700, say. A master starts as a copy
  of another. In a pen letter the knots are shared and the pen differs;
  in an outline letter the points are moved, never added or taken away
  (adding one is refused while masters disagree, as in Glyphs).
- Starting from a variable font (Hanken Grotesk is published as one):
  helder reads its gvar, and its outlines at the axis ends are the
  masters, compatible as they come.
- Seeing it: an axis bar above the board (the masters as stops, the
  letter interpolated as you drag, the masters' outlines over each
  other), the same slider on the preview strip, a waterfall of
  instances, a specimen of named instances (Light, Regular, Bold).
- The encoder writes fvar, gvar and HVAR; the preview is the real
  variable font, interpolated by helder's text engine.
- A weight tool for outlines (an offset, then corrected by hand) and a
  check of the masters' compatibility, letter by letter.

## 7. Finishing

- Features beyond the source's: a simple view for ligatures (f_i),
  alternates (a single-storey a as ss01) and tabular figures, written as
  GSUB; a features text field for experts.
- A check before export, as FontLab and Fontbakery report: missing
  letters for the chosen languages, open contours, contours the wrong
  way round, points off the grid, overlaps, kerning missing between
  common pairs.
- WOFF (zlib) beside TTF for the web; CFF outlines (exact cubics) as a
  second format.

## Agents, all along

Each step's tools are an agent's too: the font's characters and
coverage (2), kerning a string and listing the worst pairs (3), anchors
and composing (4), axes and masters (6), the export check (7). Agents
are most useful for breadth ("the 40 remaining letters in the style of
these 8", "kern the capitals", "find stems thinner than n's"); the
person keeps the decisions that make the font theirs.
