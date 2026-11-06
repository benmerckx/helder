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
analytic coverage). The lines are kept first, with their box, and
accumulated into a buffer of the box's alone, in bands of rows that stay
in the cache; of each row only the columns its lines wrote in are read,
and a block of 16 columns no line wrote in is one run of the coverage
carried into it (zero: skipped). So a small shape on a large canvas costs
its own size, a thin diagonal stroke its own pixels rather than its
box's, a large fill its edges and its runs. The sweep is four columns at
a time (hxmc.simd, single floats). Curves are flattened within a tenth
of a pixel. A colour drawn source-over takes an integer path, four pixels
at a time in 16-bit lanes, a run of whole coverage of an opaque colour
stored as it is; shaders and blend modes compose in floats.

helder.ui's SVG rendering (`Svg.render`, `Path.render`) draws through it:
its groups' opacities as layers, its clip paths as clips, its gradients
(spread included) as shaders, its strokes as `Stroke`.

## Extras (phase 4)

- **Documents** (`helder.canvas.doc`): `Recorder`, a Painter that keeps
  every call (its path, paint and stroke copied), `Document`, pages of
  them; `PdfWriter.write(doc)`: a multi-page PDF 1.7, paths as PDF's,
  colours with their opacity and blend mode in ExtGStates, linear and
  radial gradients as shadings (stops as stitching functions, their alpha
  a luminosity soft mask), images as image XObjects with soft masks,
  layers as transparency groups, streams Flate-compressed;
  `SvgWriter.write(page)`: an SVG (gradients userSpaceOnUse, clipPaths,
  groups, mix-blend-mode, images as PNG data). What neither can say
  (conic gradients, patterns, unbounded operators, erasing) is drawn on
  the CPU into an image of its own. `replay(painter)` draws a recording on
  any back end. Not written yet: shadows and filters.
- **Text to outlines**: `Glyphs.add` (the DOM's `ctx.outlineText(text)`: a
  Path2D).
- **Boolean operations** (`PathOps`): `union`, `intersect`, `difference`,
  `xor`, `simplify(path, evenOdd)`: both paths swept into bands (as
  Trapezoids), each span inside by the operation, the outline chained
  into closed contours (holes the other way round), collinear points
  dropped; the result polygonal.
- **Path effects** (`PathEffects`): `round(path, radius)`, `trim(path,
  start, end, inverted)`, `dash(path, intervals, offset)` (as subpaths),
  `jitter(path, segment, amount, seed)`.
- **Filters** (`Filter`, through `saveLayer(alpha, blend, mask, filter)`):
  `Blur` (three box blurs), `DropShadow`, `Shadow`, `ColorMatrix`
  (grayscale, sepia, saturate, hueRotate, invert, brightness, contrast,
  opacity), `FilterChain`; on the CPU, on the GPU (the layer read back and
  filtered on the CPU), on the web as CSS's filter. The DOM facade's
  `filter` and its shadows (`shadowBlur`, `shadowColor`, `shadowOffsetX/Y`:
  the shape drawn through `Shadow` moved by the offset, then itself).
- **A window**: `GpuCanvas(w, h, Device.create(window.surface))` and
  `present()` each frame (examples/canvas-window).

The DOM facade records every page beside its pixels: `canvas.newPage(w,
h)`, `pageCount`, `toBuffer("pdf")` (all pages), `toBuffer("svg")` (the
last), `saveAs("out.pdf")`; Path2D's `union`, `intersect`, `difference`,
`xor`, `complement`, `simplify`, `round`, `trim`, `jitter`, `dash`,
`offset`, `transform`.

Tests: the canvas-doc lane (the scenes as one PDF drawn by poppler and as
SVGs drawn by Chromium, against the CPU's pixels: all 27 within tolerance,
the ones that need a raster fallback looser, composite's unbounded
operators, the dots of zero-length subpaths, shadows and filters not
compared); the shadows and filters scenes against Chromium (canvas lane);
WPT's shadow tests (568 converted now: 545 pass, Chromium 555);
PathOps.test.hx (areas, contours, lengths, the same jitter from a seed);
the canvas-gpu lane runs examples/canvas-window in a window (Xvfb).

## The GPU back end: `helder.canvas.gpu`

`GpuCanvas` (phase 2) is the same `Painter` as the CPU's `Canvas` (the
interface the DOM facade and `Glyphs` draw on), on helder.gfx:

- **Paths as trapezoids**: `Trapezoids` cuts a path's lines (flattened
  in its own units) into bands between every end and every crossing, each
  band's spans by the fill rule, so the trapezoids tile the inside exactly:
  non-zero, even-odd, self-intersections, holes. The transform is the
  vertex shader's: a trapezoid's corners into pixels, its bounds a pixel
  larger.
- **Analytic edges**: each fragment's coverage is the product of its
  coverage by the trapezoid's two pairs of opposite sides (a pair's
  `clamp(d0 + 0.5) + clamp(d1 + 0.5) - 1` on the sides' signed distances in
  pixels: exact for a half plane and for a sliver thinner than a pixel),
  summed into a float target: trapezoids that share a side add up to one
  across it, no seams, no MSAA.
