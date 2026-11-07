import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

using StringTools;

// The checks, from the repository's root, with @hxmc/cli's compiler (`haxe`,
// node_modules/.bin on the PATH):
//
//   bun run test                   the headless lanes (no GPU, display or browser)
//   bun run test <lane> ...        those lanes (-k: the next one after a failure,
//                                  headless's too; every failure listed at the end)
//   bun run test help              the lanes
//
// Outputs go to bin/<lane>. GFX_TARGET and AUDIO_TARGET (the host's by
// default) cross-compile the native programs (windows-x86_64: run under
// Wine). BLESS=1 rewrites the golden files of the lanes that have them. The
// browser lanes need Playwright with Chromium (bun add --no-save playwright;
// bunx playwright install chromium); the gfx, ui-draw and 3d lanes Mesa and
// Xvfb on Linux.
class Run {
	static final TOOL = Sys.getEnv("HAXE") ?? (Sys.systemName() == "Windows" ? "haxe.cmd" : "haxe");
	static final NODE = Sys.getEnv("NODE") ?? "node";
	static final HOST = hostTarget();
	static final GFX_TARGET = Sys.getEnv("GFX_TARGET") ?? HOST;
	static final AUDIO_TARGET = Sys.getEnv("AUDIO_TARGET") ?? HOST;
	static final BLESS = Sys.getEnv("BLESS") != null && Sys.getEnv("BLESS") != "";
	// xvfb-run, returning once its X server is gone (tests/xvfb-run.sh: the
	// next one's display is not the last one's still letting go)
	static final XVFB = "sh " + FileSystem.fullPath("tests/xvfb-run.sh");

	static final HEADLESS = ["view", "text", "image", "ui", "gfx-shader", "async", "jobs", "test", "cli", "asset", "pack", "devtools", "typescript", "examples", "viewer", "canvas", "pdf", "syntax", "text-quality"];

	static final LANES:Array<{name:String, about:String, run:Void->Void}> = [
		{name: "headless", about: "the lanes that need no GPU, display or browser: " + HEADLESS.join(", "), run: () -> for (l in HEADLESS) lane(l)},
		{name: "view", about: "helder.view on Eval, natively and as JavaScript: signals, markup, control flow, the programs the macro rejects", run: view},
		{name: "text", about: "helder.text on Eval: the rasterizer, DejaVu Sans, line layout, a sample through the atlas (tests/text/sample.png)", run: text},
		{name: "image", about: "helder.image on Eval and natively: PNG, JPEG, GIF and WebP against Chromium's and libwebp's pixels, animations' frames; hxmc.unsafe's uses against the reviewed list (tests/image/unsafe.mjs); its limits and hostile headers are the test lane's (src/helder/image/ImageLimits.test.hx)", run: image},
		{name: "image-bench", about: "helder.image's speed (tests/bench/ImageBench.hx, natively): a JPEG decoded on one thread and four, at 1/8, a 256-pixel thumbnail, 50%, a large PNG; against vips, vipsthumbnail and Bun.Image where installed (tests/bench/image.mjs): bin/bench/image.md (IMAGE_BENCH_JPEG, IMAGE_BENCH_PNG)", run: imageBench},
		{name: "image-fuzz", about: "helder.image's decoders under a time-boxed mutation fuzzer (tests/image/Fuzz.hx, natively): the test images mutated, each input a decode or an ImageError within its time, the peak memory within budget (FUZZ_SECONDS, FUZZ_SEED)", run: imageFuzz},
		{name: "ui", about: "helder.ui on Eval: layout, events and focus, markup, the guide's examples", run: ui},
		{name: "gfx-shader", about: "helder.gfx's shader definitions on Eval: shaders on the CPU, the emitted GLSL, WGSL, MSL and HLSL, the programs they reject", run: gfxShader},
		{name: "async", about: "helder.async on Eval and natively (the loop, TCP, processes, the watcher, HTTP and WebSocket; its tasks and timers are the test lane's), as wasm32-wasi in the browser's loop (node), the async-dev example end to end, a benchmark", run: async},
		{name: "jobs", about: "helder.jobs: the sendable check's rejections (tests/jobs/reject); the pool, cancellation, errors and channels are the test lane's (tests/jobs/Jobs.test.hx, natively and on wasm32-wasi with node's workers)", run: jobsLane},
		{name: "jobs-web", about: "helder.jobs in headless Chromium: Web Workers instantiating the module, a cancelled one ended, the loop without frames (tests/jobs/JobsWeb.hx)", run: jobsWeb},
		{name: "app", about: "App.run turning helder.async's loop: a timer and a job's reply ending App.wait (tests/os/AppLoopTest.hx; Linux: Xvfb)", run: app},
		{name: "window", about: "helder.os's windows (tests/os/WindowTest.hx): files dropped through each system's own mechanism (X11: XDND from a second connection; Windows: WM_DROPFILES of an HDROP, also under Wine with GFX_TARGET=windows-x86_64; macOS: the window's dragging destination given a dragging info), moveTo and position, fullscreen asked; the platform's spellchecker (tests/text/SpellTest.hx: Enchant or Hunspell, ISpellChecker, NSSpellChecker; Wine has none); Windows' TSF for drawn text fields (tests/os/TsfTest.hx: the test the input method, through msctf and the store's composition sink; again with HELDER_NO_TSF=1; tests/ui/WinTextTest.hx: a drawn field typed into and composed in through it); Windows' UI Automation for the drawn tree (tests/ui/WinAccessTest.hx, WinPatternsTest.hx in process; WinAccessProbe.hx, IUIAutomation from another process, on AccessApp's fixture, todo, mail and guide; under Wine the tree and properties); macOS's NSAccessibility (tests/ui/MacAccessTest.hx, MacPatternsTest.hx, in process); helder.ui.menu's model as each platform's menus (tests/os/MenuTest.hx: macOS's NSMenu bar and roles, Windows' HMENU and accelerators, Linux's drawn bar and context menu driven by the keys, bin/os/menus-linux*.png) (Linux: Xvfb)", run: window},
		{name: "wayland", about: "helder.os on Wayland: the protocol bindings generated again from the system's XML (helder.os.wayland.Scanner) and compared with src/helder/os/wayland/protocol; then, where weston is installed, under a headless weston at scale 1 and 2 (tests/os/wayland.sh): tests/os/WaylandTest.hx (the back end chosen, configured, GL's frames through EGL on the wl_surface read back, the buffer at the scale, fullscreen and back, the clipboard; text-input-v3's requests where weston has it), the viewer showing a photo, the compositor's screenshot (bin/os/wayland-viewer.png); without weston, built only", run: wayland},
		{name: "viewer", about: "helder's image viewer (apps/viewer): its tests (the folder model, the decode cache, the camera's maths, a scripted run of the shell headless, its stories) natively and on Eval; its build for this machine", run: viewerApp},
		{name: "viewer-window", about: "the viewer in a real window on the GPU (GFX_TARGET's build: Linux under Xvfb, Windows under Wine from another host): a photo of the fixtures opened, decoded on helder.jobs and shown, closed after 3 s (--exit-after); again with no system font found (HELDER_NO_SYSTEM_FONTS=1: its own fallback font); a 9000x2000 PNG (apps/viewer/tests/bigpng.mjs) shown in tiles", run: viewerWindow},
		{name: "viewer-app", about: "macOS: the viewer as a universal app bundle (helder build --target macos: arm64 and x86_64, Info.plist's CFBundleDocumentTypes from helder.webmanifest's file_handlers), plutil and lipo's checks, then `open -a` with a file: Launch Services' open request reaching App.onOpen", run: viewerBundle},
		{name: "viewer-package", about: "the viewer's releases (helder build --package: helder.cli.Desktop, helder.pack): Linux's .tar.gz and Flatpak manifest (on Linux), Windows' zip signed by tests/pack/signing's throwaway identity, macOS's universal .app in a zip, ad hoc; checked on Eval (tests/pack/DesktopCheck.hx: the tarball's entries, the .desktop file, the icons, the metainfo; the .exe's GUI subsystem, resources, checksum and Authenticode digest; the bundle's seal and each slice's signature), then by osslsigncode verify, desktop-file-validate and appstreamcli where installed, codesign --verify on a Mac; the runtime objects of the other desktops fetched by tests/pack/runtime.mjs --desktop", run: viewerPackage},
		{name: "system-text", about: "helder.text on the platform's own stack (tests/text/SystemTextTest.hx, natively: Linux's fontconfig, HarfBuzz and FreeType, Windows' DirectWrite, macOS's Core Text): each script's fallback face, a family found, Devanagari, Bengali and Tamil shaped (reordered and split vowels), TextLayout through it, glyphs rasterised; each script drawn with the platform's engine and helder's (bin/text/system-<os>.png; GFX_TARGET=windows-x86_64 from Linux: under Wine)", run: systemText},
		{name: "text-quality", about: "helder.text's own engine against macOS's CoreText (tests/text/TextQuality.hx, natively): Inter Regular and Bold at seven sizes, DejaVu Sans at three and a paragraph, four inks on their pages, 1x and 2x, font smoothing on and off, the way the Renderer draws them, against CoreText's sheets of the same glyphs at the same pens (tests/text/coretext/sheets, drawn by the system-text lane on a Mac: CTFontDrawGlyphs through helder's Core Text back end): SSIM, the ink's weight, the pixels' differences, before (the rasterizer helder had) and now (bin/text-quality/report.md, heatmaps)", run: textQuality},
		{name: "system-images", about: "helder.os's system decoders (tests/os/SystemImagesTest.hx: Windows' WIC, macOS's ImageIO): a TIFF of a known gradient, plain and LZW, its pixels and straight alpha; macOS: a HEIC made by sips, whole and at a side; ImageLimits before any pixel; a file that is no image (GFX_TARGET=windows-x86_64 from Linux: under Wine)", run: systemImages},
		{name: "dbus", about: "helder.os's D-Bus client against a real dbus-daemon (Linux: dbus-run-session): Hello, ListNames, a service's half, then xdg-desktop-portal's FileChooser OpenFile against a stand-in portal (its arguments, its Response's URI as the path picked; tests/os/DBusTest.hx)", run: dbus},
		{name: "async-web", about: "helder.async's browser loop (wasm32-wasi) in headless Chromium: timers, tasks, cancellation, fetches", run: asyncWeb},
		{name: "test", about: "`helder test` (src/helder/cli) built natively, then every *.test.hx (helder.test) natively and as wasm32-wasi (node), and on Eval those that opt in (@:test.interp); every *.test.ts(x) (helder/test) natively and as wasm32-wasi, src/'s and examples/ts-todo's", run: helderTest},
		{name: "cli", about: "`helder build`, `run`, `dev` and `devices` (src/helder/cli): the grammar's errors and help, an example by file and by directory, a project, natively and for web (--target web); helder devices without adb and with a stand-in one; the dev loop natively (with the dev host and without) and for web without a window or a browser, and its exit policy: a crash keeps it up, the program closed ends it (tests/cli/dev.mjs, tests/cli/closer)", run: cli},
		{name: "asset", about: "helder.asset: the paths Asset's macros reject (tests/asset/reject), then `helder build tests/asset/Checksum.hx` for this machine (its files in the executable: run alone in an empty directory, their sizes and CRC-32s) and for the web (exactly the referenced files beside the page, the module run under node reading them); Android's and iOS's bundles are the pack lane's", run: assetLane},
		{name: "pack", about: "Android and iOS packaging (helder.pack): `helder build --target android, android-x86_64, ios, ios-sim` of tests/pack/Hello.hx, tests/pack/Screen.hx and of a project with an app's options (landscape, fullscreen), checked without a device (tests/pack/PackCheck.hx: the zip's layout and 16 KB alignment, the manifest, the library's ELF, the v2 signature recomputed and verified by openssl or apksigner; the bundle, Info.plist, the Mach-O's build version and code signature, its slots; Assets.car against Apple actool's structure; an .ipa signed for distribution with tests/pack/signing's throwaway identity, RSA and P-256, its CMS verified by openssl); helder run and the dev loop's protocol against stand-in adb and xcrun (tests/pack/dev.mjs); the runtime objects fetched by tests/pack/runtime.mjs (PACK_REQUIRE=1: missing ones a failure)", run: packLane},
		{name: "devtools", about: "the devtools protocol (src/helder/devtools): `helder dev` relaying a console and a ui program to a tool on its WebSocket, `helder inspect`, without a window (tests/devtools/devtools.mjs); the Frame domain's cost a frame", run: devtools},
		{name: "canvas", about: "helder.canvas: the reference scenes (tests/canvas/scenes.ts: fills, joins, caps, dashes, curves, arcs, gradients, patterns, clips, every composite and blend mode, transforms, images, pixels, text in several scripts) drawn by its DOM facade from TypeScript, natively, against Chromium's (tests/canvas/ref, made by chrome.mjs) within a tolerance (compare.mjs: bin/canvas/report.md, contact.png); WPT's Canvas 2D tests of paths, fills, strokes, line styles, compositing and transforms (tests/canvas/wpt: 523, the known failures listed); the DCE check (Linux: a path filled and a PNG with -dce full holds no gradient, blend mode, stroker, JPEG or text, dce.mjs); its unit tests are the test lane's (src/helder/canvas/*.test.hx)", run: canvasLane},
		{name: "canvas-gpu", about: "helder.canvas's GPU back end (helder.canvas.gpu, on helder.gfx; Linux: Mesa's llvmpipe): the canvas lane's reference scenes drawn by it (tests/canvas/render-gpu.ts) against the CPU back end's, the reference (compare.mjs: bin/canvas/gpu-report.md, gpu-report-contact.png); examples/canvas-window in a real window (Linux: Xvfb), its 30th frame checked", run: canvasGpu},
		{name: "canvas-web", about: "helder.canvas's web back end (helder.canvas.web: the browser's own Canvas 2D, src/helder/canvas/imports.mjs): the reference scenes as wasm32 (tests/canvas/render-web.ts) in headless Chromium (web.mjs), against Chromium's references (compare.mjs: bin/canvas/web-report.md); and the browser's image decoding (BrowserImages: WebDecode.hx, webdecode.mjs) against helder's decoders", run: canvasWeb},
		{name: "canvas-doc", about: "helder.canvas's documents (helder.canvas.doc): the reference scenes recorded by the DOM facade (tests/canvas/render-doc.ts) as one multi-page PDF (PdfWriter) and an SVG each (SvgWriter), the PDF drawn by poppler (pdftoppm, where installed) and the SVGs by Chromium (doc.mjs), against the CPU back end's pixels (compare.mjs: bin/canvas/pdf-report.md, svg-report.md; composite's unbounded operators and the dots of zero-length subpaths have no vector form; shadows and filters are not written yet)", run: canvasDoc},
		{name: "pdf", about: "helder.pdf: page 1 of each corpus PDF (tests/pdf/corpus, made by ReportLab, pypdf, LibreOffice and by hand: tests/pdf/corpus.py: the standard 14 fonts, Type 1, TrueType, Type 3, RC4, AES-128 and AES-256, object streams, a shading, a tiling pattern, an inline image, a damaged xref) drawn natively against pdf.js's (tests/pdf/ref, pdfjs.mjs): of the 3x3 blocks either inks at most 10% off, of the page 2%, and its text (Pdf.text) against pdf.js's getTextContent (check.mjs: bin/pdf/report.md); its crypto and limits are the test lane's (src/helder/pdf/*.test.hx)", run: pdfLane},
		{name: "pdf-fuzz", about: "helder.pdf under a time-boxed mutation fuzzer (tests/pdf/Fuzz.hx, natively): the corpus mutated, each mutant opened and drawn under small limits, ending in pixels or a PdfError (FUZZ_SECONDS, FUZZ_SEED)", run: pdfFuzz},
		{name: "typescript", about: "helder.typescript (TypeScript through tsgo straight to hxmc IR): the IR checks, then every program of tests/typescript compiled by tsc and run on node, and by helder's compiler (helder.compiler, with this frontend) natively and as wasm32-wasi, the outputs compared; the programs it must reject", run: () -> run(NODE, ["tests/typescript/run.mjs"])},
		{name: "typescript-native", about: "helder/native's definitions where their systems are (tests/typescript/native.mjs; the typescript lane runs it too): native.c (libc and libm on Linux, natively, static and glibc; Core Foundation on a Mac), native.objc (Foundation's NSProcessInfo and NSString on a Mac), native.com (WIC's factory, a bitmap's size read back, on Windows; on Linux under Wine with Windows' runtime objects), each refused where its system is not; native.jni's on Android is the android job's (tests/typescript/native/android.sh)", run: () -> run(NODE, ["tests/typescript/native.mjs"])},
		{name: "examples", about: "every example (Haxe, TypeScript) built by `helder build <file>` (--target web for the web) with no other flags, not run: for web (wasm32-wasi), and those on a canvas or playing a sound natively too; then the golf example's recorded rounds replayed natively and as wasm32-wasi (examples/golf/GolfReplay.hx)", run: examples},
		{name: "3d", about: "helder.scene and helder.physics: unit tests on Eval, natively and as wasm32-wasi, input actions, the renderer's frames against golden images (Mesa), helder/scene's from TypeScript (tests/3d/ts/frames.ts)", run: scene},
		{name: "3d-web", about: "helder.scene's frames on WebGPU and WebGL2 in headless Chromium", run: sceneWeb},
		{name: "gfx", about: "helder.gfx: the examples headless and in a window against golden images (tests/gfx/check.sh; Linux: Mesa, Xvfb)", run: gfx},
		{name: "gfx-shared", about: "helder.gfx's shared textures between two processes (tests/gfx/SharedTexture.hx, GFX_TARGET's build): a producer draws into a texture it shares (Device.createShared: an IOSurface on macOS, a DXGI texture with a keyed mutex on Windows, a dma-buf where EGL exports one on Linux), the consumer opens it (openShared), draws it with helder.ui's renderer and reads back each quarter's colour, then a second frame drawn into the same texture; required on macOS and Windows, skipped where the GPU shares none (llvmpipe without udmabuf, Wine): helder.story's native preview host's way to the studio", run: gfxShared},
		{name: "sprite", about: "helder.sprite's SpriteBatch on a GPU, headless (tests/sprite/SpriteFrame.hx; Linux: Mesa): sprites placed, scaled, turned, faded and added, two textures; its CPU half and the atlas are the test lane's", run: sprite},
		{name: "gfx-web", about: "helder.gfx on WebGPU and WebGL2 (wasm32-wasi) in headless Chromium", run: gfxWeb},
		{name: "audio", about: "helder.os's audio through each back end without speakers (tests/os/audio.sh)", run: audio},
		{name: "audio-web", about: "helder.os's audio on WebAudio in headless Chromium", run: audioWeb},
		{name: "touch-web", about: "helder.os's pointers in headless Chromium: two fingers, a pen, the mouse, samples, a cancel, a tap and a drag without mouse events or scrolls, a pointer event sent from JavaScript (tests/os/PointersWeb.hx); App.onBack and App.backDepth's history entry, history back, Escape as the back, haxe.Timer.delay in App.run (tests/os/BackWeb.hx); Pointers' own tests are the test lane's (src/helder/os/Pointers.test.hx)", run: touchWeb},
		{name: "web", about: "helder.web: the static renderer on Eval and natively, then the DOM renderer, the demo page, islands and wasm in headless Chromium", run: web},
		{name: "compiler-web", about: "helder.compiler.web, helder's toolchain as wasm in a worker: its modules built (src/helder/compiler/web/build.mjs: bin/compiler-web), todo and ts-todo checked and built in node (tests/compiler-web/node.mjs: warm, a type error, a check writing nothing), then in headless Chromium the worker loaded (brotli), both built to wasm32 on the page and each run in a frame of its own (preview.mjs), a literal edit patched with no build and a structural one built and swapped in, each read back from the program's view (Ui.getTree), and the numbers printed (tests/compiler-web/browser.mjs)", run: compilerWeb},
		{name: "ui-draw", about: "helder.ui's GPU renderer and its programs against golden images (Linux: Mesa, Xvfb, AT-SPI)", run: uiDraw},
		{name: "syntax", about: "helder.syntax, the syntax trees the studio edits (src/helder/syntax; its edits' tests are the test lane's, Syntax.test.hx): every .ts and .tsx file, and every .hx file with markup, of the repository read and printed back byte for byte, read structurally, each Haxe markup literal read as the macro's parser reads it (tests/syntax/Check.hx, on Eval and natively: the read of the largest file timed)", run: syntaxLane},
		{name: "syntax-run", about: "helder.syntax's edits on the examples (tests/syntax/Examples.hx; Linux: Mesa's llvmpipe, no display): todo, ts-todo, mail, the guide's screen and the viewer's shell and shader copied into bin/syntax/run and edited (attributes set, added and removed, literals, children inserted, elements moved, deleted, wrapped, unwrapped and renamed, a component renamed, a definition's field), each edit's change only in its span and undone by its inverse; each built and run headless (helder run --headless), its --tree showing each change; ts-todo's story renamed and its tests run (helder test)", run: syntaxRun},
		{name: "studio", about: "helder studio (apps/studio; Linux: Mesa's llvmpipe, no display) run headless on copies of examples/todo and examples/ts-todo by tests/studio/edit.json: every screen shown (the stories in one dev build's process, helder.story.NativeHost: its frames shared GPU textures, else shared memory, llvmpipe's), one zoomed into, its title clicked and selected, its colour changed in the inspector (the value's span alone, a live literal patched, the program's frame showing it within 3 frames), a padding added and undone (built twice), tag=\"title\" typed into the code view (built, the node tagged), the prompt bar's /tree; the files at the end and every edit's span checked, the overview, zoomed and selected frames against tests/studio's goldens, the times printed (tests/studio/Check.hx); `helder studio --help`", run: studioLane},
		{name: "demos", about: "the showcase demos run headless (Linux: Mesa's llvmpipe, no display) at half scale: examples/showreel's scenes each by --scene, examples/fx's gallery, its --tour with an effect open and its reduced-motion stills, examples/literal's and examples/notes' demo scripts (their pointer and keys); each one's stills at a few times against tests/demos's goldens, within a tolerance (tests/demos/Check.hx)", run: demosLane},
		{name: "studio-web", about: "helder studio in the browser (apps/studio/web: the studio built for the web, its projects in OPFS, the preview host in a worker, helder.story.web.Preview) in headless Chromium on WebGPU (tests/studio-web/check.mjs): examples/todo opened from the welcome, all screens shown, one zoomed into, its title selected, its colour changed in the inspector (a live literal patched in the worker's preview, the next frames showing it, the file saved in OPFS), a padding added (built by the compiler's worker, helder.compiler.web's toolchain built as the compiler-web lane builds it, and the preview swapped in with its state); at a phone's width with touches: the inspector a bottom sheet, a tap selecting, a pinch zooming, the screens' drawer; 50 screens (tests/story/host/host.mjs project) opened, timed and measured; the overview and zoomed states against tests/studio-web's goldens at both widths: bin/studio-web/results.md", run: studioWeb},
		{name: "story-host", about: "helder.story.Host, the studio's preview host (Linux: Mesa's llvmpipe, no display): 50 stories of examples/todo (tests/story/host/host.mjs gen) mounted in one program, each its own root and ScreenContext, drawn offscreen and read back; then the desktop studio (apps/studio, headless) on the same stories as a project, its one preview process (helder.story.NativeHost: shared GPU textures, else shared memory): the start to every screen's first frame and the memory then (resident, Pss: the host's and the studio's), an inspector's colour change to the host's new frame (tests/story/host/studio.json); the headless host's turns with one screen focused (only it draws) and none (none draws): bin/story-host/results.md", run: storyHost},
		{name: "motion-bench", about: "helder.ui.motion's budget measured (Linux: Mesa's llvmpipe, no display): tests/bench/MotionStress.hx, 1,000 boxes under motion retargeted every 0.25 s, run headless with --stats, against the same boxes drawn each frame without motion: ms a frame (median, p95) between retargets and at them, GC bytes a frame (checked: as many moving as still, no allocation in the steady state): bin/motion-bench/results.md", run: motionBench},
		{name: "code-bench", about: "helder.ui.code's budgets measured, not checked (Linux: Mesa's llvmpipe, no display): examples/code-editor on a 10,000-line TSX file run headless with --stats (tests/bench/code.mjs: keystrokes, the wheel down and back up, idle frames: ms against the 8 ms budget, GC bytes a frame), and the editor's own work without the renderer (tests/bench/CodeBench.hx, natively)", run: codeBench},
		{name: "million-bench", about: "helder.ui's VirtualList measured, not checked (Linux: Mesa's llvmpipe, no display): examples/million (a million rows of their own heights) run headless with --stats on a script of the wheel over new rows and over rows made before, jumps to the end and back, rows put in above the view and the keyboard (tests/bench/million.mjs: each phase's ms and GC bytes a frame against the 8 ms budget), then tests/bench/MillionBench.hx: the list's own work a frame natively without the renderer, and what it holds (tests/bench/results/million.md)", run: millionBench},
		{name: "headless-run", about: "`helder run --headless` (helder.headless; Linux: Mesa's llvmpipe, no display): examples/todo and examples/ts-todo driven by one script (tests/headless/todo.json: typed into, Enter, the Add button, a checkbox by its role and label, a filter), their --tree at a mark and at the end checked, their --snap against tests/headless's goldens, the --trace's lines, --frames with --every and keycaps; examples/glow's --snap at 0.5 s against its golden; examples/million and ts-million (a VirtualList of a million rows of their own heights, tests/headless/million.json: the wheel, End, the keyboard, the selection through recycling, rows put in above the view; their trees' options, places and rects at each mark, their last frame against its golden); examples/code-editor (helder.ui.code) on a 2,000-line TSX file (tests/headless/code-editor.json: a word double-clicked and typed over, go to line, three cursors by secondary-D, undo and redo, find and replace all, a drag), its text and status bar at each mark and its last frame against its golden; apps/viewer opening a file through its file dialog (the script's answer) and a context menu's item picked (tests/headless/viewer.json; its status bar shown by its key, its store empty as in every headless run); examples/todo's and ts-todo's dev builds with a live literal's colour and a text patched by the script (tests/headless/literals.json: helder.dev.Literals), the frame after showing them; all run twice, the outputs byte for byte the same (tests/headless/Check.hx); a --video when ffmpeg is installed", run: headlessRun},
		{name: "ui-web", about: "the todo example, text editors and the accessibility fixture's ARIA mirror (web-access.mjs) as wasm32-wasi in headless Chromium", run: uiWeb},
		{name: "bench", about: "the engine's benchmarks (tests/bench) natively and as wasm32-wasi, and the examples' sizes and compile times: a table (bin/bench/results.md)", run: bench},
		{name: "jobs-bench", about: "background work against the main thread's frames: a 4K PNG decoded between frames, as a GC job, as a GC-free job on off-heap memory (IoBuffer), natively and as wasm32-wasi workers, by hand (tests/bench/Jobs.hx) and through helder.jobs (JobsApi.hx), and a job's round trip: a table (bin/jobs/results.md)", run: jobs},
		{name: "dev", about: "the dev loop: helder.dev.Hot and view's signals across a reload, then `haxe --dev` in Chromium and natively", run: dev},
		{name: "edit-loop", about: "the edit loop's times (tests/edit-loop/edit-loop.mjs): `helder dev` warm on copies of examples/todo and examples/ts-todo in a window (Linux: Xvfb), a literal, a component's body and a new component edited, each timed from the save to the new frame and split by where the time went (the watcher, tsgo, typing, lowering, codegen, link, the reload, the first frame): bin/edit-loop/results.md", run: editLoop},
		{name: "dev-host", about: "helder dev's host (helder.dev.DevHost): three builds of a program as shared libraries swapped in one process and window (tests/os/dev/dev-host.mjs); DEV_HOST_TARGETS (comma-separated) cross-compiles for others too (windows-x86_64: run under Wine; macos-*: built only)", run: devHost},
	];

