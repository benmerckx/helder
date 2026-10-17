# @hxmc/text

Fonts and text layout in pure Haxe, no C library: what `@hxmc/ui` draws
text with, usable on its own.

- `FontFile`: an OpenType font (or a face of a `.ttc` collection): metrics,
  the character map (formats 4 and 12), advances, kerning (GPOS's pair
  adjustments for the `kern` feature, else the `kern` table), GSUB's
  single and ligature substitutions by script and feature, glyph outlines:
  TrueType's (simple and composite glyphs) or
  CFF's (`.otf`: Type 2 charstrings with their subroutines, CID-keyed
  fonts such as Noto Sans CJK too). Variable TrueType fonts: `axes`
  (fvar) and `instance(["wght" => 700])`, avar's mappings and gvar's
  deltas applied to outlines and advances (`Variations`; checked against
  Chromium on `test/var.ttf`); `SystemFonts.match` gives a variable
  face's instance at the weight asked for. CFF2 (variable) outlines are
  not read; HVAR, MVAR and GPOS's variations are not applied.
  Colour glyphs: CBDT/CBLC and sbix bitmaps (Noto Color Emoji, Apple
  Color Emoji: their PNG files, a font of bitmaps only loads too) and COLR
  version 0 layers with CPAL's palette (Segoe UI Emoji).
- `Rasterizer`: anti-aliased coverage of outlines, after Raph Levien's
  font-rs (exact area per pixel, quadratic and cubic curves flattened
  within a third of a pixel).
- `SystemFonts`: the fonts found in the system's directories (Linux,
  Windows, macOS; names read from each file's tables without loading it),
  and fonts added from bytes; `match(family, weight, italic)` picks a face
  as CSS does, with `sans-serif`, `serif` and `monospace` mapped to each
  system's usual families; `fallbacks()` for characters a face lacks, then
  `fallbackFor(cp)`, which loads a CJK or other script's face only when a
  character first needs one.
- `TextLayout`: text shaped (each character's glyph from the first face
  that has it, kerning between glyphs of the same face) and broken into
  lines (after spaces and hyphens, around CJK; a word wider than a line is
  cut; tabs to stops every `TAB_SIZE`, 8, spaces, as CSS's `tab-size`), with
  `caret` and `hit` queries. Right-to-left text too: each
  paragraph ordered by the bidi algorithm (`Bidi`: UAX #9's explicit
  levels left out, mirrored brackets), Arabic joined (`Arabic`: each
  letter's initial, medial, final or isolated form, then the required
  ligatures such as lam-alef), the caret at a character's leading edge.
  Emoji sequences (VS16, skin tones, zero width joiners, flags, keycaps)
  take a colour face and its ligatures, their widths as Chromium's;
  default ignorable characters are hidden. The standard ligatures (GSUB's
  `liga` and `clig`: DejaVu's ff, fi, ffi...) are applied as Chromium
  applies them, not where letters are spaced; widths match Chromium's,
  carets and hits divide a ligature by its characters.
  Marks are placed by GPOS's anchors (`mark`, `mkmk`: on the base, its
  ligature component or the mark before), and a character and its marks
  become the composed character when the face has it (`Compose`:
  Unicode's canonical pairs), as HarfBuzz does; Arabic, Hebrew and
  combining accents match Chromium's ink in the tests.
- `Grapheme`: grapheme clusters (a letter and its marks, emoji sequences,
  flags, Hangul syllables from jamo), the steps a caret takes; checked
  against `Intl.Segmenter`.
- Rich text: `TextRun`s give parts of a layout other fonts and line
  heights; each line is as high as CSS makes its line box (the
  paragraph's own font and each run on it, half the leading above and
  below, one baseline), checked against Chromium. An italic the face
  lacks is slanted (`FontSet.oblique`), as browsers synthesize it.
  `maxLines` keeps so many lines, the last ending in an ellipsis that fits
  (CSS's line-clamp, checked against Chromium's).
- `GlyphAtlas`: glyphs rasterized once per size and quarter-pixel offset,
  packed into an R8 bitmap for a GPU texture, its changed region tracked.

```haxe
var fonts = hxmc.text.SystemFonts.get();
var face = fonts.match("sans-serif", 400);
var layout = new TextLayout("Hello, world", new FontSet(face, fonts.fallbacks(), 16), 1.25, 200);
for (line in layout.lines)
	for (g in line.glyphs) {
		var bitmap = atlas.get(g.font, g.id, 16, 0); // where its pixels are
	}
```

In a browser (wasm32-wasi with `packages/os/browser.mjs`) there are no
font files: give the page's fonts to `run` with this package's
`imports.mjs` and the option `fonts: ['DejaVuSans.ttf', ...]` (URLs or
ArrayBuffers); `SystemFonts` adds them.

Limits, for now: no explicit bidi embeddings (LRE, RLI and the like), no
optional ligatures or contextual alternates (GSUB's other lookups), no
cursive attachment or Indic shaping, marks not reordered by combining
class, no hinting, grayscale anti-aliasing. The same
pixels on every machine, which makes golden-image tests portable; the
platforms' shapers are the planned upgrade (`docs/plans/ui.md`).

Tests: `make text-check` (`test/TextTest.hx`).
