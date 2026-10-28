# helder.image

Images in pure Haxe (Haxe package `helder.image`): PNG, JPEG, GIF and WebP
decoded to RGBA8 pixels, and animations' frames. It depends on nothing
else of helder (but `ImageJobs`, on helder.jobs), so that `helder.ui` (its
`image` element), `helder.scene` (textures, `Images.decode`) and an asset
step use the same decoders.

```haxe
var image = Image.decode(bytes);            // by the file's signature
var d = JpegDecoder.decode(bytes);          // {width, height, rgba}
var anim = AnimatedImage.decode(bytes);     // a GIF's, WebP's or APNG's frames
var image = ImageJobs.decode(bytes);        // in a coroutine: a PNG decoded as a GC-free job
anim.play(helder.ui.Clock.add);             // on a clock: its image the frame shown
```

- `Image`: RGBA8 pixels, rows top to bottom, straight alpha; `decode`
  by the signature, the file kept as `source` (a writer embeds it as it
  is) until `changed()`; `id` and `version` for a renderer's uploads.
- `PngDecoder`: every colour type, depth and interlacing, tRNS; `frames`
  an animated PNG's, composed as Chromium composes them. A wrapper of
  `PngCore`, helder's one PNG decoder: a kernel (`@:hxmc.kernel`, no
  `@:hxmc.unsafe` but for its scratch's memory) over checked spans
  (`hxmc.Span`, `ReadOnlySpan`), which decodes a Bytes lent for the call
  on the calling thread (`ReadOnlySpan.ofBytes`) and an off-heap buffer in
  a GC-free job alike; on Eval and JavaScript the same code over hxmc's
  Bytes-backed spans. Its inflate is its own (as hxmc's std's), reading
  the IDAT chunks where they are (no copy of the image data), the rows
  unfiltered and widened to RGBA8 in the one buffer; its scratch (the
  inflater's state and tables, the fixed codes built once) the thread's,
  made at its first decode, so that jobs on a pool's threads (a worker's
  own instance on wasm32) share nothing and a decode allocates nothing. Against the decoder it replaced (d4857f3, PngDecoder on
  haxe.zip's InflateImpl): the 4K photo in 184 ms instead of 259 natively
  (198 against 276 on wasm32), 33 MB of garbage instead of 119; a 48x48
  icon 0.022 ms instead of 0.027, 9 KB of garbage instead of 41; a
  program that decodes a PNG 115 KB instead of 198 natively, 85 instead
  of 151 on wasm32. A 13x11 image's fixed cost is 3-4 µs more (0.005 ms
  instead of 0.002: its tables' memory).
- `ImageJobs` (hxmc): a PNG as a GC-free job (helder.jobs: natively on
  the pool, in a safe region; in a browser on a worker), `decode` an Image
  over the job's buffer (kept), `pixels` the IoBuffer to upload and free;
  `png` the job itself. JPEG, GIF and WebP decode on the calling thread
  for now.
- `JpegDecoder`: baseline and progressive, decoded as browsers do, the
  EXIF orientation applied.
- `GifDecoder`: the first frame, or `frames`.
- `WebpDecoder` (with `Vp8Decoder`, `Vp8Tables`): lossless and lossy, with
  alpha, pixel-exact with libwebp's decoding; `frames` an animation's.
- `AnimatedImage`: frames played by their delays as browsers play them
  (10 ms or less as 100 ms, the repetitions, then the last frame stays),
  on any clock (`play(add)`: helder.ui's `Clock.add`).

SVG is `helder.ui`'s (`Svg`: it draws through ui's `Drawing`).

Tests: `tests/image/ImageTest.hx` (`bun run test image`, on Eval and
natively): the decoders against Chromium's and libwebp's pixels, the
cases written by `tests/image/*-cases.mjs`; `tests/image/ImageJobs.test.hx`
the PNG cases through the job (natively and on wasm32-wasi).
