# helder.text

Fonts and text layout in pure Haxe, no C library: what `helder.ui` draws
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
  Chromium on `tests/text/var.ttf`); `SystemFonts.match` gives a variable
  face's instance at the weight asked for. CFF2 (variable) outlines are
  not read; HVAR, MVAR and GPOS's variations are not applied.
  Colour glyphs: CBDT/CBLC and sbix bitmaps (Noto Color Emoji, Apple
  Color Emoji: their PNG files, a font of bitmaps only loads too) and COLR
  version 0 layers with CPAL's palette (Segoe UI Emoji).
- `FontEncoder`: a TrueType font (.ttf) written from glyphs of quadratic
  contours (`FontSource`: the family, metrics, each glyph's characters,
  advance and contours, kerning pairs): the tables an installed font and
  a browser's @font-face need (head, hhea, maxp, OS/2, hmtx, cmap format
  4, name, post 3, loca, glyf) and the kern table; no hinting, the Basic
  Multilingual Plane. `FontFile.parse` reads it back (FontEncoder.test.hx),
  as do CoreText and fontTools. examples/foundry makes its fonts with it.
- `Rasterizer`: anti-aliased coverage of outlines, after Raph Levien's
  font-rs (exact area per pixel, quadratic and cubic curves flattened
  within a third of a pixel); `reset` for the next bitmap, its buffer kept.
- `SystemFonts`: the fonts found in the system's directories (Linux,
  Windows, macOS; names read from each file's tables without loading it),
  and fonts added from bytes; `match(family, weight, italic)` picks a face
  as CSS does, with `sans-serif`, `serif` and `monospace` mapped to each
  system's usual families; `fallbacks()` for characters a face lacks, then
  `fallbackFor(cp)`, which loads a CJK or other script's face only when a
  character first needs one.
