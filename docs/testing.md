# Testing the packages

The packages' checks, as hxmc's docs/testing.md described them until the split
(hxmc a994ea3). `make <target>` runs them here (Makefile); paths such as
`hxmc/test/...` and `haxe/test/...` are in the hxmc checkout (`HXMC`).

## The packages' examples, built

`make examples-check` (a lane of `make check`; `hxmc/test/ExampleBuilds.hx`)
builds the packages' examples and runs none of them, so it needs no
browser, GPU or display: what CI's `site` and `gfx` jobs build, where a
program that does not build otherwise shows first. Its list is the site's
gallery's (`site/src/Examples.hx`: the files of `packages/<pkg>/examples` with
a header), of every package with examples (theme's too, which the gallery
leaves out): each example built for wasm32-wasi as the site builds it
(`Examples.wasm`, `Examples.wasmArgs`: the package's class paths, legacy
exception handling), and each one on a canvas or playing a sound, a program
on `@hxmc/os`'s window and audio, also for this machine (`Examples.buildArgs`,
as `gfx-programs`, `3d-check`, `audio-programs` and the site's measurements
build them: Linux in the glibc mode). That is 20 modules and 19 executables,
built in parallel (half the cores' worth of builds at once, `-j`; ids
restrict it), with the module cache, into `bin/hxmc-t/examples`; a build that
fails prints its log's end. About 15 s after the tool or the std changed (an
empty cache), a few seconds otherwise (Xeon E-2356G, 6 cores/12 threads, 62
GB, Linux 6.1). Not built there: the JavaScript islands and bundles of
`packages/web/examples` (the port's: `make web-check`, `web-widgets`), and
ui's `NativeForm`, which has no header (`make ui-web-check` builds it for
wasm32-wasi, `ui-programs` natively in `NativeTest`).

## Graphics