	static function main() {
		// (helder.text's own engine for every lane's program: goldens the same on every OS; system-text's the platform's)
		if (Sys.getEnv("HELDER_TEXT_ENGINE") == null) Sys.putEnv("HELDER_TEXT_ENGINE", "helder");
		var args = Sys.args();
		var keepGoing = args.remove("-k");
		if (args.length == 0) args = ["headless"];
		if (args.contains("help")) {
			Sys.println("bun run test [-k] <lane> ...\n");
			for (l in LANES) Sys.println("  " + l.name.rpad(" ", 15) + " " + l.about);
			return;
		}
		// (headless as its lanes, each run on its own: with -k every one runs
		// and each failure is reported, not the first alone)
		args = [for (a in args) for (l in (a == "headless" ? HEADLESS : [a])) l];
		var failed = [];
		for (a in args) {
			try {
				lane(a);
			} catch (e:Failed) {
				Sys.println('\n$a: FAILED: ${e.message}');
				failed.push(a);
				if (!keepGoing) break;
			}
		}
		if (failed.length > 0) {
			Sys.println("failed: " + failed.join(", "));
			Sys.exit(1);
		}
	}

	static function lane(name:String) {
		var l = Lambda.find(LANES, l -> l.name == name);
		if (l == null) throw new Failed('no lane $name (bun run test help)');
		Sys.println('--- $name');
		l.run();
	}

	// --- the lanes

	static function view() {
		var cp = cps(["src", "tests/view"]);
		interp(cp, "ViewTest", [TOOL]);
		exe("bin/view/ViewTest", cp.concat(["-main", "ViewTest"]));
		run(exePath("bin/view/ViewTest", HOST), []);
		js("bin/view/ViewTest.js", cp.concat(["-main", "ViewTest"]));
		run(NODE, ["bin/view/ViewTest.js"]);
	}

	static function text() {
		mkdirs("bin");
		interp(cps(["src", "tests/text", "tests/gfx"]), "TextTest", BLESS ? ["--bless"] : []);
	}

	static function image() {
		var cp = cps(["src", "tests/image"]);
		interp(cp, "ImageTest");
		exe("bin/image/ImageTest", cp.concat(["-main", "ImageTest"]));
		run(exePath("bin/image/ImageTest", HOST), []);
		run(NODE, ["tests/image/unsafe.mjs"]);
	}

	// (IMAGE_BENCH_JPEG, IMAGE_BENCH_PNG: the files, a photo and a large PNG;
	// by default the repository's largest: examples' comparison.jpg, tests/ui/todo.png)
	static function imageBench() {
		exe("bin/bench/ImageBench", cps(["src", "tests/bench"]).concat(["-main", "ImageBench"]));
		run(NODE, ["tests/bench/image.mjs", exePath("bin/bench/ImageBench", HOST), Sys.getEnv("IMAGE_BENCH_JPEG") ?? "examples/gltf-showcase/comparison.jpg",
			Sys.getEnv("IMAGE_BENCH_PNG") ?? "tests/ui/todo.png"]);
	}

	// (FUZZ_SECONDS: the budget, 30 s by default; FUZZ_SEED: where it starts)
	static function imageFuzz() {
		exe("bin/image/Fuzz", cps(["src", "tests/image"]).concat(["-main", "Fuzz"]));
		run(exePath("bin/image/Fuzz", HOST), [Sys.getEnv("FUZZ_SECONDS") ?? "30", Sys.getEnv("FUZZ_SEED") ?? "1"]);
	}

	static function pdfLane() {
		exe("bin/pdf/PdfRender", cps(["src", "tests/pdf"]).concat(["-main", "PdfRender"]).concat(targetArgs(HOST)));
		run(exePath("bin/pdf/PdfRender", HOST), []);
		run(NODE, ["tests/pdf/check.mjs", "bin/pdf/ours", "tests/pdf/ref", "bin/pdf/report"]);
	}

	static function pdfFuzz() {
		exe("bin/pdf/Fuzz", cps(["src", "tests/pdf"]).concat(["-main", "Fuzz"]).concat(targetArgs(HOST)));
		run(exePath("bin/pdf/Fuzz", HOST), [Sys.getEnv("FUZZ_SECONDS") ?? "30", Sys.getEnv("FUZZ_SEED") ?? "1"]);
	}

	static function canvasDoc() {
		var compiler = StringTools.trim(output(NODE, ["src/helder/compiler/build.mjs", "--quiet"]));
		mkdirs("bin/canvas/ours");
		mkdirs("bin/canvas/doc");
		run(compiler, ["tests/canvas/render.ts", "-o", exePath("bin/canvas/render", HOST)].concat(targetArgs(HOST)));
		run(exePath("bin/canvas/render", HOST), []);
		run(compiler, ["tests/canvas/render-doc.ts", "-o", exePath("bin/canvas/render-doc", HOST)].concat(targetArgs(HOST)));
		File.saveContent("bin/canvas/doc.txt", output(exePath("bin/canvas/render-doc", HOST), []));
		run(NODE, ["tests/canvas/doc.mjs", "bin/canvas/doc.txt"]);
		// (raster fallbacks drawn at twice the size, then scaled by the viewer: images and patterns softer)
		var own = "composite=skip,caps=skip,images=0.1,patterns=0.15,shadows=skip,filters=skip";
		if (FileSystem.exists("bin/canvas/pdf/fill-nonzero.png")) run(NODE, ["tests/canvas/compare.mjs", "bin/canvas/pdf", "bin/canvas/ours", "bin/canvas/pdf-report", "white", own]);
		run(NODE, ["tests/canvas/compare.mjs", "bin/canvas/svg", "bin/canvas/ours", "bin/canvas/svg-report", "-", own]);
	}

	static function canvasWeb() {
		var compiler = StringTools.trim(output(NODE, ["src/helder/compiler/build.mjs", "--quiet"]));
		run(compiler, ["tests/canvas/render-web.ts", "-o", "bin/canvas/render-web.wasm"].concat(targetArgs("wasm32-wasi")));
		run(NODE, ["tests/canvas/web.mjs", "bin/canvas/render-web.wasm"]);
		// (the references are Chromium 153's; CI's Playwright has 141, whose zero-length subpaths' caps differ: caps looser)
		run(NODE, ["tests/canvas/compare.mjs", "bin/canvas/web", "tests/canvas/ref", "bin/canvas/web-report", "-", "caps=0.03"]);
		// (the browser's decoding: BrowserImages against helder's decoders)
		wasm("bin/canvas/WebDecode.wasm", cps(["src", "tests/canvas"]).concat(["-main", "WebDecode"]));
		run(NODE, ["tests/canvas/webdecode.mjs", "bin/canvas/WebDecode.wasm"]);
	}

	static function canvasGpu() {
		var compiler = StringTools.trim(output(NODE, ["src/helder/compiler/build.mjs", "--quiet"]));
		var args = targetArgs(GFX_TARGET);
		mkdirs("bin/canvas/ours");
		mkdirs("bin/canvas/gpu");
		run(compiler, ["tests/canvas/render.ts", "-o", exePath("bin/canvas/render", HOST)].concat(targetArgs(HOST)));
		run(exePath("bin/canvas/render", HOST), []);
		run(compiler, ["tests/canvas/render-gpu.ts", "-o", exePath("bin/canvas/render-gpu", GFX_TARGET)].concat(args));
		Sys.putEnv("LIBGL_ALWAYS_SOFTWARE", "1");
		run(exePath("bin/canvas/render-gpu", GFX_TARGET), []);
		run(NODE, ["tests/canvas/compare.mjs", "bin/canvas/gpu", "bin/canvas/ours", "bin/canvas/gpu-report"]);
		// (in a window: examples/canvas-window's 30th frame, the canvas read back: something drawn)
		native("bin/canvas/canvas-window", cps(["src", "examples/canvas-window"]).concat(["-main", "CanvasWindow"]), GFX_TARGET);
		var cmd = exePath("bin/canvas/canvas-window", GFX_TARGET) + " --shot bin/canvas/window.png";
		if (Sys.systemName() == "Linux") shell('$XVFB -a $cmd') else shell(cmd);
		run(NODE, ["tests/canvas/window.mjs", "bin/canvas/window.png"]);

	}

