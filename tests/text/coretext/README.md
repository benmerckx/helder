# CoreText's own output

What helder.text's CoreGraphics pipeline (`src/helder/text/GlyphPipeline.hx`)
is checked against.

From Rune (github.com/anomalyco/rune, MIT, `RUNE-LICENSE.txt`), captured
from CoreGraphics on macOS 15.3 (24D60), `crates/rune/src/text/macos/smoothing_data`:

- `dilation.json`: 72 glyph paths and the paths CoreGraphics' font
  smoothing dilated them to (each ink's luminance bucket, 8 to 72 ppem);
- `hints.jsonl`: CoreGraphics' y autohinter's transforms for Inter and
  Helvetica at 7 to 18 ppem and each radius, and whether it hinted;
- `sweep.json`: the dilation radius over a grey ramp and five colours at 32 ppem;
- `masks.json`, `masks.bin`: 480 glyph masks of Inter Regular (12
  glyphs, 8 to 72 ppem, dark and white ink, phases 0 and ¼ px across and
  1/64 down), each with font smoothing on and off, cropped to their ink
  in a 96 x 112 tile (the pen at x 8, the baseline 24 px above the bottom).

Fonts (SIL Open Font License, `Inter-LICENSE.txt`): `Inter-Regular.ttf`,
Inter 4.1 Regular (SHA-256 `40d692fc…0c82`, Rune's `assets/`), and
`Inter-Bold-subset.ttf`, Inter 4.1 Bold cut to printable ASCII, the em
dash and curly quotes (Rune's `tests/coretext/`).

`sheets/`: CoreText's own sheets for the text-quality lane
(`tests/text/TextQuality.hx`), drawn on CI's Mac by the system-text lane
(`TextQuality reference`: CTFontDrawGlyphs through helder's Core Text back
end) and copied from its `text-macos` artifact (`bin/text/coretext`).
`<pair>-<scale>x.png` has font smoothing on, `flat-<pair>-<scale>x.png`
off; each is the green channel. `layout.txt` is the digest of helder's
layout they were drawn from: when helder lays the cases out otherwise, the
lane stops until they are drawn again.