- `TextLayout`: text shaped (each character's glyph from the first face
  that has it, kerning between glyphs of the same face) and broken into
  lines (after spaces and hyphens, around CJK, after a soft hyphen, shown
  as a hyphen where a line breaks; a word wider than a line is cut, or by
  `breaking` as CSS's `overflow-wrap` and `word-break`: overflowing,
  cut anywhere, between any letters or not around CJK, as Chromium breaks;
  tabs to stops every `TAB_SIZE`, 8, spaces, as CSS's `tab-size`), with
  `caret` and `hit` queries. Right-to-left text too: each
  paragraph ordered by the bidi algorithm (`Bidi`: UAX #9 whole, explicit
  embeddings, overrides and isolates, bracket pairs; checked against
  Unicode's BidiCharacterTest.txt; mirrored brackets), Arabic joined (`Arabic`: each
  letter's initial, medial, final or isolated form, then the required
  ligatures such as lam-alef), the caret at a character's leading edge.
  Emoji sequences (VS16, skin tones, zero width joiners, flags, keycaps)
  take a colour face and its ligatures, their widths as Chromium's;
  default ignorable characters are hidden. GSUB's standard and contextual
  ligatures and alternates (`liga`, `clig`, `calt`: DejaVu's ff, fi,
  ffi..., Inter's arrows and ×) are applied as Chromium applies them, not
  where letters are spaced: single, alternate, ligature and (chained)
  context substitutions, each lookup in the lookup list's order; widths
  match Chromium's, carets and hits divide a ligature by its characters.
  Features asked of a `FontSet` (`features`, `FontFeature.parse`: CSS's
  font-feature-settings, `"'tnum', 'liga' 0"`) add their lookups (tabular
  figures, character variants, stylistic sets, alternates, discretionary
  ligatures) or turn `liga`, `clig`, `calt` and `kern` off.
  Marks are placed by GPOS's anchors (`mark`, `mkmk`: on the base, its
  ligature component or the mark before), and a character and its marks
  become the composed character when the face has it (`Compose`:
  Unicode's canonical pairs), as HarfBuzz does; Arabic, Hebrew and
  combining accents match Chromium's ink in the tests.
- `TextLayout`'s glyphs are flat, as HarfBuzz's glyph infos and
  positions: the lines' in one buffer of `glyphCount`, each line's in
  visual order from `TextLine.glyphStart` to `glyphEnd`, read by index
  (`glyphId`, `glyphFont`, `glyphFontSet`, `glyphX`: the pen from the
  line's start; `glyphAdvance`, `glyphOffsetX` and `Y`: a mark's place;
  `glyphCluster` and `glyphLength`: the characters it shows, UTF-16
  units; `glyphChar`, `glyphLevel`, `glyphRun`,
  `glyphHidden`). No object per glyph. A layout keeps its buffers:
  `wrap(maxWidth)` lays the same shaped text out at another width (as
  Skia's `SkParagraph::layout`, cosmic-text's `Buffer`), `reset` shapes
  another text into them; neither allocates once they are large enough
  (ui's TextNode lays its paragraph out again in place).
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
- `GlyphPipeline`: CoreGraphics' glyph pipeline, what macOS's CoreText
  draws (below, "CoreText's look"): pens floored to its subpixel steps,
  font smoothing's dilation, its y autohinter, its curve flattening, then
  the Rasterizer's coverage as is.
- `GlyphAtlas`: glyphs rasterized once per size, pen phase (sixtieths of
  a pixel: `GlyphAtlas.pixel` and `phase` floor a pen to CoreGraphics'
  step) and font smoothing's radius, packed into an R8 bitmap for a GPU
  texture, its changed region tracked. Drawn in frames (`begin` before
  each): full in the middle of one, `get` gives no glyph (null; `full`)
  rather than drawing over glyphs the frame already placed, and the next
  `begin` makes room between frames: the last frame's glyphs packed
  again (the others evicted, least recently drawn first), the bitmap
  grown first, up to `max` a side, where they take more than half of it
  (`generation` counts the repacks). A glyph too large for an atlas is
  drawn alone (`bitmap`: its coverage, for an image of its own). A glyph is drawn by a
  GlyphPipeline and Rasterizer the atlas keeps, from points `FontFile`
  reads into buffers it keeps: a miss allocates its cache entry and
  nothing else, a hit nothing (tests/bench/results/text.md).

```haxe
var fonts = helder.text.SystemFonts.get();
var face = fonts.match("sans-serif", 400);
var layout = new TextLayout("Hello, world", new FontSet(face, fonts.fallbacks(), 16), 1.25, 200);
for (line in layout.lines)
	for (i in line.glyphStart...line.glyphEnd) {
		var x = layout.glyphX(i) + layout.glyphOffsetX(i), y = Math.round(line.top + line.baseline + layout.glyphOffsetY(i));
		// (where its pixels are: the pen floored to CoreGraphics' step, the bitmap drawn for that phase and ink)
		// (null: full this frame; atlas.begin() before the next makes room)
		var bitmap = atlas.get(layout.glyphFont(i), layout.glyphId(i), 16, GlyphAtlas.phase(x, 16), false, 0, 0x1d1e22);
		var left = GlyphAtlas.pixel(x, 16) + bitmap.left, top = y + bitmap.top;
	}
layout.wrap(120); // the same glyphs in lines of 120 pixels, not shaped again
```

In a browser (wasm32-wasi with `src/helder/os/browser.mjs`) there are no
font files: give the page's fonts to `run` with this package's
`imports.mjs` and the option `fonts: ['DejaVuSans.ttf', ...]` (URLs or
ArrayBuffers); `SystemFonts` adds them.

A program's own fonts by path: helder.asset's `Asset.font("fonts/x.ttf")`
(added to `SystemFonts`; bundled with the build). Under `helder dev` a
changed font is put in the same `FontFile` (`replace`: a new `id`, so
atlases draw its glyphs again; `FontFile.generation`, which ui's text
engine reports, lays its texts out again).

Limits of helder's own engine: no multiple or reverse chained
substitutions, lookup flags (marks skipped), `ccmp` and `locl`, no
cursive attachment or Indic shaping, marks not reordered by combining
class, CoreGraphics' y autohinter alone (TrueType faces at 7 to 18 ppem),
grayscale anti-aliasing. The same pixels on every machine, which makes
golden-image tests portable; the platform's engine (below) does the rest.

Tests: `bun run test text` (`tests/text/TextTest.hx`; the pipeline against
CoreGraphics' own output: `tests/text/CoreGraphicsTest.hx`).

## CoreText's look

helder's engine draws text as macOS's CoreText does, on every OS, at 1x
and 2x, with font smoothing or without: `GlyphPipeline` is CoreGraphics'
glyph pipeline, ported from Rune's (github.com/anomalyco/rune, MIT:
`crates/rune/src/text/macos/`, which recovered it from macOS 15.3; its
constants are Rune's measurements, credited where they are kept).

- Pens are floored to CoreGraphics' subpixel step, which depends on the
  ppem: fifths of a device pixel below 8⅓ ppem, quarters to 11.1, thirds
  to 16.7, halves to 33.3, whole pixels above (`GlyphPipeline.steps`).
  A pen within 1.25/1024 px under a step is on it, as CoreText places
  them (fitted on CI's Mac). Baselines are whole device pixels.
- Curves are flattened with CoreGraphics' tolerances (coordinates as f32,
  halved until flat), and at whole ppem 7 to 18 its y autohinter maps
  every point's y to snap the x-height ('o') and cap height ('X') to whole
  pixels (TrueType faces with instructions, fpgm, prep or cvt: CoreText
  on CI's Mac leaves faces cut without them unhinted; CFF and obliques
  are not hinted).
- Coverage is drawn as is (exact area, no gamma), blended in sRGB-encoded
  space as Core Animation and CSS blend: helder.ui's Renderer already does
  (premultiplied colours of sRGB values into a target that is not sRGB),
  so nothing changes there but the glyphs.
- Font smoothing is a mode (`FontSmoothing`). **On**, macOS's default:
  each outline is dilated before its coverage, by a radius from the ink's
  luminance (its linear Rec. 709 luminance to quarters, q) and the device
  ppem, `min(ppem · (0.0058 + 0.01 q), 0.3)`: lines and the monotonic
  pieces of curves moved by the signs of their direction, sides ±r, tops
  +2r, bottoms not at all, joined by bevels. Light text on dark is
  thickened more than dark on light, as on a Mac. **Off**: CoreText with
  smoothing off, what macOS browsers draw for
  `-webkit-font-smoothing: antialiased`, lighter.
- Chosen per app with `Shaping.smoothing` (`HELDER_FONT_SMOOTHING=on|off`,
  or `-D helder.text.smoothing=off`; On by default on every OS, so
  goldens do not vary), per window with its atlas's
  (`renderer.atlas.smoothing`), in markup and TSX with `<Surface
  fontSmoothing="off">` (or `"antialiased"`; reactive). Each mode, and
  each radius an ink gives, keeps its own atlas entries: switching back
  draws nothing again. `GlyphAtlas.get` takes the ink (0xRRGGBB).
- Its masks land within 3 levels of 255 of CoreGraphics' for Inter at 8
  to 72 ppem, dark and white ink, smoothing on and off, two phases
  (tests/text/coretext: Rune's captures; 94% of pixels exact, the rest
  CoreGraphics' fixed-point scan conversion).

The platform's engine (`Shaping.SYSTEM`) draws with its own rasters, as
before; on macOS Core Text's without smoothing.

The text-quality lane (`bun run test text-quality`,
`tests/text/TextQuality.hx`) measures helder's engine against CoreText
itself: Inter Regular and Bold at 9 to 32 pt, DejaVu Sans at 11 to 16 and
an Inter 16/26 paragraph, in four inks (dark on light, light grey and
near white on dark, a mid blue), at 1x and 2x, in both modes, drawn as
the Renderer draws them, against CoreText drawing the same glyphs at the
same pens (`CoreText.sheet`: CTFontDrawGlyphs through helder's Core Text
back end into an sRGB bitmap; the system-text lane draws them on CI's Mac,
`tests/text/coretext/sheets` is a copy). It reports Rune's numbers:
structural similarity (Gaussian SSIM on each row's ink), the ink's weight
against CoreText's, and the pixels' differences (their distribution, the
share off by more than 8, the mean, the largest), and the same for the
rasterizer helder had before (`bin/text-quality/report.md`, heatmaps).
It fails when a mode is further from CoreText than 4 levels anywhere.

Its numbers (CoreText on CI's macOS 15 runner; every pair and both scales
in the report). Rows pooled by pixel, SSIM their mean, weight helder's ink
over CoreText's:

| against CoreText | engine | SSIM | weight | mean abs | >8 | max |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| smoothing on, dark on light, 1x | before | 0.9265 | 0.880 | 10.29 | 22.0% | 191 |
| | smoothing on | 1.0000 | 0.998 | 0.153 | 0 | 2 |
| smoothing on, light on dark, 1x | before | 0.8823 | 0.789 | 13.32 | 23.9% | 191 |
| | smoothing on | 1.0000 | 1.002 | 0.138 | 0 | 3 |
| smoothing on, dark on light, 2x | before | 0.9001 | 0.889 | 9.77 | 14.4% | 222 |
| | smoothing on | 1.0000 | 0.999 | 0.082 | 0 | 3 |
| smoothing on, light on dark, 2x | before | 0.8599 | 0.856 | 10.24 | 15.0% | 200 |
| | smoothing on | 1.0000 | 1.001 | 0.077 | 0 | 2 |
| smoothing off, dark on light, 1x | before | 0.9384 | 0.998 | 7.34 | 16.5% | 190 |
| | smoothing off | 1.0000 | 0.998 | 0.143 | 0 | 2 |
| smoothing off, light on dark, 2x | before | 0.9295 | 1.003 | 6.20 | 11.0% | 200 |
| | smoothing off | 1.0000 | 1.001 | 0.084 | 0 | 2 |

Every pixel is within 3 levels of CoreText's, 86 to 93% of them exact;
the rest is CoreGraphics' fixed-point scan conversion. Before, light text
on dark had a fifth less ink than CoreText's (no smoothing), and glyphs
were placed and shaped otherwise (pens to the nearest quarter, no
hinting, its own flattening).

## The platform's own stack

`Shaping` chooses the engine. The platform's (`Shaping.SYSTEM`, an app's
default) shapes the scripts helder's own does not (`Shaping.complex`:
Devanagari and the other Indic scripts, Sinhala, Tibetan, Myanmar, Khmer,
Balinese, Javanese...: reordering, conjuncts, split vowels) and
rasterises glyphs; fallback and discovery ask it too. Behind one
interface, `TextBackend`:

- Linux (`linux/LinuxText`): fontconfig's fallback and families, HarfBuzz's
  shaping, FreeType's rasters (unhinted, grayscale); each library loaded
  at run time (helder.os.Dl), none: helder's own for that part.
- Windows (`windows/DirectWrite`, COM's vtables): the shared
  IDWriteFactory2; the system font collection (FindFamilyName,
  GetFirstMatchingFont) for a family; IDWriteFontFallback's MapCharacters
  (over a text analysis source of ours, its methods callbacks) for a
  character; IDWriteTextAnalyzer's AnalyzeScript, GetGlyphs and
  GetGlyphPlacements for shaping; IDWriteGlyphRunAnalysis (grayscale,
  natural symmetric, no grid fitting) for rasters. A face is opened from
  its file; a font's file named by the local loader's path.
- macOS (`mac/CoreText`, Core Foundation and the Objective-C runtime): a
  family's faces by a CTFontDescriptor, a character's fallback from
  CTFontCopyDefaultCascadeListForLanguages then CTFontCreateForString,
  shaping as a CTLine's runs (a run Core Text gave another font not
  taken), rasters by CTFontDrawGlyphs into an alpha-only
  CGBitmapContext.

TextLayout gives such a run (one face, one text run) to the back end and
takes its glyphs in visual order: ids, advances and offsets, each
cluster's characters from its first UTF-16 unit to the next cluster's;
line breaking, carets, selection and drawing stay helder's. GlyphAtlas
takes the platform's coverage into the same R8 atlas (colour glyphs stay
helder's own: CBDT, sbix, COLR).

helder's own engine stays (`Shaping.HELDER`): `helder test` builds with
it (`-D helder.text.engine=helder`), the repository's lanes run with
`HELDER_TEXT_ENGINE=helder` (stories and store screenshots too), so
goldens do not vary by OS; per font, `FontFile.engine`.

Tests: `linux/HarfBuzz.test.hx` (TextLayout's glyphs as HarfBuzz's for
Latin, Hebrew, Arabic, CJK, Thai, Devanagari, Bengali and Tamil; carets
and lines over shaped clusters; helder's engine chosen per app and per
font), `Bidi.test.hx`, and the system-text lane
(`tests/text/SystemTextTest.hx`, natively on each OS: each script's
fallback, a family found, the reordered and split vowels, rasters; every
script drawn with both engines, `bin/text/system-<os>.png`).

## Spellchecking

`Spell.checker()` is the platform's spellchecker for the user's language
(LANG's tag, `Spell.language()`), a `SpellChecker`: `check(word)`,
`suggest(word)`, `add(word)` (the user's dictionary); `Spell.words(text)`
and `Spell.misspelled(checker, text, ?cache)` give the words and the
misspelled ones as start and end pairs (UTF-16). macOS:
NSSpellChecker's shared checker (`mac/MacSpell`); Windows 8 and later:
ISpellChecker over COM (`windows/WinSpell`: ISpellCheckerFactory's
checker for the language); Linux: Enchant (`linux/LinuxSpell`,
libenchant-2 loaded at run time with helder.os.Dl: its providers and
personal dictionary), else Hunspell itself (libhunspell and a dictionary
of /usr/share/hunspell; words added kept for the run). None installed, in
a browser or on a phone: null, and spellcheck is off. Off as well with
helder's own text engine (`Shaping.HELDER`: tests, stories,
screenshots) or `HELDER_NO_SPELLCHECK=1`; `Spell.given` sets a checker of
the program's own (tests). helder.ui's text fields use it
(`EditableText.spellcheck`). Tests: `Spell.test.hx`, and
`tests/text/SpellTest.hx` in the window lane (each desktop's checker: a
right and a wrong word, suggestions, a word added).
