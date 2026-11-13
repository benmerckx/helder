# Viewer

A fast image viewer for Windows, macOS and Linux. Open a file and you
can step through every image in its folder. It is a single small program
built on helder alone, with no browser engine and no runtime to install.

- **Opens** PNG and APNG, JPEG, GIF, WebP and PDF on every system, and
  TIFF, HEIC/HEIF, AVIF and camera RAW files where the system has their
  codecs (Windows' WIC, macOS's ImageIO, Linux's libtiff, libheif,
  libavif and libraw).
- **A folder in order.** Files are sorted the way people count (`img2`
  before `img10`), and the neighbours of the current file are decoded
  ahead, so the next image is already there. The folder is watched, so
  files you add or change show up.
- **Sharp at any size.** Images are filtered in linear light when they
  are scaled down. JPEGs are decoded at the size they are shown, and very
  large images (9000 pixels or more) are drawn in tiles. EXIF orientation
  is applied.
- **Animations play**: GIF, WebP and APNG.
- **PDFs, page by page.** The next page is drawn ahead in the background,
  and you can go straight to a page by its number.
- **Desktop integration**: "Open with", the system's open dialog, drag
  and drop, one window that later launches hand their file to, and the
  window's size and place remembered between runs.

## Install

Download the package for your system from the
[releases](https://github.com/helder/helder/releases) page.

**macOS 11 or later** (Apple silicon and Intel): unzip
`viewer-<version>-macos-universal.zip` and move `Viewer.app` to
Applications. Viewer then shows up in Finder's "Open With" menu for images
and PDFs. If the release is not notarised, macOS blocks it the first time
you open it: Control-click the app and choose Open, or go to System
Settings > Privacy & Security and click Open Anyway.

**Windows 10 or later** (x86-64): unzip
`viewer-<version>-windows-x86_64.zip` and run `Viewer\viewer.exe`. To add
it to "Open with" for your account, run `viewer.exe --register` once. If
the release is unsigned, SmartScreen may warn you: click More info, then
Run anyway.

**Linux** (x86-64, glibc; X11 or Wayland with OpenGL ES or OpenGL, which
Mesa provides):

```sh
tar xzf viewer-<version>-linux-x86_64.tar.gz
cd viewer-<version> && sh install.sh      # into ~/.local; PREFIX=/usr/local sudo sh install.sh for everyone
viewer ~/Pictures
```

`install.sh` puts the program in `~/.local/bin` and its menu entry, file
types and icons in `~/.local/share`. To use Viewer as a Flatpak instead,
put `org.helder.viewer.flatpak.json` next to the tarball and run
`flatpak-builder --user --install --install-deps-from=flathub build
org.helder.viewer.flatpak.json`, then `flatpak run org.helder.viewer`.

From the command line on any system, `viewer photo.jpg` opens a file in
its folder, `viewer folder/` opens a folder's first image, `viewer --new`
opens a second window, and `viewer --version` prints the version.

## Shortcuts

Ctrl is Cmd on macOS.

| | |
| --- | --- |
| Open a file | Ctrl+O, or drop a file on the window |
| Next, previous image | Right or Down, Left or Up; Space, Page Down; Backspace, Page Up; the mouse wheel while the image fits |
| First, last image | Home, End |
| Zoom in, out | `+`, `-`; Ctrl and the wheel; a trackpad's pinch; the wheel once zoomed in |
| Fit, 100% | `0`, `1`; a double click toggles between them |
| Pan | drag the image |
| PDF: next, previous page | Page Down, Space or `]`; Page Up, Backspace or `[`; the wheel while the page fits |
| PDF: first, last page | Ctrl+Home, Ctrl+End |
| PDF: go to page | G or Ctrl+G, type the number, Enter |
| Full screen | F11 or Enter (Ctrl+Cmd+F on macOS); Escape leaves it |
| Status line | I: the zoom, the size, the format, the page, the place in the folder |
| Copy the file's path | Ctrl+Shift+C; a right click has Show in Folder and Open with Default App too |
| Menus | the menu bar (on Linux in the window: F10) |
| Quit | Ctrl+Q (Cmd+Q) |

Every shortcut can be changed in `helder-viewer-keymap.json` in the
viewer's settings folder (`~/.local/share/helder-viewer` on Linux,
`%APPDATA%\helder-viewer` on Windows, `~/Library/Application
Support/helder-viewer` on macOS). For example, to make N go to the next
image and turn off Space:

```json
[{"context": "Viewer", "bindings": {"n": "viewer::Next", "space": null}}]
```

The file is read again when it changes. The actions are listed in
`src/viewer/ViewerActions.hx`.

## Formats

| Format | Where | Notes |
| --- | --- | --- |
| PNG, APNG | everywhere | animations played |
| JPEG | everywhere | EXIF orientation applied; decoded at the size shown |
| GIF | everywhere | animations played |
| WebP | everywhere | lossy, lossless, animated; EXIF orientation applied |
| PDF | everywhere | every page; JPEG 2000 and CCITT images; password-protected files are not opened |
| TIFF, HEIC/HEIF, AVIF | Windows, macOS; Linux with libtiff, libheif, libavif | the first frame |
| RAW (DNG, CR2, CR3, NEF, ARW, RAF, ORF, RW2) | where the system has the camera's codec; Linux with libraw | |

A file that is damaged, cut short, not an image or larger than the
viewer's limits (268 megapixels, 65,536 pixels a side) shows why in place
of the image, and the keys go on to the next one.

## Releasing

A tag `viewer-v<version>` builds the three packages and attaches them to
a draft GitHub Release (`.github/workflows/release.yml`); the owner
publishes the draft. The version must be `helder.webmanifest`'s
`"helder": {"version"}`, and `"build"` should rise with each release.
`viewer-v<version>-dry` runs everything and publishes nothing (the
packages are the run's artifacts).

```sh
git tag viewer-v0.1.0-dry && git push origin viewer-v0.1.0-dry   # a rehearsal
git tag viewer-v0.1.0 && git push origin viewer-v0.1.0           # the draft release
```

The packages are `helder build --package` (src/helder/cli/Desktop.hx,
helder.pack), which builds them on any host. The other desktops' runtime
objects come from `node tests/pack/runtime.mjs bin/pack/rt --desktop` and
are passed with `HXMC_RT_DIR=bin/pack/rt`:

```sh
bun run helder build --target linux-x86_64 --package apps/viewer     # bin/dist: .tar.gz, Flatpak manifest
bun run helder build --target windows-x86_64 --package apps/viewer   # bin/dist: .zip of the .exe
bun run helder build --target macos --package apps/viewer            # bin/dist: .zip of Viewer.app
bun run helder publish --notarize apps/viewer                        # on a Mac: notarised and stapled
```

Signing is optional. Each secret holds the file's text, is read from
the environment, and is never printed. When a secret is missing, the
workflow warns and the package ships unsigned (Windows) or signed ad hoc
(macOS):

| Secret | What |
| --- | --- |
| `HELDER_MACOS_CERTIFICATE`, `HELDER_MACOS_KEY` (or `HELDER_MACOS_IDENTITY`, both in one PEM) | a Developer ID Application certificate with Apple's Developer ID G2 intermediate, and its unencrypted key (PEM: `openssl pkcs12 -in id.p12 -nokeys -out id.pem`, `-nocerts -nodes -out id.key`). helder signs the app with the hardened runtime and Apple's timestamp |
| `HELDER_ASC_KEY_ID`, `HELDER_ASC_ISSUER_ID`, `HELDER_ASC_KEY` | the App Store Connect API key that `helder publish --testflight` uses; here notarytool uses it to notarise (together with the Developer ID secrets) |
| `HELDER_WINDOWS_CERTIFICATE`, `HELDER_WINDOWS_KEY` (or `HELDER_WINDOWS_IDENTITY`) | a code signing certificate with its chain, and its key (PEM). helder signs with Authenticode, timestamped by DigiCert's TSA (repository variable `HELDER_WINDOWS_TIMESTAMP_URL` for another, `none` for no timestamp) |

Code signing certificates issued for Windows today keep their key in a
hardware module or a cloud service, so the key cannot be exported as PEM.
For those, set the repository variable `HELDER_WINDOWS_SIGN_COMMAND` to a
command that signs the file whose path is appended (jsign,
AzureSignTool, signtool), and pass that command's own credentials in
secrets that it reads.

## For developers

The viewer is built on helder alone (helder.os's window, helder.gfx,
helder.ui, helder.image's decoders, helder.pdf, helder.jobs). It is a
desktop app: it is not built for the web.

```sh
bun run helder build apps/viewer                 # bin/<target>/viewer (--target windows-x86_64, macos-arm64)
apps/viewer/bin/linux-x86_64/viewer photo.jpg    # a file: its folder, at it
apps/viewer/bin/linux-x86_64/viewer ~/Pictures   # a folder: its first image
bun run test viewer viewer-window                # its tests; a real window on the GPU
```

The title is the file's name, its place in the folder and its size
(`photo.jpg · 3 / 128 · 4032×3024`). A file that cannot be read, is not
an image this viewer reads, is damaged or larger than helder.image's
limits (`ImageLimits`: 268 MP, 65536 a side, 2 GiB to decode) shows why
in place of the image, and the keys go on to the next. The window's
size and place, and the status line, are kept between runs (helder.os's
`Store`, `helder-viewer`).

### How it works

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
- **PdfPages** (`PdfPages.hx`): a PDF's pages, each a decode of its own
  (`Decode.key`: the path, the page after a newline), so they go through
  the cache, the tiles and the zoom an image's do: its 100% two pixels a
  point (4096 a side at most), drawn at the view's side, again larger when
  a zoom needs it (`refine`); the page shown first, then the next and the
  previous page, then the folder's neighbours. The two documents opened
  last are kept open on the jobs' side with helder.pdf's own cache of
  decoded images and page contents (`PdfLimits.imageCache`, 48 MB each),
  so the next page decodes none of what the last one did; one page is
  drawn at a time under a lock; each page has its own decompression
  budget; a changed file is opened again. The key context `pdf` (a
  document of several pages) gives Page Down, Space and `]` to the pages,
  the arrows stay the folder's; `goto` is the go to page card's.
- **Version** (`Version.hx`): `helder.webmanifest`'s version, read at
  compile time, the about card's and `--version`'s.
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

### Tests

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

`bun run test viewer-package`: the three releases built by `helder build
--package` (Linux's on Linux; Windows' signed by tests/pack/signing's
throwaway identity; macOS's ad hoc) and checked (tests/pack/DesktopCheck.hx,
then osslsigncode, desktop-file-validate and appstreamcli where installed,
codesign on a Mac).

### Packages

- **macOS**: the universal `Viewer.app` (arm64 and x86-64) in a zip. Its
  document types come from `helder.webmanifest`'s `file_handlers`, so
  Finder's "Open With" lists it. Its icon is the manifest's on Apple's
  grid. The bundle is sealed (`_CodeSignature/CodeResources`) and each
  slice is signed by helder.pack's own codesign: ad hoc, or by a
  Developer ID with the hardened runtime and Apple's timestamp, which is
  what notarisation asks for. `helder publish --notarize` submits it with
  notarytool and staples the ticket. A DMG would need hdiutil on a Mac
  and gives nothing a zip does not, so the package is a zip.
- **Windows**: `viewer.exe` in a zip, made a GUI program (no console
  window), with its icon from 16 to 256 pixels and its version
  information as resources, and signed with Authenticode when a
  certificate is configured. "Open with" is the program's own
  `--register` (the user's registry). There is no MSIX: an MSIX must be
  signed to install at all, and it would sandbox the folder browsing the
  viewer is for.
- **Linux**: a `.tar.gz` (the program, `install.sh`, a `.desktop` file
  whose `MimeType` holds the file types, hicolor icons from 16 to 512, and
  AppStream metainfo) and a **Flatpak** manifest built from it. Flatpak
  rather than an AppImage: the program is one executable that loads the
  system's EGL, X11 or Wayland, fontconfig and codecs at run time, so an
  AppImage would bundle nothing but itself and still depend on the host.
  An AppImage also needs squashfs tools, a downloaded runtime and FUSE,
  and its file types only register with an extra daemon. The Flatpak
  manifest is text that is reproducible from the tarball (by its SHA-256);
  its freedesktop runtime has those libraries and the GPU drivers, its
  desktop file and icons are exported with the file types, and it is the
  form Flathub takes.

### Text in any script

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

### Not yet

On Linux, libraw's and HEVC's paths (HEIC needs libheif's libde265 plugin)
have no fixture in the tests; colour management; a PDF's password
(no prompt), its text selection and search; the window's maximised state
(helder.os has no call for it); an X11 window's class (WM_CLASS: helder.os
sets none, so an X11 desktop matches the window to its menu entry by its
title alone; Wayland's app_id is the program's name, `StartupWMClass` in
the desktop file).