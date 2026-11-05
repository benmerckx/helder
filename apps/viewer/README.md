# viewer

helder's image viewer: a native app for Windows, macOS and Linux, built
on helder alone (helder.os's window, helder.gfx, helder.ui, helder.image's
decoders, helder.jobs). PNG (and APNG), JPEG, GIF and WebP, animations
played; also what the system decodes (helder.os's SystemImages: WIC,
ImageIO, Linux's libtiff, libheif, libavif and libraw where installed):
TIFF, HEIC, AVIF, RAW where the system has their codecs, upright.

```sh
bun run helder build apps/viewer                 # bin/<target>/viewer (--target windows-x86_64, macos-arm64)
apps/viewer/bin/linux-x86_64/viewer photo.jpg    # a file: its folder, at it
apps/viewer/bin/linux-x86_64/viewer ~/Pictures   # a folder: its first image
bun run test viewer viewer-window                # its tests; a real window on the GPU
```

## Using it

| | |
| --- | --- |
| Open | the command line's file or folder; a file dropped on the window; Ctrl+O (Cmd+O) a picker: a folder's listing in a card (its folders entered, an image opened; Escape closes it) |
| Next, previous | Right, Down, Page Down, Space; Left, Up, Page Up, Backspace; the wheel while fitted (a notch each); wrapping at the ends |
| First, last | Home, End |
| Zoom | the wheel when zoomed, Ctrl and the wheel, a trackpad's pinch: about the cursor, stopping at 100% and at the fit on their way; `+` and `-` by steps; `0` the fit, `1` 100%; a double click the fit and 100% in turn |
| Pan | a drag (let go moving, it glides a little) |
| Open dialog | Ctrl+O (Cmd+O): the system's (Windows' IFileOpenDialog, macOS's NSOpenPanel, Linux's xdg-desktop-portal), else the in-app picker |
| One viewer | a second launch hands its file to the first (a loopback port in its store, a token) and ends; `--new`: a viewer of its own |
| Open with | `viewer --register`: this user's file types (Windows' registry, Linux's .desktop file); macOS: the app bundle (`bun run helder build --target macos apps/viewer`: `bin/macos/Viewer.app`, universal, its document types from `helder.webmanifest`'s `file_handlers`) |
| Window | F11 or Enter fullscreen, Escape leaves it; I the status line (zoom, size, format, the file's size, its place in the folder) |
| Menus | File (Open…, Open Recent: the last eight files, Quit) and View (Fit, Actual Size, Zoom In, Zoom Out, Previous, Next, Full Screen, Status Line): macOS's menu bar, Windows' in the window, drawn in the window on Linux (F10); a right click on the image: Copy Path (Ctrl+Shift+C), Show in Folder (Finder, Explorer, the file manager's FileManager1), Open with Default App, Fit, Actual Size |
| Keys | every key above is an action of the viewer's keymap (`ViewerActions.hx`: `viewer::Next`, `viewer::ZoomIn`...), the menus' shortcuts the same bindings; a JSON file beside the store (`helder-viewer-keymap.json`, helder.ui's keymap format: `[{"context": "Viewer", "bindings": {"n": "viewer::Next", "space": null}}]`) overrides them, read again when it changes |

The title is the file's name, its place in the folder and its size
(`photo.jpg · 3 / 128 · 4032×3024`). A file that cannot be read, is not
an image this viewer reads, is damaged or larger than helder.image's
limits (`ImageLimits`: 268 MP, 65536 a side, 2 GiB to decode) shows why
in place of the image, and the keys go on to the next. The window's
size and place, and the status line, are kept between runs (helder.os's
`Store`, `helder-viewer`).

## How it works

- **FolderModel** (`src/viewer/FolderModel.hx`): the folder's images in
  natural order (`img2` before `img10`, without case), the one shown,
  next and previous wrapping, the neighbours nearest first; `rescan`
  reads the folder again (the shell's watch, every second): files added
  and removed, the one shown kept by name (gone: the one after it), the
  ones changed on disk named.
- **DecodeCache** (`DecodeCache.hx`): decodes kept by path within a
  budget (768 MB), the wanted ones (the image shown, then two neighbours
  each side) decoded nearest first, two at a time; over the budget the
  farthest go, those no longer wanted first, never the one shown; one
  evicted while still wanted is not decoded again until the order
  changes. The decodes are `Decode.job` (`Decode.hx`) on helder.jobs'
  pool, so flipping to a neighbour shows it at once: a still PNG a GC-free
  job (ImageJobs), the rest GC jobs whose planes and pixels are off the GC
  heap (helder.image's `ImageMemory`) and whose row loops let collections
  in (`GcPoint`), the pixels moved back, not copied, and uploaded from
  there, freed when the cache lets them go (`bun run test viewer` builds
  nothing of it; `tests/bench/PrefetchBench.hx file...` measures the main
  thread's frames meanwhile: p99 88 ms, max 203 ms before; 1 to 5 ms,
  2 to 11 ms now, for a 24 MP JPEG, a 24 MP WebP and a 12 MP PNG);
  helder.image's decoders, every frame of a GIF, WebP or APNG, a WebP's
  EXIF orientation applied (JpegDecoder applies a JPEG's). A JPEG is
  decoded at the size it is shown (the view's larger side: 1/2, 1/4 or
  1/8 while still covering it; the status line says "decoded at 1/4"),
  and again larger when a zoom needs its pixels (`refine`: the smaller
  one shown meanwhile); a still image past 128 MP on the GPU is halved
  until within (its size stays the file's).
- **ViewCamera** (`ViewCamera.hx`): the scale (device pixels per image
  pixel) and the image point at the view's centre; fitted by default
  (the whole image, never above 100%, centred), zooms about a point that
  stop at 100% and at the fit, the keys' steps, pans kept within the
  image, a glide.
- **ImageView** (`ImageView.hx`, `PhotoShader.hx`): the image in ui's
  layout, drawn into a texture of its box before ui's pass (as
  helder.sprite's SpriteBox): the image in `RGBA8Srgb` textures with every
  mip level (generated), tiles of at most 4096 a side past that (each
  with 64 pixels of its neighbours around it, drawn without them: no seam
  where filtering and the mips read across; off the view, not drawn), read trilinearly, so a photo fitted to the
  window is filtered and averaged in linear light, and nearest from 200%
  up; composed over the dark background in linear light and written as
  sRGB. An animation's frame written into the texture as it changes.
- **Viewer** (`Viewer.hx`) is all of it without a window: the state and
  the texts the window shows as signals, the keys, the wheel and the
  pointer; **ViewerActions** (`ViewerActions.hx`) its actions, default
  keymap (the root's key context `Viewer`, with `picker` and `fullscreen`
  while they are), menus and context menu (helder.ui.actions, helder.ui.menu);
  **Shell** (`Shell.hx`) the window (`UiWindow`, `<Surface>`
  with `onDrop`), its markup, the jobs, the watch, the settings.

## Tests

`bun run test viewer` (`helder test` in this directory, natively, and on
Eval the camera's maths; the viewer is a desktop app, not built for the
web): `tests/viewer/FolderModel.test.hx` (natural
order, opening a file or a folder, wrapping, the watch: added, removed,
changed), `DecodeCache.test.hx` (the order, two at a time, eviction by
distance, a budget too small for every neighbour, a changed file),
`ViewCamera.test.hx` (the fit, zooms about the cursor and their stops,
the steps, the double click, pans, the glide), `Viewer.test.hx` (a
scripted run of the shell's tree in a headless Ui: the fixture folder
opened, flipped through with the keys and the wheel, an animation's
frames, a damaged file's message, zoomed with `+`, `1`, Ctrl and the
wheel, `0`, the status line, EXIF's orientation, the picker, fullscreen's
keys), `Viewer.story.hx` (its states: empty, an error, fitted, 100%, the
status line on; their trees in `Viewer.story.snap`). EXIF's reader is
helder.image's (`src/helder/image/Exif.test.hx`), the drops helder.os's
(`bun run test window`). `bun run test viewer-window`: the viewer in a
real window on the GPU (Linux under Xvfb; `GFX_TARGET=windows-x86_64`
under Wine), the fixtures' photo opened, decoded on helder.jobs and
shown, closed after 3 s (`--exit-after`), a 9000x2000 PNG in tiles
(`tests/bigpng.mjs`), then again with no system font
found (`HELDER_NO_SYSTEM_FONTS=1`: helder.text looks for none, and the
viewer adds its own, `fonts/DejaVuSans-viewer.ttf`, a 41 KB subset of
DejaVu Sans, only then). CI runs the tests in its
headless job, the window on Linux (gfx), macOS and Windows (the desktop
jobs).

## Text in any script

File names, the title and the status line in any script: helder.text's
platform engine (HarfBuzz and FreeType on Linux, DirectWrite, Core Text)
shapes the scripts its own does not (Devanagari, Bengali, Tamil...) and
falls back to the system's fonts (fontconfig, IDWriteFontFallback, Core
Text's cascade), an emoji to a colour face; the picker's names are laid
out left to right (`dir`: an extension stays at the end of a Hebrew or
Arabic name, the name itself right to left inside it, UAX #9).
`tests/fixtures/scripts`: Arabic, Hebrew, Devanagari, Bengali, Tamil,
Thai, CJK, emoji and mixed names (FolderModel.test.hx lists and decodes
them).

## Not yet

On Linux, libraw's and HEVC's paths (HEIC needs libheif's libde265 plugin)
have no fixture in the tests; colour management.