	static function canvasLane() {
		var compiler = StringTools.trim(output(NODE, ["src/helder/compiler/build.mjs", "--quiet"]));
		var args = targetArgs(HOST);
		mkdirs("bin/canvas/ours");
		run(compiler, ["tests/canvas/render.ts", "-o", exePath("bin/canvas/render", HOST)].concat(args));
		run(exePath("bin/canvas/render", HOST), []);
		run(NODE, ["tests/canvas/compare.mjs", "bin/canvas/ours", "tests/canvas/ref", "bin/canvas/report"]);
		run(compiler, ["tests/canvas/wpt.ts", "-o", exePath("bin/canvas/wpt", HOST)].concat(args));
		File.saveContent("bin/canvas/wpt.txt", output(exePath("bin/canvas/wpt", HOST), []));
		run(NODE, ["tests/canvas/wpt/check.mjs", "bin/canvas/wpt.txt"]);
		if (Sys.systemName() == "Linux") {
			var cp = cps(["src", "tests/canvas"]).concat(targetArgs(HOST));
			for (m in ["Tiny", "Full"]) {
				exe('bin/canvas/$m', cp.concat(["-main", m, "-dce", "full"]));
				exe('bin/canvas/$m-sym', cp.concat(["-main", m, "-dce", "full", "-D", "hxmc.symbols"]));
				run(exePath('bin/canvas/$m', HOST), []);
			}
			run(NODE, ["tests/canvas/dce.mjs", "bin/canvas/Tiny", "bin/canvas/Tiny-sym", "bin/canvas/Full", "bin/canvas/Full-sym"]);
		}
	}

	static function ui() {
		var cp = cps(["src", "tests/ui"]);
		interp(cp, "UiTest");
		interp(cp, "MarkupTest");
		interp(cp, "GuideTest");
	}

	static function gfxShader() {
		interp(cps(["src", "tests/gfx"]).concat(cps(GFX_EXAMPLES)), "ShaderTest", [TOOL].concat(BLESS ? ["--bless"] : []));
	}



	// (ASYNC_TARGETS: the example also built for those, comma-separated, e.g.
	// macos-arm64,windows-x86_64: their runtime objects installed)
	static function async() {
		var cp = cps(["src", "tests/async"]);
		interp(cp, "AsyncTest");
		exe("bin/async/AsyncTest", cp.concat(["-main", "AsyncTest"]));
		run(exePath("bin/async/AsyncTest", HOST), []);
		wasm("bin/async/WebTest.wasm", cp.concat(["-main", "WebTest"]));
		run(NODE, ["tests/async/web.mjs", "bin/async/WebTest.wasm"]);
		var dev = cps(["src", "examples/async-dev"]).concat(["-main", "AsyncDev"]);
		exe("bin/async/AsyncDev", dev);
		Sys.println('AsyncDev: ${Math.round(FileSystem.stat(exePath("bin/async/AsyncDev", HOST)).size / 1024)} KB');
		run(NODE, ["tests/async/dev.mjs", exePath("bin/async/AsyncDev", HOST), "bin/async"]);
		for (t in (Sys.getEnv("ASYNC_TARGETS") ?? "").split(","))
			if (t != "") native('bin/async/$t/AsyncDev', dev, t);
		exe("bin/async/AsyncBench", cp.concat(["-main", "AsyncBench"]));
		run(exePath("bin/async/AsyncBench", HOST), []);
	}

	// (the sendable check: a program it rejects, with the message expected)
	static function jobsLane() {
		var cp = cps(["src", "tests/jobs/reject"]);
		for (r in [
			{main: "NotSendable", want: "helder.jobs: count's input cannot be sent: .items[]: Item is a class"},
			{main: "NotSendableChannel", want: "helder.jobs: a Channel's value cannot be sent: Int -> Void is a function"}
		]) {
			var b = build(cp.concat(["-main", r.main, "--custom-target", 'hxmc=bin/jobs/reject/${r.main}']), 'bin/jobs/reject/${r.main}.log');
			if (b.code == 0 || !b.log.contains(r.want)) throw new Failed('${r.main}: expected the error "${r.want}":\n' + b.log);
			Sys.println('${r.main}: rejected');
		}
	}

	static function jobsWeb() {
		wasm("bin/jobs/JobsWeb.wasm", cps(["src", "tests/jobs"]).concat(["-main", "JobsWeb"]));
		run(NODE, ["tests/jobs/browser.mjs", "bin/jobs/JobsWeb.wasm"]);
	}

	static function app() {
		native('bin/os/$GFX_TARGET/AppLoopTest', cps(["src", "tests/os"]).concat(["-main", "AppLoopTest"]), GFX_TARGET);
		var exe = exePath('bin/os/$GFX_TARGET/AppLoopTest', GFX_TARGET);
		if (GFX_TARGET.startsWith("linux-")) shell('$XVFB -a ' + exe) else run(exe, []);
	}

	// (the viewer's own tests from its directory, its project: helder test there)
	static function viewerApp() {
		var h = FileSystem.fullPath(helderCli());
		var here = Sys.getCwd();
		Sys.setCwd("apps/viewer");
		// (natively, and on Eval its logic that opts in: the viewer is a desktop app)
		try run(h, ["test", "--target", "host,interp"]) catch (e:Failed) {
			Sys.setCwd(here);
			throw e;
		}
		Sys.setCwd(here);
		run(h, ["build", "apps/viewer"]);
	}

	// (GFX_TARGET's build, run on the fixtures with --exit-after: Linux under
	// Xvfb, a Windows target on another host under Wine)
	static function viewerWindow() {
		var h = helderCli();
		run(h, ["build", "--target", GFX_TARGET, "apps/viewer"]);
		var exe = exePath('apps/viewer/bin/$GFX_TARGET/viewer', GFX_TARGET);
		var wine = GFX_TARGET.startsWith("windows-") && !HOST.startsWith("windows-") ? "wine " : "";
		var cmd = '$wine$exe --new --exit-after 3 "apps/viewer/tests/fixtures/folder/photo 2.jpg"';
		var out = 'bin/viewer-window.txt';
		mkdirs("bin");
		if (Sys.systemName() == "Linux") shell('$XVFB -a $cmd > $out') else shell('$cmd > $out');
		var said = File.getContent(out);
		Sys.print(said);
		if (said.indexOf("viewer: photo 2.jpg · 5 / 6 · 1242×1048 (shown") < 0) throw new Failed('the viewer did not show the photo: $said');
		// (its main screen's accessibility tree read whole over AT-SPI, as the ui-draw lane reads AccessApp's: Linux's)
		if (GFX_TARGET.startsWith("linux-") && Sys.systemName() == "Linux") {
			native('bin/ui/$GFX_TARGET/AtspiProbe', uiCp().concat(["-main", "AtspiProbe"]), GFX_TARGET);
			shell('$XVFB -a dbus-run-session -- sh -c \'$exe --new --exit-after 30 "apps/viewer/tests/fixtures/folder/photo 2.jpg" & p=$$!; '
				+ 'bin/ui/$GFX_TARGET/AtspiProbe "photo 2" "image:photo 2.jpg · 5 / 6 · 1242×1048" "menu item:File" "menu item:View"; s=$$?; kill $$p; exit $$s\'');
		}
		// (a PDF's first page, its pages counted)
		var pdf = '$wine$exe --new --exit-after 3 apps/viewer/tests/fixtures/pdf/pages.pdf';
		if (Sys.systemName() == "Linux") shell('$XVFB -a $pdf > $out') else shell('$pdf > $out');
		said = File.getContent(out);
		Sys.print(said);
		if (said.indexOf("viewer: pages.pdf · 1 / 1 · page 1 / 3 (shown") < 0) throw new Failed('the viewer did not show the PDF\'s first page: $said');
		// (again with no system font found: its own, not a stop)
		var nofont = 'HELDER_NO_SYSTEM_FONTS=1 $cmd';
		if (Sys.systemName() == "Linux") shell('HELDER_NO_SYSTEM_FONTS=1 $XVFB -a $cmd > $out') else shell('$nofont > $out');
		said = File.getContent(out);
		Sys.print(said);
		if (said.indexOf("(shown") < 0) throw new Failed('without system fonts, the viewer did not show the photo: $said');
		// (an image past a texture's side: in tiles)
		mkdirs("bin/viewer");
		run(NODE, ["apps/viewer/tests/bigpng.mjs", "bin/viewer/wide.png", "9000", "2000"]);
		var wide = '$wine$exe --new --exit-after 4 bin/viewer/wide.png';
		if (Sys.systemName() == "Linux") shell('$XVFB -a $wide > $out') else shell('$wide > $out');
		said = File.getContent(out);
		Sys.print(said);
		if (said.indexOf("9000×2000 (shown") < 0) throw new Failed('the viewer did not show a 9000x2000 PNG in tiles: $said');
		// (one viewer: a second launch hands its file to the first, which shows it)
		var first = '$wine$exe --exit-after 6 apps/viewer/tests/fixtures/folder/alpha.png > bin/viewer/first.txt';
		var second = '$wine$exe "apps/viewer/tests/fixtures/folder/photo 2.jpg" > bin/viewer/second.txt';
		var both = '$first & sleep 3; $second; wait';
		if (Sys.systemName() == "Linux") shell('$XVFB -a sh -c \'$both\'') else shell(both);
		var a = File.getContent("bin/viewer/first.txt"), b = File.getContent("bin/viewer/second.txt");
		Sys.print(b + a);
		if (b.indexOf("handed to the running viewer") < 0 || a.indexOf("viewer: photo 2.jpg") < 0) throw new Failed('the second launch did not hand its file to the first: $b / $a');
		// (the file types registered: Windows' registry, Linux's .desktop file)
		if (!GFX_TARGET.startsWith("macos-")) {
			shell('$wine$exe --register > bin/viewer/register.txt');
			var r = File.getContent("bin/viewer/register.txt");
			Sys.print(r);
			if (r.indexOf(GFX_TARGET.startsWith("windows-") ? "helder-viewer.file\\shell\\open\\command" : "helder-viewer.desktop") < 0) throw new Failed('--register: $r');
		}
	}

	// (macOS: the universal bundle, its Info.plist and slices checked by
	// Apple's tools, then opened by Launch Services with a file: the file
	// reaching the app as an open request, App.onOpen)
	static function viewerBundle() {
		var h = helderCli();
		run(h, ["build", "--target", "macos", "apps/viewer"]);
		var app = "apps/viewer/bin/macos/Viewer.app";
		run("plutil", ["-lint", '$app/Contents/Info.plist']);
		shell('lipo -archs $app/Contents/MacOS/viewer | grep -q "x86_64 arm64\\|arm64 x86_64"');
		var report = FileSystem.fullPath("bin") + "/viewer-app.txt";
		if (FileSystem.exists(report)) FileSystem.deleteFile(report);
		// (absolute: open -a takes a relative path for an application's name)
		var abs = FileSystem.fullPath(app), photo = FileSystem.fullPath("apps/viewer/tests/fixtures/folder/photo 2.jpg");
		shell('open -W -n -a "$abs" "$photo" --args --new --exit-after 5 --report "$report"');
		var said = FileSystem.exists(report) ? File.getContent(report) : "(no report)";
		Sys.print(said);
		if (said.indexOf("viewer: photo 2.jpg") < 0) throw new Failed('the bundle, opened with a file, did not show it: $said');
		// (sealed and signed ad hoc by helder: codesign's own check of the bundle)
		run("codesign", ["--verify", "--deep", "--strict", "-vvvv", app]);
		run("codesign", ["-dvvv", app]);
	}

	// (the releases of the three desktops from this machine: Linux's on
	// Linux, Windows' and macOS's with their runtime objects from npm)
	static function viewerPackage() {
		var h = helderCli();
		run(NODE, ["tests/pack/runtime.mjs", "bin/pack/rt", "--desktop"]);
		var rt = FileSystem.fullPath("bin/pack/rt"), out = "bin/viewer-package";
		rmrf(out);
		mkdirs(out);
		var id = "org.helder.viewer", made = [];
		if (HOST.startsWith("linux-")) {
			run(h, ["build", "--target", HOST, "--package", "apps/viewer", "-o", out]);
			made.push('$out/' + [for (f in FileSystem.readDirectory(out)) if (f.endsWith(".tar.gz")) f][0]);
		}
		var signing = FileSystem.fullPath("tests/pack/signing");
		if (FileSystem.exists('$rt/windows-x86_64/rt.o')) {
			run(h, ["build", "--target", "windows-x86_64", "--package", "apps/viewer", "-o", out], [
				"HXMC_RT_DIR" => rt,
				"HELDER_WINDOWS_CERTIFICATE" => '$signing/cert.pem',
				"HELDER_WINDOWS_KEY" => '$signing/key.pem',
				"HELDER_WINDOWS_TIMESTAMP_URL" => "none"
			]);
			made.push('$out/' + [for (f in FileSystem.readDirectory(out)) if (f.indexOf("windows") > 0) f][0]);
		} else Sys.println("viewer-package: no windows-x86_64 runtime objects: its package skipped");
		if (FileSystem.exists('$rt/macos-arm64/rt.o') && FileSystem.exists('$rt/macos-x86_64/rt.o')) {
			run(h, ["build", "--target", "macos", "--package", "apps/viewer", "-o", out], ["HXMC_RT_DIR" => rt]);
			made.push('$out/' + [for (f in FileSystem.readDirectory(out)) if (f.indexOf("macos") > 0) f][0]);
		} else Sys.println("viewer-package: no macOS runtime objects: its package skipped");
		interp(cps(["src", "tests/pack"]), "DesktopCheck", [out, id].concat(made));
		var have = (tool:String) -> try {
			var p = new Process(Sys.systemName() == "Windows" ? "where" : "which", [tool]);
			var ok = p.exitCode() == 0;
			p.close();
			ok;
		} catch (_:Dynamic) false;
		if (FileSystem.exists('$out/check/viewer.exe')) {
			if (have("osslsigncode")) run("osslsigncode", ["verify", "-in", '$out/check/viewer.exe', "-CAfile", '$signing/ca.pem']);
			else Sys.println("viewer-package: no osslsigncode: the Authenticode signature checked by DesktopCheck alone");
		}
		if (FileSystem.exists('$out/check/$id.desktop') && have("desktop-file-validate")) run("desktop-file-validate", ['$out/check/$id.desktop']);
		if (FileSystem.exists('$out/check/$id.metainfo.xml') && have("appstreamcli")) run("appstreamcli", ["validate", "--no-net", '$out/check/$id.metainfo.xml']);
		if (HOST.startsWith("macos-")) {
			var zip = [for (f in FileSystem.readDirectory(out)) if (f.indexOf("macos") > 0) f][0];
			if (zip != null) {
				mkdirs('$out/unzipped');
				run("ditto", ["-x", "-k", '$out/$zip', '$out/unzipped']);
				run("codesign", ["--verify", "--deep", "--strict", "-vvvv", '$out/unzipped/Viewer.app']);
			}
		}
	}

	// (Windows and macOS; a Windows target from Linux under Wine; macOS: a HEIC made by sips)
	static function systemText() {
		native('bin/text/$GFX_TARGET/SystemTextTest', cps(["src", "tests/text"]).concat(["-main", "SystemTextTest"]), GFX_TARGET);
		var exe = exePath('bin/text/$GFX_TARGET/SystemTextTest', GFX_TARGET), env = ["HELDER_TEXT_ENGINE" => "system"];
		if (GFX_TARGET.startsWith("windows-") && !HOST.startsWith("windows-")) {
			env.set("HELDER_UNDER_WINE", "1");
			run("wine", [exe], env);
		} else run(exe, [], env);
		// (on a Mac: CoreText's sheets for the text-quality lane, bin/text/coretext: tests/text/coretext/sheets is a copy)
		if (GFX_TARGET.startsWith("macos-") && HOST.startsWith("macos-")) {
			native('bin/text/$GFX_TARGET/TextQuality', cps(["src", "tests/text"]).concat(["-main", "TextQuality"]), GFX_TARGET);
			run(exePath('bin/text/$GFX_TARGET/TextQuality', GFX_TARGET), ["reference", "bin/text/coretext"]);
		}
	}

	// (the references: tests/text/coretext/sheets, CoreText's, drawn by the system-text lane on a Mac)
	static function textQuality() {
		native("bin/text-quality/TextQuality", cps(["src", "tests/text"]).concat(["-main", "TextQuality"]), HOST);
		run(exePath("bin/text-quality/TextQuality", HOST), ["compare", "tests/text/coretext/sheets", "bin/text-quality"]);
	}

	static function systemImages() {
		native('bin/os/$GFX_TARGET/SystemImagesTest', cps(["src", "tests/os"]).concat(["-main", "SystemImagesTest"]), GFX_TARGET);
		var exe = exePath('bin/os/$GFX_TARGET/SystemImagesTest', GFX_TARGET), args = ["tests/os/images"];
		if (GFX_TARGET.startsWith("macos-")) {
			run("sips", ["-s", "format", "heic", "tests/os/images/gradient-lzw.tif", "--out", "bin/os/gradient.heic"]);
			args.push("bin/os/gradient.heic");
		}
		if (GFX_TARGET.startsWith("windows-") && !HOST.startsWith("windows-")) run("wine", [exe].concat(args)) else run(exe, args);
	}