- **Painting**: the path's bounds painted by the paint times that
  coverage and the clip: a colour, a linear, radial (two circles) or conic
  gradient through a table of its colours (the spread applied in the
  shader), a pattern or an image (repeat modes, nearest or bilinear, a
  source rectangle's clamp), premultiplied; a blend mode over a copy of
  the target's pixels (`BlendShader`: Porter-Duff's factors, the separable
  and non-separable modes, the unbounded operators over the whole clip).
- **Batches**: consecutive fills and strokes of a colour that do not
  overlap share their passes, one draw of all their trapezoids' coverage
  and one of their bounds, in draw order; a gradient, a pattern or a blend
  mode ends a batch.
- **Clips** are coverage textures (a save depth's own, two kept to narrow
  it again), **layers** render targets composited at `restore` with their
  opacity, blend mode and mask.
- Pixels: `snapshot()` reads the target back (drawn into the device's
  frame), `writePixels` draws them in again.

From TypeScript, `useGpu()` (helder/canvas) makes every canvas after it a
GPU one. The CPU back end is the reference: `bun run test canvas-gpu`
draws the 25 reference scenes on both (Mesa's llvmpipe on Linux) and
compares them: all 25 within the same tolerance as against Chromium, the
non-text scenes within 0.9% of pixels off by more than 24 of the CPU's.
Not yet: one batcher with helder.ui's renderer and helder.sprite's
SpriteBatch, a compute rasterizer (Vello's) for very large paths, the
Metal, Direct3D and WebGPU back ends tested (only GL's is, in CI's gfx job).

## The web back end: `helder.canvas.web`

`WebCanvas` (phase 3) is the same `Painter` drawn by the browser's own
Canvas 2D, for a web build (wasm32 with `src/helder/canvas/imports.mjs`,
the module `hxmc_canvas`, beside os's and text's in browser.mjs's
`imports`). Its calls are recorded as commands (float64s: an opcode, its
operands; a path's verbs and points as they are) into a buffer the page
runs in one import call when it fills, when pixels are read, or on
`flush()`: a frame of drawing is a few crossings. The page draws each
command with the canvas's context: the transform set per draw, a Path2D
of the path, gradients and patterns made from the paint (a bitmap
uploaded once, a handle), blend modes as `globalCompositeOperation`,
layers as canvases of their own composited at restore (a mask through
destination-in). A web build carries no rasterizer, stroker or shader of
helder's: a rounded rectangle filled is 97 KB of wasm (35 KB gzipped),
the runtime's mostly. From TypeScript, `useWeb()`. Not drawn by it:
gradients' reflect and repeat spreads (the browser's canvas pads), the
`dots` of zero-length subpaths (the browser prunes them).

`bun run test canvas-web` builds the reference scenes as wasm32
(tests/canvas/render-web.ts), draws them in headless Chromium and compares
them with Chromium's references: all 25 within tolerance (text within
3.3%, the others within 0.5%).

### Images decoded by the browser: `BrowserImages`

A web build can leave JPEG and PNG decoding to the browser: encoded bytes go
to `createImageBitmap` (EXIF orientation not applied, optionally resized to
the size drawn with `resizeWidth`/`resizeHeight`), and the result stays in the
page as a handle (`WebImage`) that `WebCanvas.drawHandle` draws like
`drawImage` draws a `Bitmap`. An app that decodes only this way links none of
helder.image's decoders: `-dce full` leaves them out.

The browser decodes asynchronously and a wasm call cannot wait, so drawing is
split the way a page or a frame splits it: a **prepare step** collects the
images, starts their decodes and returns; its callback runs from the page's
event loop once they have all arrived (the program keeps running after
`main` returns, as helder.os's frames do), and the drawing, synchronous,
draws them by handle. JSPI would let a call wait instead, but neither
helder's runner nor every browser has it.

```haxe
BrowserImages.all([{bytes: jpg, type: "image/jpeg", width: 300, height: 200}], images -> {
	var img = images[0]; // null when the browser could not decode it: helder's decoder then
	canvas.drawHandle(img.handle, 0, 0, img.width, img.height, x, y, 300, 200, paint);
	img.release(); // when it is no longer drawn
});
```

`HandleImages` is the interface a caller checks for (`Std.isOfType(painter,
HandleImages)`), so code shared with the other back ends keeps its Bitmaps
there. helder.pdf uses it through `helder.pdf.web.PdfWeb.prepare(page, scale,
done)`: a page's JPEGs (gray or RGB; CMYK, masks and Decode arrays stay
helder's) decoded at the size shown, kept in the document's image cache. The
canvas-web lane checks a PNG and a JPEG, at full and half size, against
helder's decoders (tests/canvas/WebDecode.hx).

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
- Not yet: `ImageData.data` as a
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

skia-canvas's extras are there too (see Extras above).

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
  568 of their 688, the bodies as WPT wrote them on harness.ts's
  `_assertPixel` and the others), natively: 503 pass (Chromium 510 of
  the same); the 20 failures are listed with their reasons
  (wpt/failing.txt: color-mix() and relative colours, CSS Typed OM colour
  objects, strings and booleans given for numbers, a stroke 8 times wider
  than its arc).
- The DCE check (above) and the unit tests (Canvas.test.hx, the test lane).