`make gfx-check`: the examples of `packages/gfx`, the triangle, the cube
(textured, lit, depth-tested, with a uniform block, over a blended backdrop
shaded by the fragment position and a soft shadow, turned by a fixed
angle), the instances, the render targets (a scene with its depth texture
rendered into a texture shown on the cube), the mip maps (a trilinear
floor through generated levels, levels written one by one read at given
levels) and the texture formats (each written and rendered into, depth
textures sampled), rendered headless and in a window, compared with
`packages/gfx/test/<scene>.png` (a pixel matches when no
channel differs by more than 2, and at most 0.5% may differ by more), and
in the window the input sent to it (a key's character, the wheel) checked
as events: on Linux by Mesa's llvmpipe (an EGL pbuffer, an X11 window under
Xvfb), on macOS by Metal (an offscreen texture, a Cocoa window; skipped
without a Metal device or outside a GUI session), on Windows by D3D11's
WARP (an offscreen texture, a Win32 window); `GFX_TARGET=windows-x86_64`
runs the Windows build under Wine (wined3d over llvmpipe, under Xvfb) (CI:
the `gfx` and `gfx-arm64` jobs on Linux, `gfx-windows` on Windows x86-64
and arm64, `gfx-macos` from the npm packages).
`make gfx-web-check`: the same on WebGPU and on WebGL2 (forced), built for
wasm32-wasi, headless and in a canvas, in headless Chromium (SwiftShader;
`packages/gfx/test/web.mjs`; CI's `gfx` job); CI checks the site's triangle and
cube the same way (`make site-check`, `site/tools/browser-test.mjs`, the
`playground` job: WebGPU and WebGL2 in Chromium, WebGL2 in Firefox, under
Xvfb, and in WebKit), and in Chromium on an emulated phone (touch, a 390x844 viewport, Chromium's
own touch input through DevTools): a horizontal touch drag turns the still
cube (its frame read back differs), a vertical swipe starting on the canvas
scrolls the page (`touchAction: 'pan-y'`); and the spinning cube held: while
a finger, or the mouse, holds it after a drag (the mouse's leaving the
canvas), its frames do not change, and once let go it spins again.
`make gfx-cache-check` (CI's `gfx` job): the module cache across builds with
other defines on one store, WebTest with `-D hxmc.wasm-gc`, GfxTest
natively, then each again: each restored whole, the same bytes, linked and
run (`web.mjs`'s triangle, GfxTest's headless triangle).
`make gfx-shader-check`: the shader macro on Eval (shaders run on the CPU, the
emitted sources, the programs it rejects: `packages/gfx/test/ShaderTest.hx`),
and the tests' PNG files (`Png.hx`: written as `--bless` writes them, in
stored blocks of 65535 bytes, and read back).
`make android-check ANDROID_TARGET=android-arm64|android-x86_64`: the APKs
of `AndroidTest` and the cube (`hxmc/test/ApkCheck.hx`: the zip and its
alignment, the manifest read back, the library's ELF: a shared object, 16 KB
segments, Bionic's imports and versions, the TLS models; the v2 signature's
digest recomputed and its signature verified by openssl; `zipalign`, `aapt`
and `apksigner` where installed), and RFC 6979's vector for the P-256 code;
`make shared-check`: shared libraries of the glibc mode loaded by an hxmc
program (`hxmc/test/SharedCheck.hx`; arm64 under qemu); `make
android-device-check`: AndroidTest on the device or emulator adb reaches
(`packages/gfx/test/android.sh`: the cube headless on the device's GPU
against `cube.png` by the rule above, frames in the activity's window, a tap
and a key as events, Home and back as Suspend and Resume, Back; a screenshot
and the log). CI's `android` job runs them, the last on an x86-64 emulator
with KVM (not a required check yet).
`make ios-check IOS_TARGET=ios-arm64|ios-sim-arm64`: the app bundles of
`IosTest` and the cube, and the cube's `.ipa` (`hxmc/test/IosCheck.hx`: the
bundle's files, `Info.plist` read back, the Mach-O's header, build version,
dylibs and signature's place, the code signature's CodeDirectory: its
identifier, page hashes and special slots recomputed against the
`Info.plist`, requirements and `CodeResources`; `llvm-objdump` where
installed); `make ios-sim-check` on a Mac with Xcode: IosTest on a new
iPhone simulator (`packages/gfx/test/ios.sh`: `codesign --verify` and
`plutil -lint` first, the cube headless on the simulator's Metal against
`cube.png`, frames in the window, its pixels lit, a tap on the Simulator's
window (`SimTap.hx`) as MouseDown and MouseUp, Settings and back as Suspend
and Resume; the screenshot, stdout and the system log). CI's `ios` job runs
the first on Linux, `ios-simulator` the second on a macOS runner (not
required checks yet).
`gfx-check` and `gfx-web-check` also draw `FeatureScene` (buffer and texture
writes, R8 and RGBA8 textures, blending, scissor) against
`packages/gfx/test/features.png`.
`make 3d-check` (CI's `gfx` job): `@hxmc/3d` ([plans/3d.md](plans/3d.md)): its
math (quaternions against gfx's rotation matrices, inverses, decomposition,
bounds), the scene graph's matrices and their cache, the camera and the
fixed-step clock, and the glTF reader (the sample scene of
`packages/3d/test/SampleModel.hx` as .glb and .gltf, its accessors, the
hierarchy as scene nodes, files it must reject), on Eval, natively and as
wasm32-wasi (`packages/3d/test/SceneTest.hx`, `GltfTest.hx`;
`@hxmc/physics`: `packages/physics/test/PhysicsTest.hx`, its checksum the
same on all three), input
actions from synthetic events natively and as wasm32-wasi (`InputTest.hx`),
a `Model.of` reference to a name the file lacks rejected, `@hxmc/3d-ui`'s
markup on the scene graph natively (`packages/3d-ui/test/SceneUiTest.hx`), then the
renderer's frames (`packages/3d/test/Scenes.hx`: the sample glTF scene)
headless against `packages/3d/test/<scene>.png` by the rule above
(`RenderTest`, `check.sh`; `make 3d-programs GFX_TARGET=<target>` builds it
for another target: CI runs the ARM64 one on llvmpipe (`gfx-arm64`) and the
Windows ones on D3D11's WARP (`gfx-windows`), and `check.sh` runs a Windows
build under Wine on Linux); `make 3d-web-check`: the same on WebGPU and
WebGL2 in headless Chromium (`packages/3d/test/web.mjs`).

## UI

On Eval: `make view-check` (`@hxmc/view` on two test renderers, on Eval,
natively and in JavaScript (compiled by the port, run by node): signals,
markup, components, text runs, reactive values, the control flow
components, boundaries between renderers, the programs the macro
rejects), `make web-check` (`@hxmc/web`'s static renderer on Eval and
natively: escaping, attributes, the markers hydration reads, islands;
then in headless Chromium: the DOM renderer, and the demo page of
`packages/web/examples` hydrated without making a node again, reactive
afterwards, a mismatch rendered again, a JavaScript island calling a
wasm32-wasi module's exports, gfx's cube as a WebAssembly island fetched
once it scrolls into view; it prints the sizes of a small island's bundle
and of the loader), `make text-check` (the rasterizer,
DejaVu Sans' tables and outlines, line layout, a text sample through the
atlas against `packages/text/test/sample.png`: the same pixels on every
machine with that font; Inter's CFF outlines and GPOS kerning against
`sample-cff.png`, when fonts-inter is installed, as in CI; Arabic, Hebrew and marks against Chromium's widths and ink, grapheme clusters against `Intl.Segmenter`), `make ui-check` (the flexbox layout against
Chromium's on 89 cases (29 of them CSS grids), `packages/ui/test/layout-expected.json`, which
`layout-ref.mjs` writes from `layout-cases.mjs` (`make ui-layout-fuzz SEED=n COUNT=n`, a tool and not a lane: random flex trees against Chromium's boxes, `FEATURES=more` grids, absolute positions, auto margins, order, aspect ratios, hidden overflow and display none too, a difference reduced into a case there, `make ui-layout-reduce CASE='fuzz 41-87'` dropping nodes and properties while it still differs; the plain trees of seeds 3, 5, 8, 11, 13, 17, 19, 23, 29, 31, 41 and 99 all match, the more trees differ mostly where aspect ratios meet stretching); text wrapping, events and
focus; PNG files of every colour type, depth, filter and interlacing,
`packages/ui/test/png/`, which `png-cases.mjs` writes with the pixels
expected, checked against Chromium's decoder when written; JPEG files of
every kind the decoder reads, `packages/ui/test/jpeg/`, which
`jpeg-cases.mjs` writes with the pixels Chromium decodes, matched exactly,
and GIF files the same way (`gif/`, `gif-cases.mjs`); SVG documents drawn
by `Svg` against Chromium's pixels (`svg/`, `svg-cases.mjs`; the shapes
must agree, edge anti-aliasing may differ); CSS colours and gradients
against Chromium's (`css/`, `css-cases.mjs`);
popups placed, hit and dismissed; then markup rendered into hxmc.ui's
nodes (`MarkupTest.hx`: attributes from Style's properties), the popup widgets driven by pointer and keys, a VirtualList of
100000 rows scrolled; the examples of `packages/ui/GUIDE.md`, run by
`GuideTest.hx`). `make theme-check` (`@hxmc/theme`: Tailwind's class lists read as rules, Tw's rules made at compile time, shadcn's sheet made, the classes it rejects at compile time). Natively: `make
ui-draw-check` (the sample UI, the todo example and the widget gallery,
the last two driven through their Ui under @hxmc/theme's `Shadcn.sheet`, drawn headless against `draw.png`,
`todo.png` and `gallery.png` (and the gallery dark, right to left, and
with no sheet at all: `gallery-unstyled.png`, its frame only); `BoxTest`, boxes with their own corners' radii
and sides' borders, a clip to rounded corners, box shadows (blurred, a
spread ring, inset, several), boxes turned, scaled, skewed
and nested, against Chromium's `boxes.png` (`box-ref.mjs` from
`boxes.json`), a text under `scale(2)` against the same text
twice the size; `BLESS=1` writes the goldens again, uncompressed, and
`node packages/gfx/test/png-deflate.mjs` compresses them before a commit; Linux: llvmpipe, DejaVu
Sans; the sample in a window under Xvfb, whose loop must sleep once it has
nothing to draw; `StressTest`, a list of 1000 rows: the time of each step,
mounting, layout, frames, a change to one row, a scroll; `ClipboardTest`,
the clipboard between two windows under Xvfb, through X11's selection
protocol; also on Windows and macOS in CI; `TextInputTest`, key presses
typed through X11's input method under Xvfb, keys given other symbols: a
Cyrillic letter, a dead key composed with the next; `LinuxAccessTest`
and `AtspiProbe`, a window's accessibility tree read and pressed by
another process through libatspi, in a D-Bus session with AT-SPI's bus
(at-spi2-core); on macOS in CI
`TextInputTest` types through the window's text view and composes in it,
`MacAccessTest` reads the accessibility tree through NSAccessibility and
performs its actions, and drives the native views: a field (an
NSTextField, a password's NSSecureTextField), a text area (an NSTextView),
a context menu chosen from (NSMenu), the menu bar's item performed; on
Windows `WinAccessTest` calls the UI Automation providers through their
COM interfaces and asks UI Automation for the window's element, and drives
the native views: an EDIT typed into and centred, a popup menu chosen
from by keys, the window's menu bar and a command of it). In the browser: `make ui-web-check` (the native form on the DOM's own
controls, `native-web.mjs`; native text editors over a drawn window,
the page's input and textarea, typed in, submitted, tabbed between drawn
widgets and hidden under a popup, `web-field.mjs`; the todo example (its
fields drawn) for
wasm32-wasi in headless Chromium on WebGPU and WebGL2, driven by real pointer
and keyboard events, an input method's composition through the DevTools
protocol, against `todo.png`). CI runs all five in the `gfx` job.

## The dev loop

`make dev-check` ([dev.md](dev.md); CI: the `gfx` job): `HotTest`
(`packages/os/test`: `hxmc.dev.Hot` and a store written as a third-party
library, `test/store/Store.hx`, run twice, the second time from the first
one's snapshot, natively and on Eval; built again with a changed type, that
value reset and logged), `RefreshTest` (`packages/view/test`: signals keyed
by their variables in each component instance, two instances apart, `For`
rows by position, the `key` attribute, a `Show` turned on later), then
`hxmc dev` itself on a copy of ui's Counter (`packages/os/test/dev`): in
headless Chromium, as wasm and as WasmGC (`dev-web.mjs`: clicks through the
canvas's ARIA mirror, an edit reloads the page with the count kept, a
changed signal type resets it with a notice, a compile error shows in the
overlay while the page and its program go on, the fix reloads with the count
kept), and natively in a window under Xvfb (`dev-native.mjs`: the same
through the process's restarts). Each prints its reloads' times.