	// (Linux: a private session bus, dbus-run-session)
	static function dbus() {
		exe("bin/os/DBusTest", cps(["src", "tests/os"]).concat(["-main", "DBusTest", "-D", "hxmc.libc=glibc"]));
		run("dbus-run-session", ["--", exePath("bin/os/DBusTest", HOST)]);
	}

	// (Linux: Xvfb; a Windows target on another host: under Wine)
	// (the protocols the bindings are made from, where the system has their XML)
	static final WAYLAND_XML = [
		"/usr/share/wayland/wayland.xml", "/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml",
		"/usr/share/wayland-protocols/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml", "/usr/share/wayland-protocols/stable/viewporter/viewporter.xml",
		"/usr/share/wayland-protocols/staging/fractional-scale/fractional-scale-v1.xml", "/usr/share/wayland-protocols/staging/cursor-shape/cursor-shape-v1.xml",
		"/usr/share/wayland-protocols/unstable/text-input/text-input-unstable-v3.xml"
	];

	static function wayland() {
		if ([for (x in WAYLAND_XML) if (!FileSystem.exists(x)) x].length == 0) {
			if (FileSystem.exists("bin/wayland/protocol")) rmrf("bin/wayland/protocol");
			mkdirs("bin/wayland/protocol");
			run(TOOL, ["-cp", "src", "--run", "helder.os.wayland.Scanner", "bin/wayland/protocol"].concat(WAYLAND_XML));
			for (f in FileSystem.readDirectory("bin/wayland/protocol"))
				if (File.getContent('bin/wayland/protocol/$f') != File.getContent('src/helder/os/wayland/protocol/$f'))
					throw new Failed('src/helder/os/wayland/protocol/$f differs from what the scanner makes of the system\'s XML (bin/wayland/protocol/$f)');
			Sys.println("wayland: the bindings are the scanner's of the system's XML");
		} else Sys.println("wayland: no wayland-protocols XML here: the bindings not compared");
		if (!GFX_TARGET.startsWith("linux-")) {
			Sys.println("wayland: Linux's alone");
			return;
		}
		native('bin/os/$GFX_TARGET/WaylandTest', cps(["src", "tests/os"]).concat(["-main", "WaylandTest"]), GFX_TARGET);
		run(helderCli(), ["build", "apps/viewer"]);
		if (Sys.systemName() != "Linux" || Sys.command("sh", ["-c", "command -v weston > /dev/null"]) != 0) {
			Sys.println("wayland: no weston here: built, not run");
			return;
		}
		shell('sh tests/os/wayland.sh bin/os/$GFX_TARGET/WaylandTest apps/viewer/bin/$GFX_TARGET/viewer bin/os');
	}

	static function window() {
		native('bin/os/$GFX_TARGET/WindowTest', cps(["src", "tests/os"]).concat(["-main", "WindowTest"]), GFX_TARGET);
		var exe = exePath('bin/os/$GFX_TARGET/WindowTest', GFX_TARGET);
		var wine = GFX_TARGET.startsWith("windows-") && !HOST.startsWith("windows-") ? "wine " : "";
		if (Sys.systemName() == "Linux") shell('$XVFB -a $wine$exe') else run(exe, []);
		// (helder.ui.menu's model as each platform's menus: tests/os/MenuTest.hx)
		native('bin/os/$GFX_TARGET/MenuTest', cps(["src", "tests/os"]).concat(["-main", "MenuTest"]), GFX_TARGET);
		var menus = exePath('bin/os/$GFX_TARGET/MenuTest', GFX_TARGET);
		if (Sys.systemName() == "Linux") shell('LIBGL_ALWAYS_SOFTWARE=1 $XVFB -a $wine$menus bin/os') else run(menus, ["bin/os"]);
		// (the platform's spellchecker: tests/text/SpellTest.hx)
		native('bin/text/$GFX_TARGET/SpellTest', cps(["src", "tests/text"]).concat(["-main", "SpellTest"]), GFX_TARGET);
		var spell = exePath('bin/text/$GFX_TARGET/SpellTest', GFX_TARGET);
		if (wine != "") shell('$wine$spell bin/text') else run(spell, ["bin/text"]);
		// (Windows' TSF for drawn text fields, the test the input method; again without it: IMM32's)
		if (GFX_TARGET.startsWith("windows-")) {
			native('bin/os/$GFX_TARGET/TsfTest', cps(["src", "tests/os"]).concat(["-main", "TsfTest"]), GFX_TARGET);
			var tsf = exePath('bin/os/$GFX_TARGET/TsfTest', GFX_TARGET);
			// (a drawn field typed into through it: tests/ui/WinTextTest.hx)
			native('bin/ui/$GFX_TARGET/WinTextTest', uiCp().concat(["-main", "WinTextTest"]), GFX_TARGET);
			var text = exePath('bin/ui/$GFX_TARGET/WinTextTest', GFX_TARGET);
			if (Sys.systemName() == "Linux") {
				shell('$XVFB -a $wine$tsf');
				shell('HELDER_NO_TSF=1 $XVFB -a $wine$tsf');
				shell('LIBGL_ALWAYS_SOFTWARE=1 $XVFB -a $wine$text');
			} else {
				run(tsf, []);
				run(tsf, [], ["HELDER_NO_TSF" => "1"]);
				run(text, []);
			}
			winAccess();
		}
		// (helder.ui's NSAccessibility, in process: tests/ui/MacAccessTest.hx, MacPatternsTest.hx)
		if (GFX_TARGET.startsWith("macos-") && Sys.systemName() == "Mac")
			for (m in ["MacAccessTest", "MacPatternsTest"]) {
				native('bin/ui/$GFX_TARGET/$m', uiCp().concat(["-main", m]), GFX_TARGET);
				run('bin/ui/$GFX_TARGET/$m', []);
			}
	}

	// helder.ui's UI Automation (Windows; a Windows target from Linux under
	// Wine): its providers in process (tests/ui/WinAccessTest.hx: Plain's
	// controls, a native field; WinPatternsTest.hx: the fixture's patterns),
	// then UI Automation's own client in another process (WinAccessProbe:
	// IUIAutomation) reading AccessApp's fixture, acted on to its Save, and
	// its todo, mail and guide screens whole. (Wine's IUIAutomation has no
	// patterns and hangs on a focus handler: there the probe reads, the
	// window is ended after.)
	static function winAccess() {
		var t = GFX_TARGET, b = 'bin/ui/$t';
		for (m in ["WinAccessTest", "WinPatternsTest", "AccessApp", "WinAccessProbe"])
			native('$b/$m', uiCp().concat(["-main", m]), t);
		var wine = !HOST.startsWith("windows-");
		var w = wine ? "wine " : "", x = wine ? "LIBGL_ALWAYS_SOFTWARE=1 HELDER_UNDER_WINE=1 " + XVFB + " -a " : "";
		var app = '$w$b/AccessApp.exe', probe = '$w$b/WinAccessProbe.exe';
		shell('$x$w$b/WinAccessTest.exe');
		shell('$x$w$b/WinPatternsTest.exe');
		var end = wine ? 'kill $$p; wineserver -k; exit $$s' : 'wait $$p && exit $$s', stop = wine ? 'kill $$p; wineserver -k' : 'kill $$p';
		shell('$x sh -c \'HELDER_ACCESS_LOG=1 $app fixture & p=$$!; $probe fixture; s=$$?; $end\'');
		// (the screens' entries in ASCII: Wine's command line is not UTF-8)
		for (screen in ACCESS_SCREENS) {
			var args = [for (a in screen) if (~/^[\x20-\x7e]*$/.match(a)) a];
			shell('$x sh -c \'$app ${screen[0]} & p=$$!; $probe ${args.join(" ")}; s=$$?; $stop; exit $$s\'');
		}
	}

	static function asyncWeb() {
		wasm("bin/async/WebTest.wasm", cps(["src", "tests/async"]).concat(["-main", "WebTest"]));
		run(NODE, ["tests/async/browser.mjs", "bin/async/WebTest.wasm"]);
	}

	// (the CLI's own build, as `bun run helder` makes it)
	static function helderCli():String {
		exe("bin/cli/helder", cps(["src"]).concat(["-main", "helder.cli.Cli"]));
		return exePath("bin/cli/helder", HOST);
	}

	static function helderTest() {
		run(helderCli(), ["test", "--target", "all,interp"]);
		// (TypeScript's tests beside an example's sources: helder/test, natively and as wasm32-wasi)
		run(helderCli(), ["test", "examples/ts-todo", "--target", "all"]);
	}

	// (the project: tests/cli/project copied, helder in its node_modules as a
	// package.json naming this checkout's src/: no link, which rmrf would follow)
	static function cli() {
		var h = helderCli();
		Sys.println('helder: ${Math.round(FileSystem.stat(h).size / 1024)} KB');
		// (the grammar, its parser's own tests src/helder/cli/Options.test.hx:
		// helder alone is help; the positional never a target; one error format)
		var none = new Map();
		expect(h, [], none, "helder <entry>                 shorthand for: helder dev <entry>");
		expect(h, ["build", "--help"], none, "  -o, --out <path>   build's output");
		expect(h, ["help", "dev"], none, "  --port <n>");
		expect(h, ["web"], none, "helder: `web` is a target: use helder dev --target web", 2);
		expect(h, ["build", "web", "examples/counter"], none, "helder build: one entry, not web and examples/counter", 2);
		expect(h, ["build", "web"], none, "helder build: `web` is a target: use --target web", 2);
		expect(h, ["run", "--bogus"], none, "helder run: unknown option --bogus (helder run --help)", 2);
		expect(h, ["dev", "--target"], none, "helder dev: --target takes a value", 2);
		expect(h, ["build", "-d", "emulator-5554"], none, "helder build: -d/--device picks a phone, emulator or simulator", 2);
		expect(h, ["run", "examples/counter", "--target", "ios-arm64"], none, "helder run: --target ios-arm64: an iPhone needs a signing identity (not yet)", 2);
		// (helder devices: no adb on the PATH, an empty directory; then a stand-in adb)
		rmrf("bin/cli/path");
		mkdirs("bin/cli/path/none");
		final noAdb = ["PATH" => FileSystem.fullPath("bin/cli/path/none"), "ADB" => "", "ANDROID_HOME" => "", "ANDROID_SDK_ROOT" => ""];
		expect(h, ["devices"], noAdb, "adb not found");
		expect(h, ["run", "examples/counter", "--target", "android"], noAdb, "adb not found (Android's platform-tools on the PATH, or ADB)", 1);
		expect(h, ["devices"], noAdb, 'host  this machine');
		if (!HOST.startsWith("windows-")) {
			mkdirs("bin/cli/path/adb");
			File.saveContent("bin/cli/path/adb/adb", "#!/bin/sh\necho 'List of devices attached'\necho 'emulator-5554  device product:sdk_gphone64 model:Pixel_7 device:emu64xa transport_id:1'\n");
			run("chmod", ["+x", "bin/cli/path/adb/adb"]);
			expect(h, ["devices"], ["PATH" => FileSystem.fullPath("bin/cli/path/adb"), "ADB" => ""], "emulator-5554  Pixel 7");
		}
		run(h, ["build", "examples/counter/Counter.hx"]);
		run(h, ["build", "--target", "web", "examples/counter"]);
		for (f in ["Counter.html", "Counter.wasm", "helder/os/browser.mjs", "helder/ui/imports.mjs"])
			if (!FileSystem.exists('bin/web/$f')) throw new Failed('helder build --target web: no bin/web/$f');
		// (a machine with no font to bundle: the warning names the cause and the fix)
		rmrf("bin/cli/nofont");
		mkdirs("bin/cli/nofont");
		expect(h, ["build", "--target", "web", "examples/counter", "-o", "bin/cli/nofont/Counter.wasm"], ["HELDER_FONT_DIRS" => FileSystem.fullPath("bin/cli/path/none")],
			"no system font to bundle was found on this machine (DejaVu Sans, in");
		expect(h, ["build", "--target", "web", "examples/counter", "-o", "bin/cli/nofont/Counter.wasm"], ["HELDER_FONT_DIRS" => FileSystem.fullPath("bin/cli/path/none")],
			"Add a font file to the project and load it with Asset.font");
		expect(h, ["run", "tests/cli/tally", "--", "3"], new Map(), "v1 count=3");
		rmrf("bin/cli/project");
		copy("tests/cli/project", "bin/cli/project");
		mkdirs("bin/cli/project/node_modules");
		mkdirs("bin/cli/project/node_modules/helder");
		var src = FileSystem.fullPath("src").split("\\").join("/");
		File.saveContent("bin/cli/project/node_modules/helder/package.json", haxe.Json.stringify({name: "helder", haxe: {name: "helder", classPath: src}}));
		expect(h, ["run", "bin/cli/project"], new Map(), "hello from the project");
		expect(h, ["run", "bin/cli/project/src/app/Hello.hx"], new Map(), "hello from app.Hello, hello from the project");
		run(h, ["build", "bin/cli/project", "--target", "wasm32-wasi"]);
		wasi("bin/cli/project/bin/wasm32-wasi/cli-fixture.wasm");
		run(NODE, ["tests/cli/dev.mjs", h, "bin/cli/dev-native", "native"]);
		run(NODE, ["tests/cli/dev.mjs", h, "bin/cli/dev-nohost", "native-nohost"]);
		run(NODE, ["tests/cli/dev.mjs", h, "bin/cli/dev-web", "web"]);
		run(NODE, ["tests/cli/dev.mjs", h, "bin/cli/dev-exit", "exit"]);
		// (assets: a change sent, nothing built, behind the same handle; the page told)
		run(NODE, ["tests/cli/dev.mjs", h, "bin/cli/dev-asset", "asset"]);
		run(NODE, ["tests/cli/dev.mjs", h, "bin/cli/dev-asset-nohost", "asset-nohost"]);
		run(NODE, ["tests/cli/dev.mjs", h, "bin/cli/dev-asset-web", "asset-web"]);
	}

	// (the runtime objects: Android's and iOS's are not npm's for this
	// (Checksum's lines: its files' sizes and CRC-32s, the bundle's list; CI's
	// emulator and simulator jobs check the same, tests/pack/android.sh, ios.sh)
	static final CHECKSUM = [for (l in File.getContent("tests/asset/checksum.txt").split("\n")) if (l != "") l];

	// (PackCheck's: the asset fixture's files, exactly)
	static final ASSETS = "assets=tests/asset:files/kept.txt,files/pixels.png";

	static function assetLane() {
		var h = helderCli();
		// (what Asset's definitions reject, at the call)
		for (r in [
			{main: "Missing", error: 'Asset.bytes("files/nothere.txt"): no such file under the class paths or the project'},
			{main: "Case", error: 'Asset.bytes("files/Kept.txt"): "Kept.txt" is "kept.txt" on disk (paths are case-sensitive on Android and the web)'},
			{main: "Absolute", error: 'Asset.bytes("/etc/hostname"): an absolute path'},
			{main: "Parent", error: 'Asset.image("files/../files/pixels.png"): a part ".."'},
			{main: "NotLiteral", error: 'Asset.bytes: name is not static'}
		]) {
			var b = build(cps(["src", "tests/asset", "tests/asset/reject"]).concat(["-main", r.main, "--custom-target", 'hxmc=bin/asset/${r.main}']), 'bin/asset/${r.main}.log');
			if (b.code == 0 || !b.log.contains(r.error)) throw new Failed('${r.main}: expected the error "${r.error}":\n' + b.log);
			Sys.println('asset: ${r.main} rejected: ${r.error}');
		}
		// (this machine: the files in the executable, nothing beside it)
		var exe = exePath("bin/asset/host/Checksum", HOST);
		rmrf("bin/asset/host");
		run(h, ["build", "tests/asset/Checksum.hx", "-o", exe]);
		if (FileSystem.readDirectory("bin/asset/host").join(",") != Path.withoutDirectory(exe)) throw new Failed("bin/asset/host: more than the executable");
		rmrf("bin/asset/empty");
		mkdirs("bin/asset/empty");
		var cwd = Sys.getCwd(), full = FileSystem.fullPath(exe);
		Sys.setCwd("bin/asset/empty");
		var out = output(full, []);
		Sys.setCwd(cwd);
		Sys.print(out);
		for (l in CHECKSUM.concat(["asset: built in files/kept.txt,files/pixels.png"])) if (!out.contains(l + "\n")) throw new Failed('Checksum, alone: no line "$l"');
		// (the web: the referenced files beside the page, no other)
		rmrf("bin/asset/web");
		run(h, ["build", "tests/asset/Checksum.hx", "--target", "web", "-o", "bin/asset/web/Checksum.wasm"]);
		var files = [];
		function walk(d:String) for (n in FileSystem.readDirectory('bin/asset/web/$d')) if (FileSystem.isDirectory('bin/asset/web/$d/$n')) walk('$d/$n') else files.push('$d/$n');
		walk("assets");
		files.sort(Reflect.compare);
		if (files.join(",") != "assets/files/kept.txt,assets/files/pixels.png") throw new Failed('bin/asset/web/assets: ${files.join(", ")}');
		var out = output(NODE, ["--no-warnings", "--stack-size=65500", "src/helder/test/wasi.mjs", "bin/asset/web/Checksum.wasm"]);
		Sys.print(out);
		for (l in CHECKSUM) if (!out.contains(l + "\n")) throw new Failed('Checksum, wasm32-wasi: no line "$l"');
	}

