# helder.canvas

A 2D drawing API with a CPU back end (phase 1 of the roadmap's
`helder.canvas`): paths, fills, strokes, paints, clips, layers, images and
text, drawn into a pixel buffer with analytic antialiasing, so the same
code gives the same pixels on every machine. It learns from Canvas 2D,
Skia, tiny-skia, Vello and Kha's g2 rather than copying one: paints and
stroke styles are values passed to each call (Skia's model), the canvas
keeps only the transform, the clip and the layers.

```haxe
var c = new Canvas(200, 100);
var p = new Path();
p.roundRect(10, 10, 180, 80, 12);
c.fill(p, Paint.shaded(new LinearGradient(0, 0, 200, 0).addStop(0, 0xFFE11D48).addStop(1, 0xFF2563EB)));
var s = new Stroke(4);
s.join = Join.round;
s.dash = new Dash([8, 4]);
c.stroke(p, s, Paint.solid(0xFF111827));
sys.io.File.saveBytes("out.png", c.toPng());
```

## The core

- `Path`: subpaths of lines, quadratic and cubic Bézier curves; `arc`,
  `arcTo`, `ellipse` (rotated), `rect`, `roundRect` (each corner's radii;
  a negative width or height mirrors it and winds it the other way) as
  cubic curves of a quarter turn at most, with Canvas 2D's rules for where
  a subpath starts (an arc draws a line to its start; after a close the
  next segment starts where the subpath began); `addPath` through a
  `Matrix`, `transform`, `contains` (the winding at a point, the edge
  inside); `SvgPath.parse` adds SVG path data. Its verbs and points are
  two buffers it keeps: `clear` and drawing again allocate nothing.
- Fills by non-zero or even-odd (`fill(path, paint, evenOdd)`).
- `Stroke`: width, `Join.miter` (with `miterLimit`), `Join.round`,
  `Join.bevel`, `Cap.butt`, `Cap.round`, `Cap.square`, `Dash` (on and off
  lengths, an offset), `dots` (a subpath of no length a dot, as SVG and
  Skia; Canvas 2D prunes it). Strokes are outlines (`Stroker`): each side
  offset, joined on the outer side of a turn, through the point on the
  inner one, capped at the ends by the curve's own tangent, through the
  transform (a non-uniform scale makes the pen an ellipse).
- A transform stack (`save`, `restore`, `translate`, `scale`, `rotate`,
  `transform`, `setTransform`); `clip(path, evenOdd)` narrows a coverage
  mask (one buffer per save depth, kept); `saveLayer(alpha, blend, mask)`
  draws apart and composites at `restore` with an opacity, a blend mode
  and a `Mask` (a coverage, from a bitmap's alpha or luminance).
- `Paint`: a colour (0xAARRGGBB) or a shader, an alpha (Canvas 2D's
  `globalAlpha`), a blend mode. Shaders: `LinearGradient`,
  `RadialGradient` (two circles, as Canvas 2D's: the cone between them
  too), `ConicGradient`, each with stops interpolated in straight sRGB and
  premultiplied after (as Chromium), a `matrix` and a spread (`PAD`,
  `REFLECT`, `REPEAT`); `Pattern` (a `Bitmap` repeated across x, y, both or
  neither, nearest or bilinear, its `matrix`).
- `drawImage(bitmap, sx, sy, sw, sh, dx, dy, dw, dh, paint, smooth)`: a
  source rectangle into a destination one through the transform, clamped
  to the source, bilinear or nearest.
- `Blend`: Porter-Duff's operators (`clear`, `copy`, `sourceIn`,
  `destinationOut`, `xor`, `lighter`...), the separable blend modes
  (`multiply`, `screen`, `overlay`, `darken`, `lighten`, `colorDodge`,
  `colorBurn`, `hardLight`, `softLight`, `difference`, `exclusion`) and the
  non-separable ones (`hue`, `saturation`, `color`, `luminosity`), W3C
  Compositing's formulas; the operators that change what they do not
  cover (`copy`, `sourceIn`, `sourceOut`, `destinationIn`,
  `destinationAtop`) apply to the whole clip, as Chromium's canvas does.
- Text: `Glyphs.fill(canvas, layout, x, y, paint)` (and `stroke`): a
  helder.text `TextLayout`'s glyphs (shaped by helder's engine or the
  platform's) as their outlines, through the transform; a synthetic
  oblique slants them as Skia does.
- Pixels: `bitmap` (RGBA8, premultiplied), `readPixels` and `writePixels`
  (straight RGBA, as getImageData and putImageData), `toPng()`
  (helder.image's PNG encoder), `toJpeg(quality, background)`
  (helder.image's `JpegEncoder`, baseline 4:4:4, added for this). WebP
  export is not there yet (helder.image decodes WebP, it encodes none).

Nothing is allocated per call: the rasterizer, the stroker's buffers, the
row of coverage and the span of shaded colours, the masks and the layers
are made once (Canvas.test.hx draws curves, strokes with round joins and
dashes, gradients, clips and layers 200 times: 0 bytes).

**Typed, so unused parts drop out.** Every choice is a call or a value of
its own class, never a string or an enum switched over everything: an
encoder is a method (`toPng`, `toJpeg`), each gradient and the pattern a
class, each blend mode a class (`Blend.multiply` is `Multiply.instance`;
Porter-Duff's share one small class), each join and cap a class, dashes
and masks classes, text a class apart (`Glyphs`) that alone reaches
helder.text. Under `-dce full` an app keeps what it uses: the canvas
lane's `Tiny` (a path filled, a PNG) is 195 KB and holds none of the JPEG
encoder, gradients, patterns, blend modes, the stroker, dashes, masks or
text, where `Full` (all of it) is 677 KB (tests/canvas/dce.mjs checks
the symbols).

**The rasterizer** (`Raster`): each line's exact signed area accumulated
per pixel, a running sum along each row (font-rs's and tiny-skia's
analytic coverage), only the rows and columns a path touched read and
cleared, so a small shape on a large canvas costs its own size. Curves
are flattened within a tenth of a pixel. A colour drawn source-over takes
an integer path (a run of whole coverage of an opaque colour stored as
it is: a 900-pixel circle on a 1000x1000 canvas in 3.5 ms natively, 11 ms
before it); shaders and blend modes compose in floats. SIMD (hxmc.simd)
is not used yet: the coverage sweep is where it would pay next.

helder.ui's SVG rendering (`Svg.render`, `Path.render`) draws through it:
its groups' opacities as layers, its clip paths as clips, its gradients
(spread included) as shaders, its strokes as `Stroke`.

## The DOM facade: `helder.canvas.dom`

The browser's Canvas 2D on the core, shaped like skia-canvas and
@napi-rs/canvas, so code written for the browser runs natively; a layer
of its own (string-valued state, every blend mode and encoder reachable),
which an app using only the core never pulls in.

- `Canvas`: `new Canvas(width, height)`, `width`/`height` (set: cleared,
  its context reset), `getContext("2d")`, `toBuffer("png" | "jpeg",
  quality)`, `saveAs(path)` (the format from the extension),
  `toDataURL()`.
- `CanvasRenderingContext2D`: the state (`save`, `restore`, `reset`), the
  transforms (`getTransform`, `setTransform` with numbers or a
  `DOMMatrix`), `fillStyle`/`strokeStyle` (CSS colours by CSS Color 4's
  grammar, `CanvasGradient`, `CanvasPattern`), `globalAlpha`,
  `globalCompositeOperation` (all 26 and `clear`), line styles and
  `setLineDash`, the path methods (`roundRect` with CSS's radii),
  `fill`/`stroke`/`clip` with a `Path2D` or the current path and a rule,
  `fillRect`, `strokeRect`, `clearRect`, `isPointInPath`,
  `isPointInStroke`, `drawImage` (its three forms; an `Image`, a `Canvas`,
  `imageSmoothingEnabled`), `createLinearGradient`,
  `createRadialGradient`, `createConicGradient`, `createPattern`,
  `createImageData`, `getImageData`, `putImageData` (a dirty rectangle),
  text: `font` (CSS's shorthand), `textAlign`, `textBaseline`,
  `direction`, `letterSpacing`, `wordSpacing`, `fontKerning`,
  `fillText`/`strokeText` (with a maxWidth), `measureText` (a full
  `TextMetrics`: the advance, the ink's box, the font's and the em box's
  ascent and descent, the baselines).
- `Path2D` (from another or from SVG path data), `ImageData`, `DOMMatrix`
  (its 2D part), `Image` and `loadImage(path)` (helder.image's decoders),
  `FontLibrary.use(family, paths)`.
- Not yet: shadows and `filter` (kept, not drawn), `ImageData.data` as a
  typed array in TypeScript (helder's TypeScript has none: a copy as
  numbers; Haxe reads `bytes`), WebP from `toBuffer`.

TypeScript programs import it as `helder/canvas` (`index.d.ts`, made from
these classes: `node src/helder/typescript/api/declarations.mjs`):

```ts
import { Canvas, FontLibrary } from "helder/canvas";

FontLibrary.use("DejaVu Sans", ["fonts/DejaVuSans.ttf"]);
const canvas = new Canvas(320, 200);
const ctx = canvas.getContext("2d")!;
ctx.fillStyle = "#2563eb";
ctx.beginPath();
ctx.roundRect(20, 20, 280, 160, [24]);
ctx.fill();
ctx.font = "24px 'DejaVu Sans'";
ctx.fillStyle = "white";
ctx.fillText("Hello", 40, 110);
canvas.saveAs("hello.png");
```

skia-canvas's extras are for later: multi-page PDF and SVG export,
Path2D's boolean operations and effects (round, trim, jitter), text to
outlines, rendering into a window.

## Correctness

`bun run test canvas`:

- **Reference scenes** (tests/canvas/scenes.ts, 25: both fill rules, every
  join, cap and dash, curves, arcs, rounded rectangles, each kind of
  gradient, patterns, clips, all 26 composite and blend modes,
  transforms, alpha, thin lines, Path2D, images, pixels, text in Latin,
  Greek, Cyrillic, Hebrew, Arabic and Japanese, aligned, measured,
  transformed) drawn by the DOM facade from TypeScript, natively
  (render.ts), against Chromium's canvas drawing the same file
  (chrome.mjs: headless through Playwright, "helder/canvas" the browser's
  own classes, tests/canvas/ref). compare.mjs: on premultiplied values,
  the share of pixels off by more than 24 within 1% (text 6%: two
  rasterisers of glyphs); bin/canvas/report.md and contact.png (helder,
  Chromium, the difference). Now every non-text scene within 0.6%, text
  within 3.2%.
- **WPT**: web-platform-tests' Canvas 2D tests of paths, fills and strokes,
  line styles, compositing, transforms and rectangles (wpt/convert.mjs:
  523 of their 616, the bodies as WPT wrote them on harness.ts's
  `_assertPixel` and the others), natively: 503 pass (Chromium 510 of
  the same); the 20 failures are listed with their reasons
  (wpt/failing.txt: color-mix() and relative colours, CSS Typed OM colour
  objects, strings and booleans given for numbers, a stroke 8 times wider
  than its arc).
- The DCE check (above) and the unit tests (Canvas.test.hx, the test lane).
