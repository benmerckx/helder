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
  is) until `changed()`; `id` and `version` for a renderer's uploads;
  `replace(other)` puts another image's pixels and size in it (helder.asset's
  reload: what shows it shows the new one). Its pixels are dropped once a
  renderer uploaded them (`uploaded()`, helder.gfx's `ImageTexture`) when
  they can come back (decoded again from its file when read); `retain`
  keeps them for an image whose pixels are read back. `size(bytes)` reads
  a file's size from its header. With `Image.decodeInBrowser`, helder.asset's
  images on the web are decoded by the browser (`WebImages`,
  createImageBitmap) and uploaded from there (copyExternalImageToTexture,
  texImage2D): their pixels never in the module's memory.
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
  of 151 on wasm32. On spans (hxmc 409f580), against the same code as
  `@:hxmc.unsafe` over `Raw` (PngCore alone, on IoBuffers; median ms,
  natively / wasm32 under node): the 4K photo 161 / 183 instead of 169 /
  192, 148 / 176 with `-D hxmc.span-checks=0`; 1920x1080 39.8 / 43.7
  instead of 40.4 / 46.3; 512x512 4.8 / 5.3 instead of 4.9 / 5.6; a
  13x11 image 0.003 ms instead of 0.007 (the thread's tables, not built in
  each decode). The GC heap's bytes are the same but for the header's 44
  bytes (a Bytes now: PngDecoder's 33177747 for the photo instead of
  33177675); off the heap, no copy of the image data (11.6 MB for the
  photo) and no scratch a decode. The checks cost code: a program that
  decodes a PNG 198 KB instead of 132 natively (157 without the checks),
  154 instead of 96 on wasm32 (114).
- `ImageJobs` (hxmc): a PNG as a GC-free job (helder.jobs: natively on
  the pool, in a safe region; in a browser on a worker), `decode` an Image
  over the job's buffer (kept), `pixels` the IoBuffer to upload and free;
  `png` the job itself. JPEG, GIF and WebP decode on the calling thread
  for now.
- `JpegDecoder`: baseline and progressive, decoded as browsers do, the
  EXIF orientation applied (`Exif`).
- `GifDecoder`: the first frame, or `frames`.
- `WebpDecoder` (with `Vp8Decoder`, `Vp8Tables`): lossless and lossy, with
  alpha, pixel-exact with libwebp's decoding; `frames` an animation's.
- `AnimatedImage`: frames played by their delays as browsers play them
  (10 ms or less as 100 ms, the repetitions, then the last frame stays),
  on any clock (`play(add)`: helder.ui's `Clock.add`).

- `BlockCompress`: RGBA8 images (and their mip chains) into GPU blocks,
  BC1, BC3 and ASTC 4x4 (one partition, LDR endpoints at 8 bits), for the
  asset step (helder.scene's `Pack --textures bc|astc`), and back
  (`decode`, tests); helder.gfx's `TextureFormat.BC1`, `BC3`, `ASTC4x4`
  sample them where `Device.supports` says the GPU does.

## Limits and errors

Every decoder checks what a file's header asks for before allocating it
(`ImageLimits`), and each size it reads from a file is computed so that it
cannot overflow (in Float, or within an Int once checked):

```haxe
ImageLimits.maxPixels = 268435456;   // width * height: 2^28, about 268 MP (the default)
ImageLimits.maxSide = 65536;         // either side
ImageLimits.maxMemory = 2147483648;  // the bytes one decode may allocate (2 GiB)
try Image.decode(bytes) catch (e:ImageError) switch e.kind {
	case TooLarge: ...;              // over a limit: its message says which
	case Corrupt: ...;               // malformed or cut short
	case Unsupported: ...;           // another format, or a feature not decoded
}
```

`ImageLimits.check` is called right after each header: the image's sides
and pixels, then the memory its decode takes by the decoder's own count
(JPEG: each component's coefficients and samples, the planes, the pixels;
PNG: the pixels and the rows decoded beside them; WebP lossless: the
pixels, a transform's copy, the prefix codes of every group; VP8: its
planes by whole macroblocks and ALPH's; an animation's frames added as
they come, `DecodeBudget`). A frame's rectangle (GIF, APNG, an ANMF), an
LZW stream's size, a chunk's or segment's length are checked against the
image and the file without a sum that could wrap; reads past a file's end
are zeros (GIF) or a `Corrupt` error. Whatever else a decoder throws is an
`ImageError` too (`ImageLimits.guard`: an index out of a hostile file's
range is `Corrupt`), so a caller catches one type. Tests:
`ImageLimits.test.hx` (hostile headers per decoder: the largest sides,
products past an Int, a frame larger than its screen, chunks past the end,
every test image cut short), `bun run test image-fuzz` (tests/image/Fuzz.hx:
a time-boxed mutation fuzzer over tests/image's files, the limits lowered;
CI's headless job runs it for 30 s), and the image lane checks every
`hxmc.unsafe` of helder.image against a reviewed list
(`tests/image/unsafe.mjs`, `unsafe.txt`).

`Exif.orientation(file)` reads EXIF's orientation (1 to 8) from a JPEG's
APP1 or a WebP's EXIF chunk: IFD0 only, every offset within the TIFF block
(no chain of IFDs followed: no loop, no depth); `Exif.apply` shows pixels
upright. JpegDecoder applies it as browsers do; WebpDecoder's pixels are
libwebp's, as stored (helder's viewer applies it).

SVG is `helder.ui`'s (`Svg`: it draws through ui's `Drawing`).

Tests: `src/helder/image/ImageLimits.test.hx` and `Exif.test.hx` (the
test lane, natively and on wasm32); `tests/image/ImageTest.hx` (`bun run test image`, on Eval and
natively): the decoders against Chromium's and libwebp's pixels, the
cases written by `tests/image/*-cases.mjs`; `tests/image/ImageJobs.test.hx`
the PNG cases through the job (natively and on wasm32-wasi);
`BlockCompress.test.hx` the blocks' round trips (the test lane), the GPU's
decoders reading them in the 3d lane's `compressed` frame.