	// machine, tests/pack/runtime.mjs fetches them (Android's from the
	// release @hxmc/cli's package.json names); the builds' HXMC_RT_DIR.
	// The debug key made in a cache of its own, on first use)
	static function packLane() {
		var h = helderCli();
		run(NODE, ["tests/pack/runtime.mjs", "bin/pack/rt"]);
		var rt = FileSystem.fullPath("bin/pack/rt");
		rmrf("bin/pack/cache");
		mkdirs("bin/pack/cache");
		var env = ["HXMC_RT_DIR" => rt, "HELDER_CACHE" => FileSystem.fullPath("bin/pack/cache")];
		var required = Sys.getEnv("PACK_REQUIRE") == "1";
		var have = (t:String) -> {
			var ok = FileSystem.exists('$rt/$t/rt.o');
			if (!ok && required) throw new Failed('no runtime objects for $t (tests/pack/runtime.mjs)');
			if (!ok) Sys.println('pack: no runtime objects for $t (tests/pack/runtime.mjs): its builds skipped');
			return ok;
		};
		rmrf("bin/pack/project");
		copy("tests/pack/project", "bin/pack/project");
		mkdirs("bin/pack/project/node_modules/helder");
		var src = FileSystem.fullPath("src").split("\\").join("/");
		File.saveContent("bin/pack/project/node_modules/helder/package.json", haxe.Json.stringify({name: "helder", haxe: {name: "helder", classPath: src}}));
		var checks = [];
		if (have("android-arm64") && have("android-x86_64")) {
			run(h, ["build", "tests/pack/Hello.hx", "--target", "android", "-o", "bin/pack/Hello-arm64.apk"], env);
			run(h, ["build", "tests/pack/Hello.hx", "--target", "android-x86_64", "-o", "bin/pack/Hello-x86_64.apk"], env);
			run(h, ["build", "bin/pack/project", "--target", "android-x86_64"], env);
			// (the screen fixture: CI's emulator runs it, tests/pack/android.sh)
			run(h, ["build", "tests/pack/Screen.hx", "--target", "android-x86_64", "-o", "bin/pack/Screen.apk"], env);
			// (the asset fixture: its files in assets/, files/dropped.txt not; CI's emulator runs it)
			run(h, ["build", "tests/asset/Checksum.hx", "--target", "android-x86_64", "-o", "bin/pack/Checksum.apk"], env);
			// (Java's classes as the program needs them: a drawn ui's listeners, NativeActivity's surface)
			run(h, ["build", "examples/counter", "--target", "android-x86_64", "-o", "bin/pack/Counter.apk"], env);
			checks = checks.concat([
				"bin/pack/Hello-arm64.apk@org.helder.hello@surface", "bin/pack/Hello-x86_64.apk", "bin/pack/project/bin/android/Packed.apk@org.helder.packcheck@landscape@fullscreen@icons",
				"bin/pack/Counter.apk@@surface", "bin/pack/Screen.apk@org.helder.screen@surface",
				'bin/pack/Checksum.apk@org.helder.checksum@$ASSETS'
			]);
			for (c in [{apk: "Counter", want: '{"dex":true,"views":false}'}]) {
				var got = File.getContent('bin/pack/${c.apk}.lib/classes.json');
				if (got != c.want) throw new Failed('bin/pack/${c.apk}.lib/classes.json: $got, not ${c.want}');
			}
			// (release signing, tests/pack/signing's RSA key: an APK, and the
			// project's App Bundle of both ABIs; one of the two settings alone an error)
			var release = [for (k => v in env) k => v];
			release.set("HELDER_ANDROID_SIGNING_CERTIFICATE", FileSystem.fullPath("tests/pack/signing/cert.pem"));
			release.set("HELDER_ANDROID_SIGNING_KEY", FileSystem.fullPath("tests/pack/signing/key.pem"));
			run(h, ["build", "tests/pack/Hello.hx", "--target", "android", "--release", "-o", "bin/pack/Hello-release.apk"], release);
			run(h, ["build", "bin/pack/project", "--target", "android", "--release", "--bundle", "-o", "bin/pack/Packed.aab"], release);
			var half = [for (k => v in env) k => v];
			half.set("HELDER_ANDROID_SIGNING_KEY", FileSystem.fullPath("tests/pack/signing/key.pem"));
			expect(h, ["build", "tests/pack/Hello.hx", "--target", "android", "-o", "bin/pack/Half.apk"], half,
				"release signing takes a certificate and its key: HELDER_ANDROID_SIGNING_CERTIFICATE", 1);
			expect(h, ["build", "tests/pack/Hello.hx", "--target", "android", "--bundle", "-o", "bin/pack/Unsigned.aab"], env,
				"an App Bundle is signed by the upload key", 1);
			checks = checks.concat(["bin/pack/Hello-release.apk@org.helder.hello@surface@release", "bin/pack/Packed.aab@org.helder.packcheck"]);
			if (!File.getContent("bin/pack/cache/android/debug-key").startsWith("helder-android-debug-key 1\n"))
				throw new Failed("bin/pack/cache/android/debug-key: not made on first use");
			Sys.println("pack: the debug key made on first use, in the cache");
			// (the CLI's own fetch of Android's objects, from a stand-in release
			// of the same objects: no HXMC_RT_DIR, a cache of its own)
			run(NODE, ["tests/pack/release.mjs", rt, "bin/pack/release"]);
			rmrf("bin/pack/rt-cache");
			mkdirs("bin/pack/rt-cache");
			var release = FileSystem.fullPath("bin/pack/release").split("\\").join("/");
			expect(h, ["build", "tests/pack/Hello.hx", "--target", "android-x86_64", "-o", "bin/pack/Fetched.apk"], [
				"HXMC_RT_DIR" => "",
				"HELDER_CACHE" => FileSystem.fullPath("bin/pack/rt-cache"),
				"HELDER_RT_URL" => "file://" + (release.startsWith("/") ? "" : "/") + release
			], "fetching");
			var fetched = [for (d in FileSystem.readDirectory("bin/pack/rt-cache/rt")) d];
			if (fetched.length != 1 || !FileSystem.exists('bin/pack/rt-cache/rt/${fetched[0]}/android-x86_64/rt.o'))
				throw new Failed('bin/pack/rt-cache/rt: ${fetched.join(", ")}, not one release\'s android-x86_64 objects');
			checks.push("bin/pack/Fetched.apk");
			Sys.println('pack: Android\'s runtime objects fetched on first use (${fetched[0]})');
		}
		// (helder publish against a stand-in of Google Play's and App Store Connect's APIs)
		if (have("android-arm64") && have("android-x86_64") && have("macos-arm64")) run(NODE, ["tests/pack/publish.mjs", h, "bin/pack/publish"], env);
		if (have("macos-arm64")) {
			run(h, ["build", "tests/pack/Hello.hx", "--target", "ios", "-o", "bin/pack/Hello.ipa"], env);
			run(h, ["build", "tests/pack/Hello.hx", "--target", "ios-sim", "-o", "bin/pack/Hello.app"], env);
			run(h, ["build", "bin/pack/project", "--target", "ios-sim"], env);
			run(h, ["build", "tests/pack/Screen.hx", "--target", "ios-sim", "-o", "bin/pack/Screen.app"], env);
			run(h, ["build", "tests/asset/Checksum.hx", "--target", "ios-sim", "-o", "bin/pack/Checksum.app"], env);
			run(h, ["build", "tests/asset/Checksum.hx", "--target", "ios", "-o", "bin/pack/Checksum.ipa"], env);
			// (signed for distribution, tests/pack/signing's throwaway CA: the
			// project with an RSA key, its files' paths; Hello with a P-256
			// key, the PEM's text and the profile's base64 in the variables)
			var signing = FileSystem.fullPath("tests/pack/signing");
			var rsa = ["HELDER_IOS_CERTIFICATE" => '$signing/cert.pem', "HELDER_IOS_KEY" => '$signing/key.pem', "HELDER_IOS_PROFILE" => '$signing/test.mobileprovision'];
			var ec = [
				"HELDER_IOS_CERTIFICATE" => File.getContent('$signing/cert-ec.pem'),
				"HELDER_IOS_KEY" => File.getContent('$signing/key-ec.pem'),
				"HELDER_IOS_PROFILE" => haxe.crypto.Base64.encode(File.getBytes('$signing/test.mobileprovision'))
			];
			for (k => v in env) {
				rsa.set(k, v);
				ec.set(k, v);
			}
			run(h, ["build", "bin/pack/project", "--target", "ios", "-o", "bin/pack/Packed-signed.ipa"], rsa);
			run(h, ["build", "tests/pack/Hello.hx", "--target", "ios", "-o", "bin/pack/Hello-signed.ipa"], ec);
			var partial = [for (k => v in env) k => v];
			partial.set("HELDER_IOS_KEY", '$signing/key.pem');
			expect(h, ["build", "tests/pack/Hello.hx", "--target", "ios", "-o", "bin/pack/Unsigned.ipa"], partial,
				"signing for the App Store takes a certificate and its key (HELDER_IOS_IDENTITY: both in one PEM): HELDER_IOS_CERTIFICATE", 1);
			checks = checks.concat(["bin/pack/Packed-signed.ipa@org.helder.packcheck@signed@encryption@entitlements@landscape@fullscreen@icons",
				"bin/pack/Hello-signed.ipa@org.helder.Hello@signed"]);
			checks = checks.concat(["bin/pack/Hello.ipa@org.helder.Hello", "bin/pack/Hello.app", "bin/pack/project/bin/ios-sim/Packed.app@org.helder.packcheck@entitlements@landscape@fullscreen@icons", "bin/pack/Screen.app@org.helder.Screen",
				'bin/pack/Checksum.app@org.helder.Checksum@$ASSETS', 'bin/pack/Checksum.ipa@org.helder.Checksum@$ASSETS']);
		}
		if (checks.length > 0) interp(cps(["src", "tests/pack"]), "PackCheck", checks);
		// (a phone's tools stood in for: helder run, the dev loop's protocol)
		if (HOST.startsWith("windows-")) return;
		var fake = ["ADB" => FileSystem.fullPath("tests/pack/fake/adb"), "XCRUN" => FileSystem.fullPath("tests/pack/fake/xcrun")];
		for (k => v in env) fake.set(k, v);
		if (FileSystem.exists('$rt/android-x86_64/rt.o')) {
			expect(h, ["run", "tests/pack/Hello.hx", "--target", "android"], fake, "running org.helder.hello on Pixel 7");
			run(NODE, ["tests/pack/dev.mjs", h, "bin/pack/dev-android", "android"], env);
		}
		if (FileSystem.exists('$rt/macos-arm64/rt.o')) run(NODE, ["tests/pack/dev.mjs", h, "bin/pack/dev-ios", "ios"], env);
	}

	static function devtools() {
		var h = helderCli();
		exe("bin/devtools/FrameCost", cps(["src", "tests/devtools"]).concat(["-main", "FrameCost", "-D", "hxmc.dev"]));
		run(exePath("bin/devtools/FrameCost", HOST), []);
		run(NODE, ["tests/devtools/devtools.mjs", h, "bin/devtools/console", "console"]);
		run(NODE, ["tests/devtools/devtools.mjs", h, "bin/devtools/ui", "ui"]);
	}

	static function copy(from:String, to:String) {
		mkdirs(to);
		for (n in FileSystem.readDirectory(from))
			if (FileSystem.isDirectory('$from/$n')) copy('$from/$n', '$to/$n') else File.copy('$from/$n', '$to/$n');
	}

	// (the examples' directories of gfx's, which its tests use)
	static final GFX_EXAMPLES = [for (e in ["triangle", "cube", "instances", "mips", "formats"]) 'examples/$e'];

	static function gfxCp()
		return cps(["src", "tests/gfx"].concat(GFX_EXAMPLES));

	static function gfxPrograms() {
		for (m in ["GfxTest", "Triangle", "Cube", "Instances", "Targets", "Mips", "Formats"])
			native('bin/gfx/$GFX_TARGET/$m', gfxCp().concat(["-main", m]), GFX_TARGET);
	}

	static function gfx() {
		gfxPrograms();
		run("sh", ["tests/gfx/check.sh", 'bin/gfx/$GFX_TARGET']);
	}

	static function gfxShared() {
		native('bin/gfx-shared/$GFX_TARGET/SharedTexture', cps(["src", "tests/gfx"]).concat(["-main", "SharedTexture"]), GFX_TARGET);
		var exe = exePath('bin/gfx-shared/$GFX_TARGET/SharedTexture', GFX_TARGET);
		// (a Mac's and Windows' own GPU always share; under Wine, or on Linux without a dma-buf exporter, skipped)
		var require = GFX_TARGET == HOST && (HOST.startsWith("macos-") || HOST.startsWith("windows-"));
		if (GFX_TARGET.startsWith("windows-") && !HOST.startsWith("windows-")) run("wine", [exe]) else run(exe, require ? ["--require"] : []);
	}

	static function sprite() {
		native('bin/sprite/$GFX_TARGET/SpriteFrame', cps(["src", "tests/sprite"]).concat(["-main", "SpriteFrame"]), GFX_TARGET);
		Sys.putEnv("LIBGL_ALWAYS_SOFTWARE", "1");
		run(exePath('bin/sprite/$GFX_TARGET/SpriteFrame', GFX_TARGET), []);
	}

	static function gfxWeb() {
		wasm("bin/gfx/WebTest.wasm", gfxCp().concat(["-main", "WebTest"]));
		run(NODE, ["tests/gfx/web.mjs", "bin/gfx/WebTest.wasm", "bin/gfx"]);
	}

	static function osCp()
		return cps(["src", "examples/tone", "tests/os"]);

	static function audio() {
		for (m in ["AudioTest", "Tone"])
			native('bin/audio/$AUDIO_TARGET/$m', osCp().concat(["-main", m]), AUDIO_TARGET);
		run("sh", ["tests/os/audio.sh", 'bin/audio/$AUDIO_TARGET']);
	}

	static function audioWeb() {
		wasm("bin/audio/AudioTest.wasm", osCp().concat(["-main", "AudioTest"]));
		run(NODE, ["tests/os/web.mjs", "bin/audio/AudioTest.wasm"]);
	}

	static function touchWeb() {
		wasm("bin/os/PointersWeb.wasm", cps(["src", "tests/os"]).concat(["-main", "PointersWeb"]));
		run(NODE, ["tests/os/pointers-web.mjs", "bin/os/PointersWeb.wasm"]);
		wasm("bin/os/BackWeb.wasm", cps(["src", "tests/os"]).concat(["-main", "BackWeb"]));
		run(NODE, ["tests/os/back-web.mjs", "bin/os/BackWeb.wasm"]);
	}

	static final SCENE_EXAMPLES = [for (e in ["gltf-viewer", "orbits", "showroom", "falling", "walker", "chains", "glow"]) 'examples/$e'];
	// the glTF samples packed for the packed scenes (the asset step)
	static final PACKED = ["examples/gltf-viewer/sample.glb", "tests/3d/skinned.glb", "examples/showroom/normals.glb", "examples/showroom/morph.glb"];

	static function sceneCp()
		return gfxCp().concat(cps(SCENE_EXAMPLES.concat(["tests/3d", "tests/physics"])));

	static function pack() {
		mkdirs("bin/3d");
		for (glb in PACKED)
			interp(sceneCp(), "helder.scene.gltf.Pack", [glb, "bin/3d/" + Path.withoutExtension(Path.withoutDirectory(glb)) + ".hxm3d"]);
		// (the textured sample's texture compressed for the GPU: BC1, ASTC 4x4)
		for (t in ["bc", "astc"])
			interp(sceneCp(), "helder.scene.gltf.Pack", ["tests/3d/textured.glb", 'bin/3d/textured.$t.hxm3d', "--textures", t]);
	}

	static function scene() {
		var cp = sceneCp();
		var tests = ["SceneTest", "GltfTest", "PhysicsTest"];
		for (t in tests)
			interp(cp, t);
		for (t in tests) {
			exe('bin/3d/$t', cp.concat(["-main", t]));
			run(exePath('bin/3d/$t', HOST), []);
		}
		for (t in tests) {
			wasm('bin/3d/$t.wasm', cp.concat(["-main", t]));
			wasi('bin/3d/$t.wasm');
		}
		pack();
		var t = GFX_TARGET;
		for (m in ["RenderTest", "GltfViewer", "Orbits", "Showroom", "Falling", "Walker", "Chains", "InputTest"])
			native('bin/3d/$t/$m', cp.concat(["-main", m]), t);
		wasm("bin/3d/InputTest.wasm", cp.concat(["-main", "InputTest"]));
		run(exePath('bin/3d/$t/InputTest', t), []);
		wasi("bin/3d/InputTest.wasm");
		// (helder.scene.view: view's markup on the scene graph; natively: its meshes import gfx, which node lacks)
		native('bin/3d/$t/SceneUiTest', cps(["src", "tests/3d-ui"]).concat(["-main", "SceneUiTest"]), t);
		run(exePath('bin/3d/$t/SceneUiTest', t), []);
		// (the boundary tags in windows: <Surface>s, a <Scene> box, picking through it, <Ui>; Xvfb)
		native('bin/3d/$t/SurfaceTest', cps(["src", "tests/gfx", "tests/3d-ui"]).concat(["-main", "SurfaceTest"]), t);
		shell('LIBGL_ALWAYS_SOFTWARE=1 $XVFB -a -s "-screen 0 640x480x24" ' + exePath('bin/3d/$t/SurfaceTest', t));
		run("sh", ["tests/3d/check.sh", 'bin/3d/$t']);
		sceneTs(t);
		// (Model.of's files in the executable's data, helder.asset's Bundle: it
		// alone in a directory, run from it, nothing beside it)
		var exe = Path.withoutDirectory(exePath("bin/3d/alone/RenderTest", t));
		rmrf("bin/3d/alone");
		mkdirs("bin/3d/alone");
		shell('cp ${exePath('bin/3d/$t/RenderTest', t)} bin/3d/alone/$exe');
		if (FileSystem.readDirectory("bin/3d/alone").join(",") != exe) throw new Failed("bin/3d/alone: not the executable alone");
		shell('cd bin/3d/alone && LIBGL_ALWAYS_SOFTWARE=1 HXMC_GFX_SOFTWARE=1 env -u DISPLAY ./$exe skin ../../../tests/3d/skin.png ../skin-alone.png');
		// (Model.of: a name the file does not have is a compile error)
		var r = build(cp.concat(cps(["tests/3d/reject"])).concat(["-main", "ModelTypo", "--custom-target", "hxmc=bin/3d/ModelTypo"]), "bin/3d/ModelTypo.log");
		if (r.code == 0 || !r.log.contains("has no field bal"))
			throw new Failed("ModelTypo: expected the error \"has no field bal\":\n" + r.log);
	}

