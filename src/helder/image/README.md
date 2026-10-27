# helder.image

Images in pure Haxe (Haxe package `helder.image`): PNG, JPEG, GIF and WebP
decoded to RGBA8 pixels, and animations' frames. It depends on nothing
else of helder, so that `helder.ui` (its `image` element), `helder.scene`
(textures, `Images.decode`) and an asset step use the same decoders.

```haxe
var image = Image.decode(bytes);            // by the file's signature
var d = JpegDecoder.decode(bytes);          // {width, height, rgba}
var anim = AnimatedImage.decode(bytes);     // a GIF's, WebP's or APNG's frames
anim.play(helder.ui.Clock.add);             // on a clock: its image the frame shown
```

- `Image`: RGBA8 pixels, rows top to bottom, straight alpha; `decode`
  by the signature, the file kept as `source` (a writer embeds it as it
  is) until `changed()`; `id` and `version` for a renderer's uploads.
- `PngDecoder`: every colour type, depth and interlacing, tRNS; `frames`
  an animated PNG's, composed as Chromium composes them.
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
cases written by `tests/image/*-cases.mjs`.
