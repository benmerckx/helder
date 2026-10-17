# @hxmc/text

Fonts and text layout in pure Haxe, no C library: what `@hxmc/ui` draws
text with, usable on its own.

- `FontFile`: an OpenType font (or a face of a `.ttc` collection): metrics,
  the character map (formats 4 and 12), advances, kerning (GPOS's pair
  adjustments for the `kern` feature, else the `kern` table), glyph outlines: TrueType's (simple and composite glyphs) or
  CFF's (`.otf`: Type 2 charstrings with their subroutines, CID-keyed
  fonts such as Noto Sans CJK too). CFF2 (variable) outlines are not read.
- `Rasterizer`: anti-aliased coverage of outlines, after Raph Levien's
  font-rs (exact area per pixel, quadratic and cubic curves flattened
  within a third of a pixel).
- `SystemFonts`: the fonts found in the system's directories (Linux,
  Windows, macOS; names read from each file's tables without loading it),
  and fonts added from bytes; `match(family, weight, italic)` picks a face
  as CSS does, with `sans-serif`, `serif` and `monospace` mapped to each
  system's usual families; `fallbacks()` for characters a face lacks.
- `TextLayout`: text shaped (each character's glyph from the first face
  that has it, kerning between glyphs of the same face) and broken into
  lines (after spaces and hyphens, around CJK; a word wider than a line is
  cut), with `caret` and `hit` queries.
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

Limits, for now: left to right only (no bidi), no ligatures or mark
positioning (no GSUB or GPOS), no hinting, grayscale anti-aliasing. The same
pixels on every machine, which makes golden-image tests portable; the
platforms' shapers are the planned upgrade (`hxmc/UI.md`).

Tests: `make text-check` (`test/TextTest.hx`).