	// helder/scene from TypeScript (tests/3d/ts/frames.ts, examples/ts-scene's
	// scenes): its module's declarations as FramesTypeScript makes them, then
	// its frames headless as RenderTest's, glow against Haxe's glow.png,
	// tsscene against tsscene.png (which check.sh's Haxe twin matches too)
	static function sceneTs(t:String) {
		var compiler = StringTools.trim(output(NODE, ["src/helder/compiler/build.mjs", "--quiet"]));
		var cp = [for (d in ["tests/3d/ts", "tests/gfx"].concat(GFX_EXAMPLES)) for (a in ["--cp", d]) a];
		run(NODE, ["src/helder/typescript/api/declarations.mjs", "--check"].concat(cp).concat(["helder.asset.TypeScript", "helder.scene.TypeScript", "frames.FramesTypeScript"]));
		var exe = exePath('bin/3d/$t/ts-frames', t);
		mkdirs(Path.directory(exe));
		run(compiler, ["tests/3d/ts/frames.ts", "-o", exe].concat(cp).concat(targetArgs(t)));
		for (s in ["glow", "tsscene"])
			shell('LIBGL_ALWAYS_SOFTWARE=1 HXMC_GFX_SOFTWARE=1 env -u DISPLAY $exe $s tests/3d/$s.png bin/3d/$t/ts-$s.png');
	}

	// (each run twice, into bin/headless-run/1 and 2: the same bytes)
	static function editLoop()
		run(NODE, ["tests/edit-loop/edit-loop.mjs", helderCli(), "bin/edit-loop"]);

	static function syntaxLane() {
		var cp = cps(["src", "tests/syntax"]);
		interp(cp, "Check");
		exe("bin/syntax/Check", cp.concat(["-main", "Check"]));
		run(exePath("bin/syntax/Check", HOST), []);
	}

	// (the examples edited, built and run headless, their trees checked)
	static function syntaxRun() {
		var h = helderCli(), o = "bin/syntax/run";
		var cp = cps(["src", "tests/syntax"]);
		interp(cp, "Examples", ["prepare", o]);
		for (app in ["todo", "ts-todo"])
			run(h, ["run", "--headless", '$o/$app', "--script", "tests/headless/todo.json", "--tree", '$o/$app-end.json']);
		run(h, ["run", "--headless", '$o/mail', "--tree", '$o/mail.json']);
		run(h, ["run", "--headless", '$o/guide/GuideScreen.hx', "--tree", '$o/guide.json']);
		run(h, ["run", "--headless", '$o/viewer', "--script", "tests/headless/viewer.json", "--size", "480x360", "--tree", '$o/viewer-end.json']);
		run(h, ["test", '$o/ts-todo-story', "--target", "host"]);
		interp(cp, "Examples", ["check", o]);
	}

	static function headlessRun() {
		var h = helderCli(), b = "bin/headless-run";
		rmrf(b);
		// (a TSX file of 2,000 lines for the code editor: examples/ts-todo's app repeated)
		mkdirs(b);
		File.saveContent('$b/code.tsx', repeatedLines("examples/ts-todo/app.tsx", 2000));
		for (pass in ["1", "2"]) {
			var o = '$b/$pass';
			// (helder.ui.code: examples/code-editor on it, scripted)
			run(h, [
				"run", "--headless", "examples/code-editor", "--script", "tests/headless/code-editor.json", "--size", "900x640", "--tree", '$o/code-multi.json',
				"--at", "mark:multi", "--tree", '$o/code-undone.json', "--at", "mark:undone", "--tree", '$o/code-find.json', "--at", "mark:find", "--snap",
				'$o/code-end.png', "--tree", '$o/code-end.json', "--", '$b/code.tsx'
			]);
			for (app in ["todo", "ts-todo"])
				run(h, [
					"run", "--headless", 'examples/$app', "--script", "tests/headless/todo.json", "--snap", '$o/$app-toggled.png', "--tree", '$o/$app-toggled.json',
					"--at", "mark:toggled", "--tree", '$o/$app-end.json', "--trace", '$o/$app.jsonl'
				]);
			run(h, [
				"run", "--headless", "examples/todo", "--script", "tests/headless/todo.json", "--frames", "6", "--every", "2", "--start", "0.3", "-o", '$o/frames', "--keys",
				"--pointer"
			]);
			// (live literals: a dev build's title colour and text patched by the script, the next frame showing them)
			for (app in ["todo", "ts-todo"])
				run(h, [
					"run", "--headless", "--dev", 'examples/$app', "--script", "tests/headless/literals.json", "--snap", '$o/$app-literal-before.png', "--at", "mark:before",
					"--snap", '$o/$app-literal-after.png', "--tree", '$o/$app-literal.json', "--at", "mark:patched"
				]);
			run(h, ["run", "--headless", "examples/glow", "--size", "320x240", "--snap", '$o/glow.png', "--at", "0.5"]);
			// (a million rows: tests/headless/million.json's marks)
			for (app in ["million", "ts-million"]) {
				var args = ["run", "--headless", 'examples/$app', "--script", "tests/headless/million.json", "--size", "480x640"];
				for (m in ["start", "down", "up", "end", "keys", "kept", "before", "inserted"])
					args = args.concat(["--tree", '$o/$app-$m.json', "--at", 'mark:$m']);
				run(h, args.concat(["--snap", '$o/$app-last.png', "--at", "mark:last"]));
			}
			// (helder.ui.motion: examples/motion scripted, its trace and frame strips; again under --reduced-motion)
			var shots = [];
			for (strip in [
				{name: "rows", at: [0.32, 0.37, 0.42, 0.47, 0.52, 0.6]},
				{name: "zoom", at: [1.62, 1.68, 1.74, 1.8, 1.88, 2.0]},
				{name: "theme", at: [3.02, 3.08, 3.14, 3.2, 3.3, 3.5]}
			])
				for (k => t in strip.at)
					shots = shots.concat(["--snap", '$o/motion-${strip.name}-$k.png', "--at", '$t']);
			run(h, ["run", "--headless", "examples/motion/Motion.hx", "--script", "tests/headless/motion.json", "--trace", '$o/motion.jsonl'].concat(shots)
				.concat(["--tree", '$o/motion-end.json', "--at", "end"]));
			run(h, ["run", "--headless", "examples/motion/Motion.hx", "--script", "tests/headless/motion.json", "--reduced-motion", "--trace", '$o/motion-reduced.jsonl']);
			run(h, ["run", "--headless", "examples/motion/main.tsx", "--script", "tests/headless/motion.json", "--trace", '$o/motion-ts.jsonl']);
			run(h, [
				"run", "--headless", "apps/viewer", "--script", "tests/headless/viewer.json", "--size", "480x360", "--tree", '$o/viewer-menu.json', "--at", "mark:menu",
				"--tree", '$o/viewer-end.json'
			]);
		}
		exe('$b/Check', cps(["src", "tests/headless"]).concat(["-main", "Check"]));
		run(exePath('$b/Check', HOST), [b].concat(BLESS ? ["--bless"] : []));
		// (a video: where ffmpeg is installed)
		if (Sys.command("sh", ["-c", "command -v ffmpeg >/dev/null"]) == 0) {
			run(h, ["run", "--headless", "examples/todo", "--script", "tests/headless/todo.json", "--video", '$b/todo.mp4', "--keys", "--pointer"]);
			if (!FileSystem.exists('$b/todo.mp4') || FileSystem.exists('$b/todo.frames')) throw new Failed('$b/todo.mp4: not written, or its frames left');
		} else Sys.println("headless-run: no ffmpeg: --video not checked");
	}

	static function studioLane() {
		var h = helderCli(), b = "bin/studio-check";
		// (the studio's files first: their links into the copies)
		rmrf("bin/studio");
		rmrf(b);
		run(h, ["studio", "--help"]);
		for (app in ["todo", "ts-todo"]) {
			// (a copy, a repository of its own: its branch in the sidebar the same everywhere)
			copy('examples/$app', '$b/$app');
			run("git", ["init", "-q", "-b", "studio", '$b/$app']);
			run(h, [
				"run", "--headless", "apps/studio", "--script", "tests/studio/edit.json", "--size", "1180x740", "--snap", '$b/$app-overview.png', "--at",
				"mark:overview", "--snap", '$b/$app-zoomed.png', "--at", "mark:zoomed", "--snap", '$b/$app-selected.png', "--at", "mark:selected", "--snap", '$b/$app-end.png', "--at", "mark:end", "--",
				'$b/$app', "--events", '$b/$app.jsonl'
			]);
		}
		exe('$b/Check', cps(["src", "tests/studio"]).concat(["-main", "Check"]));
		run(exePath('$b/Check', HOST), [b].concat(BLESS ? ["--bless"] : []));
	}

	// the demos' stills: [name, entry, script or "", the program's arguments, times (seconds or mark:<name>)]
	static final DEMO_SHOTS:Array<{name:String, entry:String, script:String, flags:Array<String>, args:Array<String>, at:Array<String>}> = [
		{name: "showreel-title", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "title"], at: ["3.4"]},
		{name: "showreel-launch", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "launch"], at: ["1.0", "7.0"]},
		{name: "showreel-zoom", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "zoom"], at: ["2.4"]},
		{name: "showreel-odometer", entry: "examples/showreel", script: "", flags: ["--reduced-motion"], args: ["--scene", "odometer"], at: ["0.5"]},
		{name: "showreel-million", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "million"], at: ["2.2"]},
		{name: "showreel-type", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "type"], at: ["3.0"]},
		{name: "showreel-material", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "material"], at: ["4.0"]},
		{name: "showreel-canvas", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "canvas"], at: ["3.0"]},
		{name: "showreel-theme", entry: "examples/showreel", script: "", flags: [], args: ["--scene", "theme"], at: ["3.6"]},
		{name: "fx", entry: "examples/fx", script: "", flags: [], args: [], at: ["1.0"]},
		{name: "fx-tour", entry: "examples/fx", script: "", flags: [], args: ["--tour"], at: ["9.6"]},
		{name: "fx-reduced", entry: "examples/fx", script: "", flags: ["--reduced-motion"], args: [], at: ["0.5"]},
		{name: "literal", entry: "examples/literal", script: "examples/literal/demo.json", flags: ["--pointer"], args: [], at: ["mark:frozen", "mark:fallen"]},
		{name: "notes", entry: "examples/notes", script: "examples/notes/demo.json", flags: ["--pointer", "--keys"], args: [], at: ["mark:launcher", "mark:end"]}
	];

	// each demo run headless (it runs: its exit status), its stills against the goldens
	static function demosLane() {
		var h = helderCli(), b = "bin/demos";
		rmrf(b);
		mkdirs(b);
		for (d in DEMO_SHOTS) {
			var args = ["run", "--headless", d.entry, "--scale", "0.5"].concat(d.flags);
			if (d.script != "") args = args.concat(["--script", d.script]);
			for (t in d.at)
				args = args.concat(["--snap", '$b/${d.name}-${t.replace("mark:", "")}.png', "--at", t]);
			run(h, d.args.length > 0 ? args.concat(["--"]).concat(d.args) : args);
		}
		exe('$b/Check', cps(["src", "tests/demos"]).concat(["-main", "Check"]));
		run(exePath('$b/Check', HOST), [b].concat(BLESS ? ["--bless"] : []));
	}

	// (the site apps/studio/web/build.mjs writes: the studio for the web, todo and 50 screens bundled)
	static function studioWeb() {
		var b = "bin/studio-web";
		rmrf(b);
		run(NODE, ["tests/story/host/host.mjs", "project", '$b/screens50']);
		// (helder.compiler.web's toolchain, as the compiler-web lane builds it: structural edits built in the browser)
		run(NODE, ["src/helder/compiler/web/build.mjs", "bin/compiler-web"]);
		run(NODE, ["apps/studio/web/build.mjs", '$b/site', "--compiler", "bin/compiler-web", "examples/todo=Todo", '$b/screens50=50 screens']);
		run(NODE, ["tests/studio-web/check.mjs", '$b/site', b].concat(BLESS ? ["--bless"] : []));
	}

	static function storyHost() {
		var b = "bin/story-host";
		rmrf(b);
		run(NODE, ["tests/story/host/host.mjs", "gen", b]);
		var cp = cps(["src", "examples/todo", '$b/gen']).concat(["-D", "hxmc.dev", "-D", "helder.headless"]);
		native('$b/BenchHost', cp.concat(["-main", "BenchHost"]), HOST);
		// (the desktop studio on the same stories: helder run's)
		Sys.putEnv("HELDER", helderCli());
		run(NODE, ["tests/story/host/host.mjs", "measure", b]);
	}

	static function motionBench() {
		var h = helderCli(), b = "bin/motion-bench";
		mkdirs(b);
		var rows = ["| 1,000 boxes | frames | ms median | ms p95 | retarget frames' ms median | GC bytes a frame (median) |", "|---|---|---|---|---|---|"];
		var gc = new Map<String, Float>();
		for (mode in ["still", "motion"]) {
			run(h, ["run", "--headless", "tests/bench/MotionStress.hx", "--script", "tests/bench/motion-stress.json", "--stats", '$b/$mode.json', "--", "1000"].concat(mode == "still" ? ["still"] : []));
			var frames:Array<Dynamic> = haxe.Json.parse(File.getContent('$b/$mode.json')).frames;
			// (once the boxes move: between their retargets, and the frames of them)
			var steady = [for (f in frames) if (f.t >= 0.6 && f.t < 3 && Math.abs((f.t - 0.5) % 0.25) > 0.02) f];
			var at = [for (f in frames) if (f.t >= 0.6 && f.t < 3 && Math.abs((f.t - 0.5) % 0.25) <= 0.001) f];
			function stat(fs:Array<Dynamic>, k:String, q:Float):Float {
				var v:Array<Float> = [for (f in fs) Reflect.field(f, k)];
				v.sort(Reflect.compare);
				return v.length == 0 ? 0 : v[Std.int(Math.min(v.length - 1, v.length * q))];
			}
			gc.set(mode, stat(steady, "gcBytes", 0.5));
			rows.push('| $mode | ${steady.length} | ${stat(steady, "ms", 0.5)} | ${stat(steady, "ms", 0.95)} | ${stat(at, "ms", 0.5)} | ${gc.get(mode)} |');
		}
		var table = rows.join("\n");
		Sys.println(table);
		File.saveContent('$b/results.md', table + "\n");
		if (gc.get("motion") > gc.get("still")) throw new Failed('motion-bench: the moving frames allocate ${gc.get("motion")} bytes, the still ones ${gc.get("still")}');
	}

	static function codeBench() {
		var h = helderCli(), b = "bin/code-bench";
		mkdirs(b);
		File.saveContent('$b/code.tsx', repeatedLines("examples/ts-todo/app.tsx", 10000, true));
		// (the script: focus, go to line 5,000's end, a key a frame; the wheel
		// down a frame at a time, then back up, at a place: a step aimed at a
		// node finds it in the tree, the harness's work, not the frame's)
		var ev:Array<Dynamic> = [{t: 0.2, type: "tap", tag: "code-view", ox: 300, oy: 10}, {t: 0.3, type: "key", name: "g", secondary: true},
			{t: 0.35, type: "type", text: "5000"}, {t: 0.45, type: "key", name: "Enter"}, {t: 0.5, type: "key", name: "End"}];
		var t = 0.6, dt = 1 / 60;
		for (k in 0...240) {
			ev.push(k % 40 == 39 ? {t: t, type: "key", name: "Enter"} : {t: t, type: "type", text: String.fromCharCode("a".code + k % 26)});
			t += dt;
		}
		var typed = t;
		t += 0.5;
		var down = t;
		for (_ in 0...600) {
			ev.push({t: t, type: "wheel", x: 450, y: 320, dy: 80});
			t += dt;
		}
		var up = t;
		for (_ in 0...600) {
			ev.push({t: t, type: "wheel", x: 450, y: 320, dy: -80});
			t += dt;
		}
		var idle = t;
		ev.push({t: t + 1, type: "mark", name: "end"});
		File.saveContent('$b/script.json', haxe.Json.stringify({events: ev}));
		File.saveContent('$b/phases.json', haxe.Json.stringify([
			{name: "keystroke (to its frame)", kind: "keys", from: 0.59, to: typed},
			{name: "wheel down (lines new)", kind: "wheels", from: down, to: up},
			{name: "wheel back up (steady state)", kind: "wheels", from: up, to: idle},
			{name: "idle (caret blinking)", kind: "idle", from: idle + 0.2, to: idle + 1}
		]));
		run(h, ["run", "--headless", "examples/code-editor", "--size", "900x640", "--script", '$b/script.json', "--stats", '$b/stats.json', "--", '$b/code.tsx']);
		run(NODE, ["tests/bench/code.mjs", '$b/stats.json', '$b/phases.json']);
		exe('$b/CodeBench', cps(["src", "tests/bench"]).concat(["-main", "CodeBench", "-D", "hxmc.libc=glibc"]));
		run(exePath('$b/CodeBench', HOST), ['$b/code.tsx']);
	}

	static function millionBench() {
		var h = helderCli(), b = "bin/million-bench";
		mkdirs(b);
		// (the wheel down 400 frames (rows new), back and forth over 1,200 px
		// 10 times (rows made before), End and Top 10 times, a row put in
		// above the view 30 times, Down 120 times, idle)
		var ev:Array<Dynamic> = [], t = 0.5, dt = 1 / 60;
		function at(name:String) {
			ev.push({t: t, type: "mark", name: name});
		}
		at("down");
		for (_ in 0...400) {
			ev.push({t: t, type: "wheel", x: 240, y: 300, dy: 60});
			t += dt;
		}
		at("again");
		for (k in 0...400) {
			ev.push({t: t, type: "wheel", x: 240, y: 300, dy: k % 40 < 20 ? 60 : -60});
			t += dt;
		}
		at("jumps");
		for (k in 0...20) {
			ev.push({t: t, type: "tap", tag: k % 2 == 0 ? "end" : "top"});
			t += 0.2;
		}
		at("inserts");
		for (_ in 0...30) {
			ev.push({t: t, type: "tap", tag: "insert"});
			t += 0.1;
		}
		ev.push({t: t, type: "tap", tag: "top"});
		t += 0.2;
		at("keys");
		for (_ in 0...120) {
			ev.push({t: t, type: "key", name: "ArrowDown"});
			t += dt * 2;
		}
		at("idle");
		t += 1;
		at("end");
		File.saveContent('$b/script.json', haxe.Json.stringify({events: ev}));
		run(h, ["run", "--headless", "examples/million", "--size", "480x640", "--script", '$b/script.json', "--stats", '$b/stats.json']);
		run(NODE, ["tests/bench/million.mjs", '$b/stats.json', '$b/script.json']);
		exe('$b/MillionBench', cps(["src", "tests/bench", "examples/million"]).concat(["-main", "MillionBench", "-D", "hxmc.libc=glibc"]));
		run(exePath('$b/MillionBench', HOST), []);
	}

	// a file's lines repeated to n lines (and a last line break); unique:
	// each repetition's lines but the first's marked with its number (no
	// two lines alike: none laid out once for both)
	static function repeatedLines(path:String, n:Int, unique = false):String {
		var src = File.getContent(path).split("\n"), out = [];
		if (src[src.length - 1] == "") src.pop();
		while (out.length < n) {
			var l = src[out.length % src.length], k = Std.int(out.length / src.length);
			out.push(unique && k > 0 && StringTools.trim(l) != "" ? l + " /* " + k + " */" : l);
		}
		return out.join("\n") + "\n";
	}

	static function sceneWeb() {
		pack();
		// (Model.of's files beside the module, helder.asset's Bundle: fetched by
		// browser.mjs before main; Lazy's at run time)
		rmrf("bin/3d/assets");
		wasm("bin/3d/SceneWebTest.wasm", sceneCp().concat(["-main", "SceneWebTest", "-D", "helder.asset.out=bin/3d/SceneWebTest.wasm"]));
		run(NODE, ["tests/3d/web.mjs", "bin/3d/SceneWebTest.wasm", "bin/3d"]);
	}

	static function compilerWeb() {
		run(NODE, ["src/helder/compiler/web/build.mjs", "bin/compiler-web"]);
		run(NODE, ["tests/compiler-web/node.mjs", "bin/compiler-web"]);
		run(NODE, ["tests/compiler-web/browser.mjs", "bin/compiler-web"]);
	}

	static function web() {
		var cp = cps(["src", "tests/web", "examples/web-demo"]);
		interp(cp, "StaticTest");
		exe("bin/web/StaticTest", cp.concat(["-main", "StaticTest"]));
		run(exePath("bin/web/StaticTest", HOST), []);
		rmrf("bin/web/demo");
		interp(cp, "DemoPage", ["bin/web/demo"]);
		js("bin/web/domtest.js", cp.concat(["-main", "DomTest", "-debug"]));
		js("bin/web/demo/islands.js", cp.concat(["-main", "DemoBundle", "-dce", "full", "-debug"]));
		js("bin/web/demo/counter.js", cp.concat(["-main", "Counter", "-dce", "full", "-D", "js-es=6", "-D", "analyzer-optimize"]));
		wasm("bin/web/demo/lab.wasm", cps(["src", "examples/web-demo"]).concat(["-main", "Lab"]));
		wasm("bin/web/demo/cube.wasm", gfxCp().concat(["-main", "Cube"]));
		// (ui's counter, its root a <Surface>: the page's <Surface>)
		wasm("bin/web/demo/counter-ui.wasm", cps(["src", "examples/counter"]).concat(["-main", "Counter"]));
		for (f in FileSystem.readDirectory("bin/web/demo"))
			if (f.endsWith(".log")) FileSystem.deleteFile('bin/web/demo/$f');
		run(NODE, ["tests/web/web.mjs", "bin/web"]);
	}

	static function uiCp()
		return cps(["src", "tests/gfx", "tests/ui", "examples/counter", "examples/todo", "examples/mail"]);

	static function uiPrograms() {
		var t = GFX_TARGET;
		var programs = ["UiDrawTest", "TodoTest", "StressTest", "ClipboardTest", "EmojiTest", "BoxTest", "SnapTest", "WindowTest"];
		if (t.startsWith("linux-")) programs = programs.concat(["TextInputTest", "LinuxAccessTest", "AtspiProbe", "AccessApp"]);
		if (t.startsWith("windows-")) programs.push("WinAccessTest");
		for (m in programs)
			native('bin/ui/$t/$m', uiCp().concat(["-main", m]), t);
	}

	static function uiDraw() {
		uiPrograms();
		var b = 'bin/ui/$GFX_TARGET';
		var bless = BLESS ? " --bless" : "";
		var gpu = "LIBGL_ALWAYS_SOFTWARE=1 env -u DISPLAY";
		var xvfb = '$XVFB -a -s "-screen 0 640x480x24"';
		shell('$gpu $b/UiDrawTest tests/ui/draw.png $b/draw.png$bless');
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb $b/UiDrawTest tests/ui/draw.png $b/window.png --window');
		shell('$gpu $b/TodoTest tests/ui/todo.png $b/todo.png$bless');
		shell('$gpu $b/StressTest');
		shell('$gpu $b/EmojiTest tests/ui/emoji.png $b/emoji.png');
		shell('$gpu $b/BoxTest tests/ui/boxes.png $b/boxes.png');
		shell('$gpu $b/SnapTest');
		shell('$xvfb $b/ClipboardTest');
		shell('$xvfb $b/TextInputTest');
		shell('$xvfb $b/WindowTest');
		// (AT-SPI: the window's tree read by another process through libatspi,
		// in a D-Bus session: the fixture's, acted on, then the examples' and
		// the guide's, read whole)
		shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb dbus-run-session -- sh -c \'$b/LinuxAccessTest & p=$$!; $b/AtspiProbe fixture; s=$$?; wait $$p && exit $$s\'');
		for (screen in ACCESS_SCREENS)
			shell('LIBGL_ALWAYS_SOFTWARE=1 $xvfb dbus-run-session -- sh -c \'$b/AccessApp ${screen[0]} & p=$$!; $b/AtspiProbe ${screen.join(" ")}; s=$$?; kill $$p; exit $$s\'');
	}

	// AccessApp's screens, each with what its tree must have ("role:name", as
	// AT-SPI names roles; the other platforms' probes map them)
	static final ACCESS_SCREENS = [
		["todo", '"entry:What needs to be done?"', '"push button:Add"', '"check box:Write the docs"', '"check box:Ship it"', '"label:2 items left"'],
		["mail", '"list:Folders"', '"list item:Inbox 3"', '"list:Messages"', '"entry:Search messages"', '"push button:Archive"'],
		["guide", '"push button:+"', '"label:Total: € 60"', '"push button:Delete"', '"push button:Search"', '"entry:Subject"', '"entry:Body"', '"entry:Text"',
			'"password text:Password"']
	];

	static function uiWeb() {
		var b = "bin/ui";
		wasm('$b/WebTodo.wasm', uiCp().concat(["-main", "WebTodo"]));
		run(NODE, ["tests/ui/web.mjs", '$b/WebTodo.wasm', b]);
		wasm('$b/WebField.wasm', uiCp().concat(["-main", "WebField"]));
		run(NODE, ["tests/ui/web-field.mjs", '$b/WebField.wasm']);
		// (the ARIA mirror of the fixture: Playwright's snapshot, Chromium's tree, a screen reader's clicks)
		wasm('$b/WebAccessPage.wasm', uiCp().concat(["-main", "WebAccessPage"]));
		run(NODE, ["tests/ui/web-access.mjs", '$b/WebAccessPage.wasm']);
	}

	// (each program run twice, the second from the first's snapshot)
	static function dev() {
		var os = cps(["src", "tests/os"]).concat(["-D", "hxmc.dev"]);
		var views = cps(["src", "tests/view"]).concat(["-D", "hxmc.dev"]);
		var snapshot = (file:String) -> ["HXMC_DEV_SNAPSHOT" => file];
		exe("bin/dev/HotTest", os.concat(["-main", "HotTest"]));
		exe("bin/dev/HotTestChanged", os.concat(["-main", "HotTest", "-D", "hot_changed"]));
		run(exePath("bin/dev/HotTest", HOST), ["save", "bin/dev/hot.snapshot"]);
		run(exePath("bin/dev/HotTest", HOST), ["restore", "-"], snapshot("bin/dev/hot.snapshot"));
		expect(exePath("bin/dev/HotTestChanged", HOST), ["restore", "-"], snapshot("bin/dev/hot.snapshot"), "changed reset: its type changed");
		expect(exePath("bin/dev/HotTestChanged", HOST), ["restore", "-"], snapshot("bin/dev/hot.snapshot"), "dial reset: its initial value changed");
		interp(os, "HotTest", ["save", "bin/dev/hot-eval.snapshot"]);
		interp(os, "HotTest", ["restore", "-"], snapshot("bin/dev/hot-eval.snapshot"));
		exe("bin/dev/RefreshTest", views.concat(["-main", "RefreshTest"]));
		run(exePath("bin/dev/RefreshTest", HOST), ["save", "bin/dev/refresh.snapshot"]);
		run(exePath("bin/dev/RefreshTest", HOST), ["restore", "-"], snapshot("bin/dev/refresh.snapshot"));
		exe("bin/dev/RefreshTestChanged", views.concat(["-main", "RefreshTest", "-D", "refresh_changed"]));
		expect(exePath("bin/dev/RefreshTestChanged", HOST), ["restore", "-"], snapshot("bin/dev/refresh.snapshot"), "main.tuned reset: its initial value changed");
		interp(views, "RefreshTest", ["save", "bin/dev/refresh-eval.snapshot"]);
		interp(views, "RefreshTest", ["restore", "-"], snapshot("bin/dev/refresh-eval.snapshot"));
		// (the dev loop's server, @hxmc/cli's dev.mjs, run by node with the compiler)
		var compiler = "node_modules/.bin/haxe";
		run(NODE, ["tests/os/dev/dev-web.mjs", compiler, "bin/dev/web"]);
		if (HOST.startsWith("linux-")) shell('$XVFB -a -s "-screen 0 640x480x24" $NODE tests/os/dev/dev-native.mjs $compiler bin/dev/native');
		else run(NODE, ["tests/os/dev/dev-native.mjs", compiler, "bin/dev/native"]);
		run(NODE, ["tests/os/dev/server-verify.mjs", compiler]);
		run(NODE, ["tests/os/dev/dev-verify.mjs", compiler, "Counter", "web"]);
		// (helder dev's asset reload in the page: the same Image, no swap)
		run(NODE, ["tests/os/dev/dev-asset.mjs", helderCli(), "bin/dev/asset"]);
	}

	// (Linux: under Xvfb, a Windows build's Wine too)
	static function devHost() {
		var targets = [HOST].concat([for (t in (Sys.getEnv("DEV_HOST_TARGETS") ?? "").split(",")) if (t != "" && t != HOST) t]);
		for (t in targets) {
			var args = 'tests/os/dev/dev-host.mjs node_modules/.bin/haxe bin/dev-host/$t $t';
			if (HOST.startsWith("linux-")) shell('$XVFB -a -s "-screen 0 640x480x24" $NODE $args') else run(NODE, args.split(" "));
		}
	}

	// --- the examples

	static final HEADER = ~/^\/\/ *(title|summary|tags|demo): *(.*)$/;

	// each example directory's programs with a header naming them,
	//
	//   // title: Cube
	//   // summary: A textured cube casting a soft shadow, its shaders in Haxe
	//   // tags: gfx, shaders, 3d
	//   // demo: canvas 512x384
	//
	// (demo: canvas WxH, a program drawing on a canvas; sound, a program
	// started by a click; island, a JavaScript island of helder.web; module,
	// a wasm module JavaScript calls; none, a program of the command line
	// or of a native window, built by its own lane), each built for
	// wasm32-wasi but the islands, and those on a canvas or playing a sound for this machine
	// too, in parallel, into bin/examples (each one's log beside it), each by
	// the CLI with no flags but the target and the output: `helder build
	// <file> [--target web] -o <out>`.
	static function examples() {
		var h = helderCli();
		var builds:Array<{id:String, target:String, out:String, args:Array<String>}> = [];
		var dirs = FileSystem.readDirectory("examples");
		dirs.sort(Reflect.compare);
		for (dir in dirs) {
			var path = 'examples/$dir';
			var files = [for (f in FileSystem.readDirectory(path)) if (f.endsWith(".hx") || (~/\.tsx?$/.match(f) && !f.endsWith(".d.ts"))) f];
			files.sort(Reflect.compare);
			for (f in files) {
				var head = new Map<String, String>();
				for (line in File.getContent('$path/$f').split("\n")) {
					if (!line.startsWith("//")) break;
					if (HEADER.match(line.trim())) head.set(HEADER.matched(1), HEADER.matched(2).trim());
				}
				if (!head.exists("title")) continue;
				var main = Path.withoutExtension(f);
				var demo = head.get("demo") ?? "";
				var id = dir + (files.length > 1 && main.toLowerCase() != dir.replace("-", "") ? "-" + main.toLowerCase() : "");
				if (demo != "" && demo != "island") {
					var out = 'bin/examples/wasm32-wasi/$id.wasm';
					builds.push({id: id, target: "wasm32-wasi", out: out, args: ["build", '$path/$f', "--target", "web", "-o", out]});
				}
				if (demo.startsWith("canvas") || demo == "sound") {
					var out = exePath('bin/examples/$HOST/$id', HOST);
					builds.push({id: id, target: HOST, out: out, args: ["build", '$path/$f', "-o", out]});
				}
			}
		}
		var t0 = Sys.time();
		var failed = [];
		parallel(builds, b -> {
			mkdirs(Path.directory(b.out));
			var r = build(b.args, b.out + ".log", h);
			var ok = r.code == 0 && FileSystem.exists(b.out);
			Sys.println(b.id.rpad(" ", 22) + " " + b.target.rpad(" ", 15) + " " + (ok ? "ok  " : "FAIL") + " " + Std.string(Math.round(r.seconds * 10) / 10).lpad(" ", 6) + "s");
			if (!ok) {
				failed.push(b.id + " (" + b.target + ")");
				Sys.println(r.log.length > 1500 ? r.log.substr(r.log.length - 1500) : r.log);
			}
		});
		Sys.println('examples: ${builds.length - failed.length}/${builds.length} built, ${Math.round(Sys.time() - t0)}s');
		if (failed.length > 0) throw new Failed(failed.join(", "));
		// (the golf example's simulation, deterministic: recorded rounds replayed natively and as wasm32-wasi, each hole holed in its strokes)
		var replay = exePath('bin/examples/$HOST/golf-replay', HOST);
		run(h, ["build", "examples/golf/GolfReplay.hx", "-o", replay]);
		run(replay, []);
		run(h, ["build", "examples/golf/GolfReplay.hx", "--target", "web", "-o", "bin/examples/wasm32-wasi/golf-replay.wasm"]);
		wasi("bin/examples/wasm32-wasi/golf-replay.wasm");
	}

	// --- the benchmarks

	// (the programs whose size and compile time are tracked: ui and text, scene and physics)
	static final BENCH_BUILDS = [{dir: "examples/todo", main: "Todo"}, {dir: "examples/walker", main: "Walker"}];

	// tests/bench/Bench.hx natively and as wasm32-wasi (BENCH: the workloads,
	// by name, separated by spaces; each in a process of its own), then the
	// examples above built for both: a table
	static function bench() {
		var font = "bin/bench/DejaVuSans.ttf";
		mkdirs("bin/bench");
		File.saveBytes(font, File.getBytes(dejavu()));
		var cp = cps(["src", "tests/bench"]).concat(["-main", "Bench"]);
		// (each built twice: from nothing (-D hxmc.no-module-cache), then with
		// the module cache. The last build is the one run)
		var builds = [];
		function timed(what:String, target:String, out:String, args:Array<String>) {
			var times = [];
			var nothing = ["-D", "hxmc.no-module-cache"];
			for (extra in [nothing, []]) {
				var t0 = Sys.time();
				if (target == HOST) native(out, args.concat(extra), HOST) else wasm(out, args.concat(extra));
				times.push(Sys.time() - t0);
			}
			builds.push({what: what, target: target, out: target == HOST ? exePath(out, HOST) : out, times: times});
		}
		timed("Bench", HOST, "bin/bench/Bench", cp);
		timed("Bench", "wasm32-wasi", "bin/bench/Bench.wasm", cp);
		var names = (Sys.getEnv("BENCH") ?? "").split(" ").filter(n -> n != "");
		if (names.length == 0) names = [for (l in output(exePath("bin/bench/Bench", HOST), [font, "list"]).split("\n")) if (l.trim() != "") l.trim()];
		var md = ["# Benchmarks", "", 'tests/bench/Bench.hx (`bun run test bench`), ${Date.now().toString().substr(0, 10)}, ${cpuName()}.', ""];
		md.push("Milliseconds per run (median, p99, max), GC heap bytes allocated per run, collections (all runs; majors), the longest time collecting in one run (hxmc.GcStats' pauses, natively and on wasm32).");
		for (target in [HOST, "wasm32-wasi"]) {
			md = md.concat(["", '## $target', "", "| workload | runs | median | p99 | max | KB/run | GCs | majors | longest GC |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]);
			for (n in names) {
				var wasi = ["--stack-size=65500", "tests/bench/wasi.mjs", "bin/bench/Bench.wasm", font, n];
				var out = target == HOST ? output(exePath("bin/bench/Bench", HOST), [font, n]) : output(NODE, wasi, true), mark = "";
				// (wasm32's runtime crashes in a major collection with arrays of tens
				// of MB, scene.world.100k's: again with an old space it fits in, and
				// node's own stack size, where the overflow is an error, not a crash)
				if (out == null) {
					out = output("env", ["RT_OLD_MB=512", NODE].concat(wasi.slice(1)));
					mark = " (RT_OLD_MB=512)";
				}
				for (l in out.split("\n")) {
					var c = l.trim().split(" ");
					if (c[0] != "bench") continue;
					var kb = Math.round(Std.parseFloat(c[6]) / 1024 * 10) / 10;
					md.push('| ${c[1]}$mark | ${c[2]} | ${c[3]} | ${c[4]} | ${c[5]} | $kb | ${c[7]} | ${c[8]} | ${c[9]} |');
					Sys.println('$target ${c[1]}: ${c[3]} ms median, ${c[4]} p99, $kb KB/run, ${c[7]} GCs');
				}
			}
		}
		for (b in BENCH_BUILDS) {
			var args = cps(["src", b.dir]).concat(["-main", b.main]);
			timed(b.main, HOST, 'bin/bench/${b.main}', args);
			timed(b.main, "wasm32-wasi", 'bin/bench/${b.main}.wasm', args.concat(["-D", "hxmc.wasm-eh=legacy"]));
		}
		md = md.concat([
			"", "## Builds", "",
			"Seconds to compile, without a compilation server: from nothing (-D hxmc.no-module-cache) and with the module cache on disk.",
			"", "| program | target | size (KB) | build | cached |", "| --- | --- | ---: | ---: | ---: |"
		]);
		for (b in builds)
			md.push('| ${b.what} | ${b.target} | ${Math.round(FileSystem.stat(b.out).size / 1024)} | ' + [for (t in b.times) Math.round(t * 10) / 10].join(" | ") + " |");
		File.saveContent("bin/bench/results.md", md.join("\n") + "\n");
		Sys.println(md.join("\n"));
	}

	// tests/bench/Jobs.hx: each variant RUNS times, each in a process of its
	// own, the medians and the spread of its columns; the job alone; what
	// each variant adds to the program's size and build; JobsWasm.wasm with a
	// worker instance (tests/bench/jobs.mjs). JOBS: the variants (all)
	static final JOB_VARIANTS = ["none", "a", "b", "d", "d0"];

	static function jobs() {
		var dir = "bin/jobs", font = '$dir/DejaVuSans.ttf', png = '$dir/photo.png';
		mkdirs(dir);
		File.saveBytes(font, File.getBytes(dejavu()));
		if (!FileSystem.exists(png)) run(NODE, ["tests/bench/photo.mjs", png]);
		var cp = cps(["src", "tests/bench"]);
		exe('$dir/Jobs', cp.concat(["-main", "Jobs"]));
		wasm('$dir/JobsWasm.wasm', cp.concat(["-main", "JobsWasm"]));
		var bin = exePath('$dir/Jobs', HOST);
		run(bin, [font, png, "check"]);
		var runs = Std.parseInt(Sys.getEnv("RUNS") ?? "") ?? 5;
		var variants = (Sys.getEnv("JOBS") ?? "").split(" ").filter(v -> v != "");
		if (variants.length == 0) variants = JOB_VARIANTS;
		// (a column's median, and its spread when it has one)
		function cell(rows:Array<Array<String>>, c:Int):String {
			var v = [for (r in rows) Std.parseFloat(r[c])];
			v.sort(Reflect.compare);
			var m = v[v.length >> 1], r = (x:Float) -> Std.string(Math.round(x * 100) / 100);
			return v[0] == v[v.length - 1] ? r(m) : '${r(m)} (${r(v[0])}-${r(v[v.length - 1])})';
		}
		function lines(cmd:String, args:Array<String>):Array<Array<String>>
			return [for (_ in 0...runs) for (l in output(cmd, args).split("\n")) if (l.startsWith("jobs ")) l.split(" ")];
		var md = ["# Jobs", "", 'tests/bench/Jobs.hx (`bun run test jobs-bench`), ${Date.now().toString().substr(0, 10)}, ${cpuName()}; $runs runs of each, medians (and their spread).', ""];
		for (mode in ["probe", "natural"]) {
			md = md.concat([
				"", '## $HOST, ${mode == "probe" ? "a collection at every frame of the job" : "collections from the garbage alone"}', "",
				"| variant | frame median | p99 | max | longest pause | pauses | GCs | majors | decode | longest stop | GC heap KB/frame |",
				"| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
			]);
			for (v in variants) {
				var rows = lines(bin, [font, png, v].concat(mode == "probe" ? ["probe"] : []));
				md.push('| $v | ' + [for (c in 3...13) cell(rows, c)].join(" | ") + " |");
				Sys.println('$mode $v: longest pause ${cell(rows, 6)} ms, frame max ${cell(rows, 5)} ms');
			}
		}
		md = md.concat(["", "## The job alone", "", "| job | ms | min | max | GC heap growth | worker's allocation |", "| --- | ---: | ---: | ---: | ---: | ---: |"]);
		for (v in ["b", "d"]) {
			var c = output(bin, [font, png, "alone", v]).split("\n").filter(l -> l.startsWith("alone "))[0].split(" ");
			md.push('| $v | ${c[2]} | ${c[3]} | ${c[4]} | ${c[5]} | ${c[6]} |');
		}
		// (each variant alone in the program, with the ui and without it:
		// sizes, and builds from nothing and with the module cache)
		md = md.concat(["", "## Sizes and builds", "", "| variant | size (KB) | without the ui | build (s) | cached |", "| --- | ---: | ---: | ---: | ---: |"]);
		for (v in ["none", "a", "b", "d"]) {
			var args = cp.concat(["-main", "Jobs", "-D", 'jobs_only=$v']), out = '$dir/only/Jobs-$v';
			var times = [];
			for (extra in [["-D", "hxmc.no-module-cache"], []]) {
				var t0 = Sys.time();
				native(out, args.concat(extra), HOST);
				times.push(Math.round((Sys.time() - t0) * 100) / 100);
			}
			native('$out-bare', args.concat(["-D", "jobs_bare"]), HOST);
			var kb = (f:String) -> Math.round(FileSystem.stat(exePath(f, HOST)).size / 1024 * 10) / 10;
			md.push('| $v | ${kb(out)} | ${kb('$out-bare')} | ${times[0]} | ${times[1]} |');
		}
		md = md.concat([
			"", "## wasm32-wasi, a worker instance", "",
			"| variant | frame median | p99 | max | GCs | decode | worker's copy out | main's copy in | longest task |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
		]);
		// (node's WASI allocates in its fast API calls, which can collect
		// meanwhile and crash V8 once linear memory is large: no fast calls)
		for (v in ["none", "a", "b"]) {
			var rows = lines(NODE, ["--no-turbo-fast-api-calls", "--stack-size=65500", "tests/bench/jobs.mjs", '$dir/JobsWasm.wasm', font, png, v]);
			md.push('| $v | ' + [for (c in 3...11) cell(rows, c)].join(" | ") + " |");
		}
		// (the same through helder.jobs: frames on helder.async's loop, ImageJobs' job, a job's round trip)
		exe('$dir/JobsApi', cp.concat(["-main", "JobsApi"]));
		wasm('$dir/JobsApi.wasm', cp.concat(["-main", "JobsApi"]));
		var api = exePath('$dir/JobsApi', HOST);
		var wasi = ["--no-warnings", "--no-turbo-fast-api-calls", "--stack-size=65500", "src/helder/test/wasi.mjs", '$dir/JobsApi.wasm'];
		md = md.concat(["", "## Through helder.jobs (JobsApi.hx)", "", "| target | variant | frame median | p99 | max | longest pause | decode |", "| --- | --- | ---: | ---: | ---: | ---: | ---: |"]);
		for (mode in ["probe", "natural", "wasm"])
			for (v in ["none", "inline", "job", "gc"]) {
				var a = [font, png, v].concat(mode == "probe" ? ["probe"] : []);
				var rows = [for (_ in 0...runs) for (l in (mode == "wasm" ? output(NODE, wasi.concat(a)) : output(api, a)).split("\n")) if (l.startsWith("api ")) l.split(" ")];
				md.push('| ${mode == "wasm" ? "wasm32-wasi" : '$HOST, $mode'} | $v | ' + [for (c in 3...8) cell(rows, c)].join(" | ") + " |");
			}
		var o = (l:String) -> [for (x in l.split("\n")) if (x.startsWith("overhead ")) x.split(" ")][0];
		var on = o(output(api, ["overhead"])), ow = o(output(NODE, wasi.concat(["overhead"])));
		md = md.concat(["", "A job's round trip, from the awaiting task (µs):", "", "| target | GC-free | GC | on the loop |", "| --- | ---: | ---: | ---: |",
			'| $HOST | ${on[1]} | ${on[2]} | ${on[3]} |', '| wasm32-wasi | ${ow[1]} | ${ow[2]} | ${ow[3]} |']);
		File.saveContent('$dir/results.md', md.join("\n") + "\n");
		Sys.println(md.join("\n"));
	}

	// (DejaVu Sans: fonts-dejavu-core's, else fontconfig's)
	static function dejavu():String {
		var known = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf";
		if (FileSystem.exists(known)) return known;
		var f = output("fc-match", ["-f", "%{file}", "DejaVu Sans"]).trim();
		if (!f.endsWith("DejaVuSans.ttf")) throw new Failed("bench: no DejaVu Sans (fonts-dejavu-core)");
		return f;
	}

	static function cpuName():String {
		try {
			for (l in File.getContent("/proc/cpuinfo").split("\n"))
				if (l.startsWith("model name")) return l.substr(l.indexOf(":") + 1).trim() + ", " + cpus() + " cores";
		} catch (_) {}
		return HOST;
	}

	// a program's standard output (it must succeed; mayFail: null if it does not)
	static function output(cmd:String, args:Array<String>, mayFail = false):Null<String> {
		args = nodeArgs(cmd, args);
		var p = new Process(cmd, args);
		var out = p.stdout.readAll().toString();
		p.stderr.readAll();
		var code = p.exitCode();
		p.close();
		if (code != 0 && mayFail) return null;
		if (code != 0) throw new Failed('${[cmd].concat(args).join(" ")}: exit code $code');
		return out;
	}

	// --- building and running

	static function cps(dirs:Array<String>):Array<String>
		return [for (d in dirs) for (a in ["-cp", d]) a];

	// the compiler on Eval: `--run main args`
	static function interp(cp:Array<String>, main:String, ?args:Array<String>, ?env:Map<String, String>)
		run(TOOL, cp.concat(["--run", main]).concat(args ?? []), env);

	static function js(out:String, args:Array<String>) {
		mkdirs(Path.directory(out));
		run(TOOL, args.concat(["-js", out]));
	}

	// a program for this machine, for wasm32-wasi, for a target (Linux: the
	// dynamic glibc mode, which loads the GPU's and the sound's drivers)
	static function exe(out:String, args:Array<String>)
		hxmc(exePath(out, HOST), args);

	static function wasm(out:String, args:Array<String>)
		hxmc(out, args.concat(targetArgs("wasm32-wasi")));

	static function native(out:String, args:Array<String>, target:String)
		hxmc(exePath(out, target), args.concat(targetArgs(target)));

	static function targetArgs(target:String):Array<String>
		return ["-D", 'hxmc.target=$target'].concat(target.startsWith("linux-") ? ["-D", "hxmc.libc=glibc"] : []);

	static function exePath(out:String, target:String):String
		return target.startsWith("windows-") ? '$out.exe' : out;

	// a build by hxmc, its log beside the output (printed when it fails)
	static function hxmc(out:String, args:Array<String>) {
		mkdirs(Path.directory(out));
		var r = build(args.concat(["--custom-target", 'hxmc=$out']), '$out.log');
		if (r.code != 0) {
			Sys.println(r.log);
			throw new Failed('$out: the build failed');
		}
		Sys.println('$out (${Math.round(r.seconds * 10) / 10}s)');
	}

	static function build(args:Array<String>, log:String, ?tool:String):{code:Int, log:String, seconds:Float} {
		var t0 = Sys.time();
		var p = new Process(tool ?? TOOL, args);
		// (the compiler's messages are on stderr: read first, its pipe would fill)
		var err = p.stderr.readAll().toString();
		var out = p.stdout.readAll().toString();
		var code = p.exitCode();
		p.close();
		mkdirs(Path.directory(log));
		File.saveContent(log, out + err);
		return {code: code, log: out + err, seconds: Sys.time() - t0};
	}

	static function wasi(module:String)
		run(NODE, ["--stack-size=65500", "tests/wasi.mjs", module]);

	// node's fast API calls off: WASI's fd_write is one, and a V8 collection
	// started inside it segfaults once a module's memory is large (node 22;
	// tests/bench/results/jobs.md)
	static function nodeArgs(cmd:String, args:Array<String>):Array<String>
		return cmd == NODE && args.indexOf("--no-turbo-fast-api-calls") < 0 ? ["--no-turbo-fast-api-calls"].concat(args) : args;

	static function run(cmd:String, args:Array<String>, ?env:Map<String, String>) {
		args = nodeArgs(cmd, args);
		var saved = new Map<String, Null<String>>();
		if (env != null) for (k => v in env) {
			saved.set(k, Sys.getEnv(k));
			Sys.putEnv(k, v);
		}
		var code = Sys.command(cmd, args);
		// (null: unset again, not left empty: the variables as they were before)
		for (k => v in saved) Sys.putEnv(k, v);
		if (code != 0) throw new Failed('${[cmd].concat(args).join(" ")}: exit code $code');
	}

	static function shell(cmd:String)
		run("sh", ["-c", cmd]);

	// a program's output must contain `text`
	// (and exit with `want`, 0 by default; env's variables set for it, then
	// given back their values)
	static function expect(cmd:String, args:Array<String>, env:Map<String, String>, text:String, want = 0) {
		var saved = new Map<String, Null<String>>();
		for (k => v in env) {
			saved.set(k, Sys.getEnv(k));
			Sys.putEnv(k, v);
		}
		var p = new Process(cmd, args);
		var out = p.stdout.readAll().toString() + p.stderr.readAll().toString();
		var code = p.exitCode();
		p.close();
		// (null: unset again, not left empty: the variables as they were before)
		for (k => v in saved) Sys.putEnv(k, v);
		Sys.print(out);
		if (code != want || !out.contains(text)) throw new Failed('${[cmd].concat(args).join(" ")}: expected "$text" (exit code $code, not $want)');
	}

	// each item in a thread, half the cores' worth at once (each build is parallel itself)
	static function parallel<T>(items:Array<T>, f:T->Void) {
		var jobs = Std.parseInt(Sys.getEnv("JOBS") ?? "") ?? Std.int(Math.max(1, cpus() / 2));
		var queue = items.copy();
		var mutex = new sys.thread.Mutex();
		var done = new sys.thread.Lock();
		var workers = Std.int(Math.min(jobs, queue.length));
		for (_ in 0...workers)
			sys.thread.Thread.create(() -> {
				while (true) {
					mutex.acquire();
					var item = queue.shift();
					mutex.release();
					if (item == null) break;
					f(item);
				}
				done.release();
			});
		for (_ in 0...workers) done.wait();
	}

	static function cpus():Int {
		var n = Std.parseInt(Sys.getEnv("NUMBER_OF_PROCESSORS") ?? "");
		if (n != null) return n;
		try {
			var p = new Process("getconf", ["_NPROCESSORS_ONLN"]);
			n = Std.parseInt(p.stdout.readAll().toString().trim());
			p.close();
		} catch (_) {}
		return n ?? 4;
	}

	// hxmc's name of this machine
	static function hostTarget():String {
		var os = switch Sys.systemName() {
			case "Windows": "windows";
			case "Mac": "macos";
			case _: "linux";
		}
		var arch = if (os == "windows") Sys.getEnv("PROCESSOR_ARCHITECTURE") ?? "AMD64" else {
			var p = new Process("uname", ["-m"]);
			var m = p.stdout.readAll().toString().trim();
			p.close();
			m;
		}
		return os + "-" + (["aarch64", "arm64", "ARM64"].contains(arch) ? "arm64" : "x86_64");
	}

	static function mkdirs(dir:String)
		if (dir != "" && !FileSystem.exists(dir)) FileSystem.createDirectory(dir);

	// (only under bin/; a link is removed, never followed: a link to the
	// checkout once took the checkout with it)
	static function rmrf(path:String) {
		var bin = FileSystem.fullPath("bin");
		var parent = FileSystem.fullPath(Path.directory(FileSystem.absolutePath(path)));
		if (bin == null || parent == null || !(parent + "/").startsWith(bin + "/") && parent != bin)
			throw new Failed('rmrf: $path is not under bin/');
		removeTree(path);
	}

	static function removeTree(path:String) {
		if (!FileSystem.exists(path)) return;
		var abs = FileSystem.absolutePath(path);
		var real = FileSystem.fullPath(abs);
		var parent = FileSystem.fullPath(Path.directory(abs));
		if (real != Path.join([parent, Path.withoutDirectory(abs)])) {
			FileSystem.deleteFile(abs); // a link: the link alone
			return;
		}
		if (FileSystem.isDirectory(abs)) {
			for (f in FileSystem.readDirectory(abs)) removeTree('$abs/$f');
			FileSystem.deleteDirectory(abs);
		} else FileSystem.deleteFile(abs);
	}
}

class Failed extends haxe.Exception {}
