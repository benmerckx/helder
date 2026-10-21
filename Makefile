# universe: an experimental app/GUI stack on hxmc (README.md). GNU make, from
# the repository root; needs node 22 and git.
#
#   make hxmc            the hxmc checkout (HXMC, at HXMC_REV) and its tool, port and std,
#                        linked into bin/ (bin/hxmc, bin/port, bin/wasm)
#   make headless        the checks that need no GPU, display or browser
#   make help            the targets below
#
# The packages' checks are the ones hxmc's Makefile had until the split
# (hxmc a994ea3): they run with hxmc's tool (bin/hxmc/hxmc), its merged std
# (bin/hxmc/std) and its port (bin/port/haxe), from a checkout of hxmc built
# from source. HXMC=<dir> uses another checkout (one already built: nothing
# is cloned; `make hxmc` still builds what is missing there).

HXMC ?= hxmc
HXMC_URL ?= https://github.com/benmerckx/hxmc.git
# the pinned hxmc commit (the nightly: hxmc's main at d0c1758)
HXMC_REV ?= d0c1758032cc662959c805067bc8d446514b489e

export HXMC_DIR := $(abspath $(HXMC))
export HAXE_STD_PATH := $(abspath $(HXMC))/haxe/upstream/std
export HXMC_RT_DIR := $(CURDIR)/bin/hxmc/rt
JOBS ?= $(shell nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
NODE ?= node
HOST ?= $(if $(filter Darwin,$(shell uname -s)),macos,linux)-$(if $(filter aarch64 arm64,$(shell uname -m)),arm64,x86_64)
# `make gfx-programs`: any of the six targets, or the host's (`make gfx-check GFX_TARGET=windows-x86_64`: under Wine)
GFX_TARGET ?= $(HOST)
# `make audio-programs`, `make audio-check`: the same for packages/os's audio
AUDIO_TARGET ?= $(HOST)
# `make android-programs`, `android-check`, `android-device-check`: android-x86_64 or android-arm64
ANDROID_TARGET ?= android-x86_64
# `make ios-programs`, `ios-check`: ios-sim-arm64 or ios-arm64 (`ios-sim-check`: the simulator's, on a Mac)
IOS_TARGET ?= ios-sim-arm64
# `make site`: a directory of lix binaries to publish under tools/, and a checkout of hxmc's bench-data branch
LIX_DIR ?=
BENCH_DATA ?=

TOOL := bin/hxmc/hxmc
PORT_BIN := bin/port/haxe
# (hxmc's Makefile names these as prerequisites; here the tool's build makes them)
STD :=
HOST_RT :=
WASI := ulimit -s unlimited 2>/dev/null || true; $(NODE) --stack-size=65500 $(HXMC)/hxmc/bootstrap/wasi.mjs
RUN = ulimit -s unlimited 2>/dev/null || true; $(TOOL)
HXMC_ARGS := -cp bin/hxmc/std --custom-target hxmc
EXE = $(if $(findstring windows,$(1)),.exe)

# $(call hxmc,<out>,<args>): a build by the tool, its log next to the output
define hxmc
@mkdir -p $(dir $(1))
ulimit -s unlimited 2>/dev/null || true; $(TOOL) $(1) $(2) > $(1).log 2>&1 || { cat $(1).log; exit 1; }
@ls -l $(1)
endef

.DEFAULT_GOAL := help
.PHONY: help hxmc headless gfx-programs devhost-programs gfx-check gfx-web-check gfx-cache-check gfx-shader-check 3d-programs 3d-check 3d-web-check 3d-sizes \
	android-programs android-check android-device-check touch-check ios-programs ios-check ios-sim-check \
	audio-programs audio-check audio-web-check ui-programs view-check web-check text-check ui-check ui-layout-fuzz ui-layout-reduce \
	theme-check theme-fidelity-check theme-dom-check web-widgets ui-draw-check ui-web-check dev-check site site-check examples-check clean

help:
	@sed -n '/^# --- Targets/,$$p' $(MAKEFILE_LIST) | sed -n 's/^## \{0,1\}//p'

# --- hxmc, built from source ---

$(HXMC)/.git:
	git clone --filter=blob:none $(HXMC_URL) $(HXMC)
	git -C $(HXMC) checkout -q $(HXMC_REV)
	git -C $(HXMC) submodule update --init --depth 1

hxmc: $(HXMC)/.git
	$(MAKE) -C $(HXMC) hxmc std rt
	@mkdir -p bin
	ln -sfn $(abspath $(HXMC))/bin/hxmc bin/hxmc

$(TOOL):
	$(MAKE) --no-print-directory hxmc

$(PORT_BIN): $(TOOL)
	$(MAKE) -C $(HXMC) port
	ln -sfn $(abspath $(HXMC))/bin/port bin/port

wasm: $(TOOL)
	$(MAKE) -C $(HXMC) wasm
	ln -sfn $(abspath $(HXMC))/bin/wasm bin/wasm

# --- Targets ---
## hxmc        the hxmc checkout (HXMC, cloned at HXMC_REV when missing) and its tool, std and
##             runtime objects, linked as bin/hxmc
## headless    the checks that need no GPU, display or browser: view-check, text-check, ui-check,
##             theme-check, gfx-shader-check, examples-check
## gfx-programs  bin/gfx/GFX_TARGET/{GfxTest,Triangle,Cube,Instances,Targets,Mips,Formats}[.exe]: packages/gfx's test programs (Linux: glibc mode)
## android-programs  bin/android/ANDROID_TARGET/*.apk: APKs written by hxmc (android-x86_64, android-arm64)
## android-check  their structure (hxmc/test/ApkCheck.hx: zip, manifest, ELF, v2 signature, classes.dex)
## android-device-check  the Android tests on the device or emulator adb reaches (android.sh, android-native.sh, android-mix.sh, android-touch.sh)
## touch-check  packages/os's touch gesture (TouchDrag, Android's and iOS's: a tap, a drag, a fling's glide) natively here
## ios-programs  bin/ios/IOS_TARGET/*.app, Cube.ipa: iOS apps written by hxmc (ios-sim-arm64, ios-arm64); bin/ios/SimTap (macOS)
## ios-check   their structure (hxmc/test/IosCheck.hx: bundle, Info.plist, Mach-O, code signature)
## ios-sim-check  IosTest on an iPhone simulator (a Mac with Xcode: packages/gfx/test/ios.sh)
## gfx-check   packages/gfx: the examples (triangle, cube, instances, targets, mips, formats) headless and in a window, against
##             golden images (packages/gfx/test/check.sh; Linux: Mesa, Xvfb; macOS: Metal, Cocoa);
##             GFX_TARGET=windows-x86_64: D3D11 and Win32 under Wine
## gfx-web-check  packages/gfx on WebGPU and WebGL2 (wasm32-wasi): the same, headless and in a
##             canvas, in headless Chromium (packages/gfx/test/web.mjs; Playwright with Chromium);
##             then built with -D hxmc.wasm-gc (the hybrid module)
## gfx-cache-check  the module cache across WasmGC and native builds on one store: WebTest with
##             -D hxmc.wasm-gc, GfxTest natively, each again from the store, linked, the same, run
## gfx-shader-check  packages/gfx's shader macro on Eval: shaders run on the CPU, the emitted
##             GLSL, WGSL, MSL and HLSL against packages/gfx/test/shader/, the programs it must
##             reject (packages/gfx/test/ShaderTest.hx; BLESS=1 rewrites the sources)
## 3d-check    packages/3d (docs/plans/3d.md): the math, the scene graph, the camera and the fixed-step
##             clock, the glTF reader on the sample scene, on Eval, natively and as wasm32-wasi
##             (packages/3d/test/SceneTest.hx, GltfTest.hx) and packages/physics (PhysicsTest.hx); input actions natively and as wasm32-wasi
##             (InputTest.hx); then the renderer's frames headless against
##             golden images (packages/3d/test/check.sh: RenderTest, Scenes.hx; Linux: Mesa)
## 3d-programs packages/3d's RenderTest for GFX_TARGET (any of the six: check.sh runs it, Windows's under Wine)
## 3d-sizes    what each feature of packages/3d adds to a program, natively and as wasm32-wasi
##             (packages/3d/test/size)
## 3d-web-check  packages/3d's frames on WebGPU and WebGL2 in headless Chromium (packages/3d/test/web.mjs),
##             Model.of's files fetched before main; then built with -D hxmc.wasm-gc
## view-check  packages/view on Eval, natively and in JavaScript (the port, node): signals, markup
##             (elements, attributes, whitespace, components, text runs, reactive values), the control
##             flow components, on two test renderers with boundaries between them, and the programs
##             the macro rejects (packages/view/test/ViewTest.hx)
## web-check   packages/web: the static renderer on Eval and natively (escaping, markers, islands:
##             packages/web/test/StaticTest.hx), then in headless Chromium (packages/web/test/web.mjs;
##             Playwright): the DOM renderer (DomTest.hx), the demo page (packages/web/examples)
##             hydrated without making nodes again, reactive after, a mismatch rendered again, a
##             JavaScript island calling a wasm module, gfx's cube as a wasm island loaded once in view;
##             the sizes of a small island's bundle and of the loader
## text-check  packages/text on Eval: the rasterizer, DejaVu Sans (metrics, cmap, kerning, outlines),
##             line layout, and a text sample through the atlas against packages/text/test/sample.png
## ui-check    packages/ui on Eval: the layout against Chromium's flexbox (layout-expected.json,
##             from packages/ui/test/layout-ref.mjs), text wrapping, events and focus (UiTest.hx);
##             markup rendered into nodes (MarkupTest.hx); the guide's examples (GuideTest.hx); the
##             widgets' examples rendered and their reference complete (WidgetExamplesTest.hx; the
##             reference written to bin/ui/widgets.json, tools/WidgetDocs.hx)
## theme-check  packages/theme on Eval: Tailwind's classes read as rules, Tw's rules made at compile time,
##             shadcn's sheet made, the classes it rejects (packages/theme/test/ThemeTest.hx)
## theme-fidelity-check  packages/theme's widgets drawn headless against shadcn's markup in Chromium
##             (packages/theme/test/ref, from ref.mjs; the cases known to differ reported, not failed)
## web-widgets  the DOM's widgets (packages/web, hxmc.web.widgets): the gallery driven in Chromium by pointer
##             and keys (packages/web/test/widgets.mjs), the sizes of the counter, form and gallery bundles
## theme-dom-check  the DOM's widgets (packages/web) under the theme's CSS in Chromium against the same
##             references (packages/theme/test/dom-fidelity.mjs)
## ui-layout-fuzz  random flex trees (SEED, COUNT; FEATURES=more: grids, absolute positions, auto margins, order and more) against Chromium's boxes (Playwright): differences to reduce into layout-cases.mjs
## ui-layout-reduce  one of them (CASE='fuzz 41-87', after ui-layout-fuzz) reduced: nodes and properties dropped while it still differs
## ui-programs  bin/ui/GFX_TARGET/{UiDrawTest,TodoTest,GalleryTest,StressTest,ClipboardTest,EmojiTest,BoxTest,WindowTest}[.exe], NativeTest (GTK 3, Win32, AppKit), TextInputTest (X11), LinuxAccessTest and AtspiProbe (AT-SPI), WinAccessTest (Windows): packages/ui's test programs (Linux: glibc mode)
## ui-draw-check  packages/ui's GPU renderer (hxmc.ui.draw): the sample UI headless against
##             packages/ui/test/draw.png (also in a window, under Xvfb), then the todo example (markup, signals, widgets) driven
##             through its Ui and drawn against todo.png (Linux: Mesa, DejaVu Sans; BLESS=1 rewrites them)
## ui-web-check  the todo example as wasm32-wasi in headless Chromium, on WebGPU and WebGL2, driven by
##             real pointer and keyboard events, against todo.png (packages/ui/test/web.mjs; DejaVu Sans);
##             the native form (native-web.mjs); native text editors in a drawn window (web-field.mjs);
##             each also built with -D hxmc.wasm-gc
## dev-check   the dev loop (docs/dev.md): hxmc.dev.Hot and a store written as a third-party library
##             across a reload (packages/os/test/HotTest.hx: natively and on Eval, a changed type reset),
##             view's signals keyed by component instance (packages/view/test/RefreshTest.hx), then
##             `hxmc dev` on ui's Counter: in headless Chromium, also as WasmGC (packages/os/test/dev/dev-web.mjs: an edit
##             keeps the count, a changed type resets it, a compile error shows in the overlay while the last
##             good build runs) and natively in a window (dev-native.mjs; Linux: under Xvfb); the compilation
##             server's builds through edits (one changing a module's API, one of markup using code it did not use before)
##             against fresh ones (dev-verify.mjs; small programs: server-verify.mjs)
## audio-programs  bin/audio/AUDIO_TARGET/{AudioTest,Tone}[.exe]: packages/os's audio test and example
## audio-check  packages/os's audio through each back end without speakers (packages/os/test/audio.sh):
##             ALSA's null and file devices (Linux), CoreAudio's generic output (macOS), WASAPI
##             (Windows; AUDIO_TARGET=windows-x86_64: under Wine, to an ALSA file); the samples
## site        bin/site: the website (site/: pages rendered by site/src with @hxmc/web, the packages'
##             examples built for the browser, the API read by the compiler; LIX_DIR's lix binaries
##             under tools/, BENCH_DATA's benchmark history under bench/)
## site-check  bin/site in headless browsers: every page rendered, islands hydrated, examples
##             drawing, the playground compiling, no console errors, no broken links
##             (site/tools/browser-test.mjs; Playwright; BROWSERS="chromium firefox webkit")
## examples-check  the packages' examples built, not run (no browser, GPU or display): the site's
##             gallery (site/src/Examples.hx) for wasm32-wasi as the site builds it, and those on a
##             canvas or playing a sound natively too, in parallel (hxmc/test/ExampleBuilds.hx)
## clean       remove the build outputs (keeps the hxmc checkout)
##
## Variables: HXMC, HXMC_REV, JOBS, NODE, HOST, GFX_TARGET, AUDIO_TARGET, ANDROID_TARGET, IOS_TARGET, LIX_DIR, BENCH_DATA.

headless: view-check text-check ui-check theme-check gfx-shader-check examples-check

# the os and gfx packages' sources (`-lib hxmc.gfx` once the launcher resolves packages/)
GFX_CP := -cp packages/os/src -cp packages/gfx/src -cp packages/gfx/examples -cp packages/gfx/test
# (Linux: the dynamic glibc mode, which loads the GPU drivers)
GFX_ARGS = $(if $(filter linux-%,$(GFX_TARGET)),-D hxmc.libc=glibc) -D hxmc.target=$(GFX_TARGET)
gfx-programs: $(TOOL) $(STD) $(HOST_RT)
	$(call hxmc,bin/gfx/$(GFX_TARGET)/GfxTest$(call EXE,$(GFX_TARGET)),$(GFX_CP) -main GfxTest $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/gfx/$(GFX_TARGET)/Triangle$(call EXE,$(GFX_TARGET)),$(GFX_CP) -main Triangle $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/gfx/$(GFX_TARGET)/Cube$(call EXE,$(GFX_TARGET)),$(GFX_CP) -main Cube $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/gfx/$(GFX_TARGET)/Instances$(call EXE,$(GFX_TARGET)),$(GFX_CP) -main Instances $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/gfx/$(GFX_TARGET)/Targets$(call EXE,$(GFX_TARGET)),$(GFX_CP) -main Targets $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/gfx/$(GFX_TARGET)/Mips$(call EXE,$(GFX_TARGET)),$(GFX_CP) -main Mips $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/gfx/$(GFX_TARGET)/Formats$(call EXE,$(GFX_TARGET)),$(GFX_CP) -main Formats $(HXMC_ARGS) $(GFX_ARGS))
# hxmc dev's host and three builds of DevHostTest as libraries it loads in turn (packages/gfx/test/host-dev.sh)
DEVHOST_ARGS := -D hxmc.dev -D hxmc.dev-host -D hxmc.shared -D hxmc.exports=hxmc_dev_run,hxmc_dev_state
DEVHOST_EXT = $(if $(filter windows-%,$(GFX_TARGET)),dll,$(if $(filter macos-%,$(GFX_TARGET)),dylib,so))
devhost-programs: $(TOOL) $(STD) $(HOST_RT)
	$(call hxmc,bin/gfx/$(GFX_TARGET)/dev/host$(call EXE,$(GFX_TARGET)),-cp packages/os/src -main hxmc.dev.DevHost $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/gfx/$(GFX_TARGET)/dev/DevHost1.$(DEVHOST_EXT),$(GFX_CP) -main DevHostTest $(HXMC_ARGS) $(GFX_ARGS) $(DEVHOST_ARGS) -D devhost_version=1 -D hxmc.dll-base=0x10000000)
	$(call hxmc,bin/gfx/$(GFX_TARGET)/dev/DevHost2.$(DEVHOST_EXT),$(GFX_CP) -main DevHostTest $(HXMC_ARGS) $(GFX_ARGS) $(DEVHOST_ARGS) -D devhost_version=2 -D hxmc.dll-base=0x30000000)
	$(call hxmc,bin/gfx/$(GFX_TARGET)/dev/DevHost3.$(DEVHOST_EXT),$(GFX_CP) -main DevHostTest $(HXMC_ARGS) $(GFX_ARGS) $(DEVHOST_ARGS) -D devhost_version=3 -D hxmc.dll-base=0x10000000)
gfx-check: gfx-programs
	sh packages/gfx/test/check.sh bin/gfx/$(GFX_TARGET)

# Android: APKs written by hxmc (hxmc/src/hxmc/android/Apk.hx), AndroidTest
# (packages/gfx/test/AndroidTest.hx), the cube example and AndroidNativeTest
# (packages/ui/test/AndroidNativeTest.hx: views, so classes.dex), AndroidMixTest
# (a GPU view among views) and AndroidTextTest (packages/os/test: text input
# in a drawn window)
android-programs: $(TOOL) $(STD) $(HOST_RT)
	$(call hxmc,bin/android/$(ANDROID_TARGET)/AndroidTest.apk,$(GFX_CP) -main AndroidTest $(HXMC_ARGS) -D hxmc.target=$(ANDROID_TARGET) -D hxmc.android-package=org.hxmc.gfxtest)
	$(call hxmc,bin/android/$(ANDROID_TARGET)/Cube.apk,$(GFX_CP) -main Cube $(HXMC_ARGS) -D hxmc.target=$(ANDROID_TARGET) -D hxmc.android-package=org.hxmc.cube)
	$(call hxmc,bin/android/$(ANDROID_TARGET)/AndroidNativeTest.apk,$(UI_CP) -main AndroidNativeTest $(HXMC_ARGS) -D hxmc.target=$(ANDROID_TARGET) -D hxmc.android-package=org.hxmc.nativetest)
	$(call hxmc,bin/android/$(ANDROID_TARGET)/AndroidMixTest.apk,$(UI_CP) -cp packages/gfx/examples -main AndroidMixTest $(HXMC_ARGS) -D hxmc.target=$(ANDROID_TARGET) -D hxmc.android-package=org.hxmc.mixtest)
	$(call hxmc,bin/android/$(ANDROID_TARGET)/AndroidTextTest.apk,-cp packages/os/src -cp packages/os/test -main AndroidTextTest $(HXMC_ARGS) -D hxmc.target=$(ANDROID_TARGET) -D hxmc.android-package=org.hxmc.texttest)
	$(call hxmc,bin/android/$(ANDROID_TARGET)/AndroidTouchTest.apk,$(UI_CP) -cp packages/os/test -main AndroidTouchTest $(HXMC_ARGS) -D hxmc.target=$(ANDROID_TARGET) -D hxmc.android-package=org.hxmc.touchtest)
# their structure without a device (hxmc/test/ApkCheck.hx: zip, manifest, ELF, signature, classes.dex; zipalign, aapt, apksigner, dexdump when there)
android-check: android-programs
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) -cp $(HXMC)/hxmc/test -cp $(HXMC)/haxe/test -cp $(HXMC)/hxmc/src --run ApkCheck $(foreach a,AndroidTest Cube AndroidNativeTest AndroidMixTest AndroidTextTest AndroidTouchTest,bin/android/$(ANDROID_TARGET)/$(a).apk)
# the Android tests on the device or emulator adb reaches (packages/gfx/test/android.sh, packages/ui/test/android-native.sh, android-mix.sh)
android-device-check: android-programs
	sh packages/gfx/test/android.sh bin/android/$(ANDROID_TARGET)/AndroidTest.apk bin/android/$(ANDROID_TARGET)
	sh packages/ui/test/android-native.sh bin/android/$(ANDROID_TARGET)/AndroidNativeTest.apk bin/android/$(ANDROID_TARGET)
	sh packages/ui/test/android-mix.sh bin/android/$(ANDROID_TARGET)/AndroidMixTest.apk bin/android/$(ANDROID_TARGET)/AndroidTextTest.apk bin/android/$(ANDROID_TARGET)
	sh packages/os/test/android-touch.sh bin/android/$(ANDROID_TARGET)/AndroidTouchTest.apk bin/android/$(ANDROID_TARGET)

# iOS: app bundles written by hxmc (hxmc/src/hxmc/ios/Bundle.hx), IosTest
# (packages/gfx/test/IosTest.hx) and the cube example (also as an .ipa);
# SimTap (packages/gfx/test/SimTap.hx), a macOS program that taps the
# simulator for ios.sh
# (hxmc dev's host: DevHostTest as the app and as dylibs of later versions, ios-dev.sh)
IOS_DEV := -D hxmc.dev -D hxmc.dev-host -D hxmc.exports=hxmc_dev_run,hxmc_dev_state
ios-programs: $(TOOL) $(STD) $(HOST_RT)
	$(call hxmc,bin/ios/$(IOS_TARGET)/IosTest.app,$(GFX_CP) -main IosTest $(HXMC_ARGS) -D hxmc.target=$(IOS_TARGET) -D hxmc.ios-bundle-id=org.hxmc.gfxtest)
	$(call hxmc,bin/ios/$(IOS_TARGET)/Cube.app,$(GFX_CP) -main Cube $(HXMC_ARGS) -D hxmc.target=$(IOS_TARGET) -D hxmc.ios-bundle-id=org.hxmc.cube)
	$(call hxmc,bin/ios/$(IOS_TARGET)/Cube.ipa,$(GFX_CP) -main Cube $(HXMC_ARGS) -D hxmc.target=$(IOS_TARGET) -D hxmc.ios-bundle-id=org.hxmc.cube)
	$(call hxmc,bin/ios/SimTap,-cp packages/os/src -cp packages/gfx/test -main SimTap $(HXMC_ARGS) -D hxmc.target=macos-arm64)
	$(call hxmc,bin/ios/$(IOS_TARGET)/DevHostTest.app,$(GFX_CP) -main DevHostTest $(HXMC_ARGS) -D hxmc.target=$(IOS_TARGET) -D hxmc.ios-bundle-id=org.hxmc.devhosttest $(IOS_DEV) -D devhost_version=1)
	$(call hxmc,bin/ios/$(IOS_TARGET)/DevHost2.dylib,$(GFX_CP) -main DevHostTest $(HXMC_ARGS) -D hxmc.target=$(IOS_TARGET) $(IOS_DEV) -D hxmc.shared -D devhost_version=2)
	$(call hxmc,bin/ios/$(IOS_TARGET)/DevHost3.dylib,$(GFX_CP) -main DevHostTest $(HXMC_ARGS) -D hxmc.target=$(IOS_TARGET) $(IOS_DEV) -D hxmc.shared -D devhost_version=3)
# their structure without a Mac (hxmc/test/IosCheck.hx: bundle, Info.plist, Mach-O, code signature; llvm-objdump when there)
ios-check: ios-programs
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) -cp $(HXMC)/hxmc/test -cp $(HXMC)/haxe/test -cp $(HXMC)/hxmc/src --run IosCheck $(foreach a,IosTest.app Cube.app Cube.ipa,bin/ios/$(IOS_TARGET)/$(a))
# IosTest on an iPhone simulator (packages/gfx/test/ios.sh: a Mac with Xcode)
ios-sim-check:
	$(MAKE) --no-print-directory ios-programs IOS_TARGET=ios-sim-arm64
	sh packages/gfx/test/ios.sh bin/ios/ios-sim-arm64/IosTest.app bin/ios/ios-sim-arm64 bin/ios/SimTap
	sh packages/gfx/test/ios-dev.sh bin/ios/ios-sim-arm64 bin/ios/ios-sim-arm64

gfx-web-check: $(TOOL) $(STD)
	$(call hxmc,bin/gfx/WebTest.wasm,$(GFX_CP) -main WebTest $(HXMC_ARGS) -D hxmc.target=wasm32-wasi)
	$(NODE) packages/gfx/test/web.mjs bin/gfx/WebTest.wasm bin/gfx
	$(call hxmc,bin/gfx/gc/WebTest.wasm,$(GFX_CP) -main WebTest $(HXMC_ARGS) -D hxmc.target=wasm32-wasi -D hxmc.wasm-gc)
	$(NODE) packages/gfx/test/web.mjs bin/gfx/gc/WebTest.wasm bin/gfx/gc

# the module cache across a WasmGC and a native build on one store
# (hxmc/src/hxmc/ModuleCache.hx: a module restored with the variant typed
# for the build's defines also where only its dependencies read them, as
# GLBackend, which inlines BytesPtr's -D hxmc.wasm-gc functions and calls
# GL's functions made for the target; one a restored module's HXB names
# checked before it is decoded): WebTest with -D hxmc.wasm-gc, GfxTest
# natively, then each again from the store (restored whole), then each with
# a define nothing reads (another signature: no variant typed with the
# build's defines, the modules that depend on the target typed again); each
# linked, the same as the first of its kind, then run (web.mjs's triangle,
# check.sh's headless triangle)
GFX_CACHE_DIR := bin/gfx/cache
gfx-cache-check: $(TOOL) $(STD) $(HOST_RT)
	rm -rf $(GFX_CACHE_DIR); mkdir -p $(GFX_CACHE_DIR)
	@set -e; ulimit -s unlimited 2>/dev/null || true; export HXMC_CACHE=$(abspath $(GFX_CACHE_DIR))/store HXMC_STATS=1; \
	for i in 1 2 3 4 5 6; do \
		case $$i in 1|3|5) o=$(GFX_CACHE_DIR)/WebTest$$i.wasm; a="-main WebTest -D hxmc.target=wasm32-wasi -D hxmc.wasm-gc";; \
		*) o=$(GFX_CACHE_DIR)/GfxTest$$i$(call EXE,$(GFX_TARGET)); a="-main GfxTest $(GFX_ARGS)";; esac; \
		case $$i in 5|6) a="$$a -D gfx_cache_check";; esac; \
		echo "$(TOOL) $$o $$a"; \
		$(TOOL) $$o $(GFX_CP) $(HXMC_ARGS) $$a > $$o.log 2>&1 || { cat $$o.log; exit 1; }; \
		grep "module cache: .* checked" $$o.log; \
	done; \
	for l in WebTest3.wasm GfxTest4$(call EXE,$(GFX_TARGET)); do grep -q " 0 typed from source," $(GFX_CACHE_DIR)/$$l.log || { echo "gfx-cache-check: $$l not restored whole"; exit 1; }; done
	for i in 3 5; do cmp $(GFX_CACHE_DIR)/WebTest1.wasm $(GFX_CACHE_DIR)/WebTest$$i.wasm || exit 1; done
	for i in 4 6; do cmp $(GFX_CACHE_DIR)/GfxTest2$(call EXE,$(GFX_TARGET)) $(GFX_CACHE_DIR)/GfxTest$$i$(call EXE,$(GFX_TARGET)) || exit 1; done
	SCENES=triangle $(NODE) packages/gfx/test/web.mjs $(GFX_CACHE_DIR)/WebTest3.wasm $(GFX_CACHE_DIR)
	LIBGL_ALWAYS_SOFTWARE=1 env -u DISPLAY $(GFX_CACHE_DIR)/GfxTest4 headless triangle packages/gfx/test/triangle.png $(GFX_CACHE_DIR)/triangle-headless.png

# packages/os's audio (Linux: the glibc mode, which loads libasound.so.2)
OS_CP := -cp packages/os/src -cp packages/os/examples -cp packages/os/test
AUDIO_ARGS = $(if $(filter linux-%,$(AUDIO_TARGET)),-D hxmc.libc=glibc) -D hxmc.target=$(AUDIO_TARGET)
audio-programs: $(TOOL) $(STD) $(HOST_RT)
	$(call hxmc,bin/audio/$(AUDIO_TARGET)/AudioTest$(call EXE,$(AUDIO_TARGET)),$(OS_CP) -main AudioTest $(HXMC_ARGS) $(AUDIO_ARGS))
	$(call hxmc,bin/audio/$(AUDIO_TARGET)/Tone$(call EXE,$(AUDIO_TARGET)),$(OS_CP) -main Tone $(HXMC_ARGS) $(AUDIO_ARGS))
audio-check: audio-programs
	sh packages/os/test/audio.sh bin/audio/$(AUDIO_TARGET)

# packages/os's touch gesture (TouchDrag: Android's and iOS's), natively on this host
touch-check: $(TOOL) $(STD) $(HOST_RT)
	$(call hxmc,bin/os/TouchDragTest,$(OS_CP) -main TouchDragTest $(HXMC_ARGS) $(if $(filter linux-%,$(HOST)),-D hxmc.libc=glibc))
	bin/os/TouchDragTest

audio-web-check: $(TOOL) $(STD)
	$(call hxmc,bin/audio/AudioTest.wasm,$(OS_CP) -main AudioTest $(HXMC_ARGS) -D hxmc.target=wasm32-wasi)
	$(NODE) packages/os/test/web.mjs bin/audio/AudioTest.wasm

gfx-shader-check: $(TOOL)
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) -cp packages/gfx/src -cp packages/gfx/examples -cp packages/gfx/test --run ShaderTest $(TOOL) $(if $(BLESS),--bless)

# packages/3d (docs/plans/3d.md) on gfx: the unit tests on Eval, natively and as wasm32-wasi, then
# the renderer's frames against golden images, natively (GFX_TARGET) and in Chromium
SCENE_CP := $(GFX_CP) -cp packages/3d/src -cp packages/3d/examples -cp packages/3d/test -cp packages/physics/src -cp packages/physics/examples -cp packages/physics/test \
	-cp packages/text/src -cp packages/ui/src
SCENE_UI_CP := -cp packages/os/src -cp packages/gfx/src -cp packages/3d/src -cp packages/view/src -cp packages/3d-ui/src -cp packages/3d-ui/test \
	-D hxmc.view.renderer=hxmc.scene.view.SceneRenderer
# RenderTest for GFX_TARGET (any of the six; CI runs the ARM64 and Windows ones on their machines)
3d-programs: $(TOOL) $(STD) $(HOST_RT)
	@mkdir -p bin/3d
	@# (the asset step: the samples packed for the packed scenes)
	ulimit -s unlimited 2>/dev/null || true; for m in sample skinned normals morph; do $(TOOL) $(SCENE_CP) --run hxmc.scene.gltf.Pack packages/3d/examples/$$m.glb bin/3d/$$m.hxm3d || exit 1; done
	$(call hxmc,bin/3d/$(GFX_TARGET)/RenderTest$(call EXE,$(GFX_TARGET)),$(SCENE_CP) -main RenderTest $(HXMC_ARGS) $(GFX_ARGS))
3d-check: $(TOOL) $(STD) $(HOST_RT)
	@set -e; ulimit -s unlimited 2>/dev/null || true; for t in SceneTest GltfTest PhysicsTest; do $(TOOL) $(SCENE_CP) --run $$t; done
	$(call hxmc,bin/3d/SceneTest,$(SCENE_CP) -main SceneTest $(HXMC_ARGS))
	$(call hxmc,bin/3d/GltfTest,$(SCENE_CP) -main GltfTest $(HXMC_ARGS))
	$(call hxmc,bin/3d/PhysicsTest,$(SCENE_CP) -main PhysicsTest $(HXMC_ARGS))
	bin/3d/SceneTest && bin/3d/GltfTest && bin/3d/PhysicsTest
	$(call hxmc,bin/3d/SceneTest.wasm,$(SCENE_CP) -main SceneTest $(HXMC_ARGS) -D hxmc.target=wasm32-wasi)
	$(call hxmc,bin/3d/GltfTest.wasm,$(SCENE_CP) -main GltfTest $(HXMC_ARGS) -D hxmc.target=wasm32-wasi)
	$(call hxmc,bin/3d/PhysicsTest.wasm,$(SCENE_CP) -main PhysicsTest $(HXMC_ARGS) -D hxmc.target=wasm32-wasi)
	$(WASI) bin/3d/SceneTest.wasm && $(WASI) bin/3d/GltfTest.wasm && $(WASI) bin/3d/PhysicsTest.wasm
	$(MAKE) --no-print-directory 3d-programs
	$(call hxmc,bin/3d/$(GFX_TARGET)/GltfViewer$(call EXE,$(GFX_TARGET)),$(SCENE_CP) -main GltfViewer $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/3d/$(GFX_TARGET)/Orbits$(call EXE,$(GFX_TARGET)),$(SCENE_CP) -main Orbits $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/3d/$(GFX_TARGET)/Showroom$(call EXE,$(GFX_TARGET)),$(SCENE_CP) -main Showroom $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/3d/$(GFX_TARGET)/Falling$(call EXE,$(GFX_TARGET)),$(SCENE_CP) -main Falling $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/3d/$(GFX_TARGET)/Walker$(call EXE,$(GFX_TARGET)),$(SCENE_CP) -main Walker $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/3d/$(GFX_TARGET)/Chains$(call EXE,$(GFX_TARGET)),$(SCENE_CP) -main Chains $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/3d/$(GFX_TARGET)/InputTest$(call EXE,$(GFX_TARGET)),$(SCENE_CP) -main InputTest $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/3d/InputTest.wasm,$(SCENE_CP) -main InputTest $(HXMC_ARGS) -D hxmc.target=wasm32-wasi)
	bin/3d/$(GFX_TARGET)/InputTest$(call EXE,$(GFX_TARGET)) && $(WASI) bin/3d/InputTest.wasm
	@# (@hxmc/3d-ui: view's markup on the scene graph; natively: its meshes import gfx, which node lacks)
	$(call hxmc,bin/3d/$(GFX_TARGET)/SceneUiTest$(call EXE,$(GFX_TARGET)),$(SCENE_UI_CP) -main SceneUiTest $(HXMC_ARGS) $(GFX_ARGS))
	bin/3d/$(GFX_TARGET)/SceneUiTest$(call EXE,$(GFX_TARGET))
	sh packages/3d/test/check.sh bin/3d/$(GFX_TARGET)
	@# (Model.of's files beside the executable, -D hxmc.scene.embed=0)
	$(call hxmc,bin/3d/files/RenderTest$(call EXE,$(GFX_TARGET)),$(SCENE_CP) -main RenderTest $(HXMC_ARGS) $(GFX_ARGS) -D hxmc.scene.embed=0 -D hxmc.scene.out=bin/3d/files/RenderTest$(call EXE,$(GFX_TARGET)))
	test -f bin/3d/files/assets/sample.glb && test -f bin/3d/files/RenderTest$(call EXE,$(GFX_TARGET)).assets.json
	cd bin/3d && LIBGL_ALWAYS_SOFTWARE=1 HXMC_GFX_SOFTWARE=1 env -u DISPLAY files/RenderTest$(call EXE,$(GFX_TARGET)) skin ../../packages/3d/test/skin.png files/skin.png
	@# (Model.of: a name the file does not have is a compile error)
	ulimit -s unlimited 2>/dev/null || true; ! $(TOOL) bin/3d/ModelTypo $(SCENE_CP) -cp packages/3d/test/reject -main ModelTypo $(HXMC_ARGS) > bin/3d/ModelTypo.log 2>&1
	grep -q "has no field bal" bin/3d/ModelTypo.log
# what each feature of packages/3d adds to a program (packages/3d/test/size: Linux x86-64, wasm32-wasi)
3d-sizes: $(TOOL) $(STD) $(HOST_RT)
	@mkdir -p bin/3d
	ulimit -s unlimited 2>/dev/null || true; for m in sample skinned normals morph; do $(TOOL) $(SCENE_CP) --run hxmc.scene.gltf.Pack packages/3d/examples/$$m.glb bin/3d/$$m.hxm3d || exit 1; done
	ulimit -s unlimited 2>/dev/null || true; sh packages/3d/test/size/sizes.sh $(TOOL) bin/3d/size -cp packages/os/src -cp packages/gfx/src -cp packages/3d/src -cp packages/3d/examples -cp packages/3d/test/size $(HXMC_ARGS)
3d-web-check: $(TOOL) $(STD)
	@mkdir -p bin/3d
	ulimit -s unlimited 2>/dev/null || true; for m in sample skinned normals morph; do $(TOOL) $(SCENE_CP) --run hxmc.scene.gltf.Pack packages/3d/examples/$$m.glb bin/3d/$$m.hxm3d || exit 1; done
	@# (Model.of's files beside the module, -D hxmc.scene.embed=0: fetched by browser.mjs before main)
	rm -rf bin/3d/assets
	$(call hxmc,bin/3d/SceneWebTest.wasm,$(SCENE_CP) -main SceneWebTest $(HXMC_ARGS) -D hxmc.target=wasm32-wasi -D hxmc.scene.embed=0 -D hxmc.scene.out=bin/3d/SceneWebTest.wasm)
	$(NODE) packages/3d/test/web.mjs bin/3d/SceneWebTest.wasm bin/3d
	@# (and as WasmGC, the files built in)
	$(call hxmc,bin/3d/gc/SceneWebTest.wasm,$(SCENE_CP) -main SceneWebTest $(HXMC_ARGS) -D hxmc.target=wasm32-wasi -D hxmc.wasm-gc)
	$(NODE) packages/3d/test/web.mjs bin/3d/gc/SceneWebTest.wasm bin/3d/gc

# (two renderers: TestRenderer, OtherRenderer; JavaScript compiled by the port)
VIEW_CP := -cp packages/view/src -cp packages/view/test -D hxmc.view.renderer=TestRenderer -D hxmc.view.renderer.other=OtherRenderer
view-check: $(TOOL) $(STD) $(HOST_RT) $(PORT_BIN)
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) $(VIEW_CP) --run ViewTest $(TOOL)
	$(call hxmc,bin/view/ViewTest,$(VIEW_CP) -main ViewTest $(HXMC_ARGS))
	bin/view/ViewTest
	ulimit -s unlimited 2>/dev/null || true; $(PORT_BIN) $(VIEW_CP) -main ViewTest -js bin/view/ViewTest.js
	$(NODE) bin/view/ViewTest.js

# (packages/web: the static renderer on Eval and natively; the demo page rendered on Eval, its
# islands compiled to JavaScript by the port, lab.wasm and gfx's cube for wasm32-wasi)
WEB_CP := -cp packages/view/src -cp packages/web/src -cp packages/web/test -cp packages/web/examples
WEB_STATIC := $(WEB_CP) -D hxmc.view.renderer.html=hxmc.web.StaticRenderer
WEB_DOM := $(WEB_CP) -D hxmc.view.renderer.dom=hxmc.web.DomRenderer
web-check: $(TOOL) $(STD) $(HOST_RT) $(PORT_BIN)
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) $(WEB_STATIC) --run StaticTest
	$(call hxmc,bin/web/StaticTest,$(WEB_STATIC) -main StaticTest $(HXMC_ARGS))
	bin/web/StaticTest
	rm -rf bin/web/demo
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) $(WEB_STATIC) --run DemoPage bin/web/demo
	$(PORT_BIN) $(WEB_DOM) -D hxmc.view.renderer.html=hxmc.web.StaticRenderer -main DomTest -debug -js bin/web/domtest.js
	$(PORT_BIN) $(WEB_DOM) -main DemoBundle -dce full -debug -js bin/web/demo/islands.js
	$(PORT_BIN) $(WEB_DOM) -main Counter -dce full -D js-es=6 -D analyzer-optimize -js bin/web/demo/counter.js
	$(call hxmc,bin/web/demo/lab.wasm,-cp packages/web/src -cp packages/web/examples -main Lab $(HXMC_ARGS) -D hxmc.target=wasm32-wasi)
	$(call hxmc,bin/web/demo/cube.wasm,$(GFX_CP) -main Cube $(HXMC_ARGS) -D hxmc.target=wasm32-wasi)
	rm -rf bin/web/demo/*.hxmc bin/web/demo/*.log
	$(NODE) packages/web/test/web.mjs bin/web

# (the DOM's widgets: the theme's CSS on Eval, the examples compiled to JavaScript by the port, driven in Chromium)
web-widgets: $(TOOL) $(PORT_BIN)
	@mkdir -p bin/web/widgets
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) -cp packages/ui/tools -cp packages/web/test --run WidgetParity packages/ui/src/hxmc/ui/widgets/Widgets.hx packages/web/src/hxmc/web/widgets/Widgets.hx
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) -cp packages/ui/src -cp packages/theme/src --run hxmc.theme.Css shadcn.json bin/web/widgets/shadcn.css
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) -cp packages/ui/src -cp packages/theme/src --run hxmc.theme.Css shadcn.json bin/web/widgets/shadcn-scoped.css .hxmc
	for m in counter:WidgetCounter form:WidgetForm gallery:WidgetGallery; do \
		ulimit -s unlimited 2>/dev/null || true; $(PORT_BIN) $(DOM_CP) -cp packages/web/examples -main $${m#*:} -dce full -D js-es=6 -D analyzer-optimize -js bin/web/widgets/$${m%%:*}.js || exit 1; \
		printf '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>%s</title><link rel="stylesheet" href="shadcn.css"></head><body><script src="%s.js"></script></body></html>\n' $${m#*:} $${m%%:*} > bin/web/widgets/$${m%%:*}.html; \
	done
	$(NODE) packages/web/test/widgets.mjs bin/web/widgets

text-check: $(TOOL)
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) -cp packages/text/src -cp packages/text/test -cp packages/gfx/test --run TextTest $(if $(BLESS),--bless)

# (hxmc.view and its renderer for hxmc.ui, as -lib hxmc.ui sets it: packages/ui/extraParams.hxml)
UI_VIEW := -cp packages/view/src -D hxmc.view.renderer.ui=hxmc.ui.view.NodeRenderer
ui-check: $(TOOL)
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) -cp packages/text/src -cp packages/ui/src -cp packages/ui/test --run UiTest
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) $(UI_VIEW) -cp packages/text/src -cp packages/ui/src -cp packages/ui/test -cp packages/ui/examples --run MarkupTest
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) $(UI_VIEW) -cp packages/text/src -cp packages/ui/src -cp packages/ui/test -cp packages/ui/examples --run GuideTest
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) $(UI_VIEW) -cp packages/text/src -cp packages/ui/src -cp packages/theme/src -cp packages/ui/test -cp packages/ui/tools -cp packages/ui/examples/widgets --run WidgetExamplesTest
	mkdir -p bin/ui; ulimit -s unlimited 2>/dev/null || true; $(TOOL) -cp packages/ui/tools --run WidgetDocs packages/ui/src/hxmc/ui/widgets/Widgets.hx packages/ui/examples/widgets bin/ui/widgets.json

# random flex trees against Chromium (Playwright): a tool, not a lane
ui-layout-fuzz: $(TOOL)
	node packages/ui/test/layout-fuzz.mjs $(or $(SEED),1) $(or $(COUNT),200) bin/ui/fuzz $(FEATURES)
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) -cp packages/text/src -cp packages/ui/src -cp packages/ui/test --run LayoutFuzz bin/ui/fuzz

ui-layout-reduce: $(TOOL)
	node packages/ui/test/layout-reduce.mjs bin/ui/fuzz/layout-cases.json '$(CASE)' bin/ui/reduce

theme-check: $(TOOL)
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) -cp packages/ui/src -cp packages/theme/src -cp packages/theme/test --run ThemeTest $(TOOL)
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) -cp packages/ui/src -cp packages/theme/src -cp packages/theme/test --run CssTest

# (the theme's CSS on Eval, the DOM's widgets compiled to JavaScript by the port, in Chromium)
DOM_CP := -cp packages/view/src -cp packages/web/src -cp packages/text/src -cp packages/ui/src -D hxmc.view.renderer.dom=hxmc.web.DomRenderer
theme-dom-check: $(TOOL) $(PORT_BIN)
	@mkdir -p bin/theme/dom
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) -cp packages/ui/src -cp packages/theme/src --run hxmc.theme.Css shadcn.json bin/theme/dom/shadcn.css
	ulimit -s unlimited 2>/dev/null || true; $(PORT_BIN) $(DOM_CP) -cp packages/theme/src -cp packages/theme/test -main DomFidelity -dce full -D js-es=6 -js bin/theme/dom/domfidelity.js
	$(NODE) packages/theme/test/dom-fidelity.mjs bin/theme/dom bin/theme/dom/out

theme-fidelity-check: $(TOOL) $(STD) $(HOST_RT)
	$(call hxmc,bin/theme/$(GFX_TARGET)/FidelityTest$(call EXE,$(GFX_TARGET)),$(UI_CP) -cp packages/theme/test -main FidelityTest $(HXMC_ARGS) $(GFX_ARGS))
	mkdir -p bin/theme/out && LIBGL_ALWAYS_SOFTWARE=1 env -u DISPLAY bin/theme/$(GFX_TARGET)/FidelityTest packages/theme/test/ref bin/theme/out

UI_CP := -cp packages/os/src -cp packages/gfx/src -cp packages/gfx/test -cp packages/text/src $(UI_VIEW) -cp packages/ui/src -cp packages/theme/src -cp packages/ui/test -cp packages/ui/examples
ui-programs: $(TOOL) $(STD) $(HOST_RT)
	$(call hxmc,bin/ui/$(GFX_TARGET)/UiDrawTest$(call EXE,$(GFX_TARGET)),$(UI_CP) -main UiDrawTest $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/ui/$(GFX_TARGET)/TodoTest$(call EXE,$(GFX_TARGET)),$(UI_CP) -main TodoTest $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/ui/$(GFX_TARGET)/GalleryTest$(call EXE,$(GFX_TARGET)),$(UI_CP) -main GalleryTest $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/ui/$(GFX_TARGET)/StressTest$(call EXE,$(GFX_TARGET)),$(UI_CP) -main StressTest $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/ui/$(GFX_TARGET)/ClipboardTest$(call EXE,$(GFX_TARGET)),$(UI_CP) -main ClipboardTest $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/ui/$(GFX_TARGET)/NativeTest$(call EXE,$(GFX_TARGET)),$(UI_CP) -main NativeTest $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/ui/$(GFX_TARGET)/EmojiTest$(call EXE,$(GFX_TARGET)),$(UI_CP) -main EmojiTest $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/ui/$(GFX_TARGET)/BoxTest$(call EXE,$(GFX_TARGET)),$(UI_CP) -main BoxTest $(HXMC_ARGS) $(GFX_ARGS))
	$(call hxmc,bin/ui/$(GFX_TARGET)/WindowTest$(call EXE,$(GFX_TARGET)),$(UI_CP) -main WindowTest $(HXMC_ARGS) $(GFX_ARGS))
	$(if $(filter linux-%,$(GFX_TARGET)),$(call hxmc,bin/ui/$(GFX_TARGET)/TextInputTest,$(UI_CP) -main TextInputTest $(HXMC_ARGS) $(GFX_ARGS)))
	$(if $(filter linux-%,$(GFX_TARGET)),$(call hxmc,bin/ui/$(GFX_TARGET)/LinuxAccessTest,$(UI_CP) -main LinuxAccessTest $(HXMC_ARGS) $(GFX_ARGS)))
	$(if $(filter linux-%,$(GFX_TARGET)),$(call hxmc,bin/ui/$(GFX_TARGET)/AtspiProbe,$(UI_CP) -main AtspiProbe $(HXMC_ARGS) $(GFX_ARGS)))
	$(if $(filter windows-%,$(GFX_TARGET)),$(call hxmc,bin/ui/$(GFX_TARGET)/WinAccessTest.exe,$(UI_CP) -main WinAccessTest $(HXMC_ARGS) $(GFX_ARGS)))
ui-draw-check: ui-programs
	LIBGL_ALWAYS_SOFTWARE=1 env -u DISPLAY bin/ui/$(GFX_TARGET)/UiDrawTest packages/ui/test/draw.png bin/ui/$(GFX_TARGET)/draw.png $(if $(BLESS),--bless)
	LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 640x480x24" bin/ui/$(GFX_TARGET)/UiDrawTest packages/ui/test/draw.png bin/ui/$(GFX_TARGET)/window.png --window
	LIBGL_ALWAYS_SOFTWARE=1 env -u DISPLAY bin/ui/$(GFX_TARGET)/TodoTest packages/ui/test/todo.png bin/ui/$(GFX_TARGET)/todo.png $(if $(BLESS),--bless)
	LIBGL_ALWAYS_SOFTWARE=1 env -u DISPLAY bin/ui/$(GFX_TARGET)/GalleryTest packages/ui/test/gallery.png bin/ui/$(GFX_TARGET)/gallery.png $(if $(BLESS),--bless)
	LIBGL_ALWAYS_SOFTWARE=1 env -u DISPLAY bin/ui/$(GFX_TARGET)/GalleryTest packages/ui/test/gallery-dark.png bin/ui/$(GFX_TARGET)/gallery-dark.png --dark $(if $(BLESS),--bless)
	LIBGL_ALWAYS_SOFTWARE=1 env -u DISPLAY bin/ui/$(GFX_TARGET)/GalleryTest packages/ui/test/gallery-rtl.png bin/ui/$(GFX_TARGET)/gallery-rtl.png --rtl $(if $(BLESS),--bless)
	LIBGL_ALWAYS_SOFTWARE=1 env -u DISPLAY bin/ui/$(GFX_TARGET)/GalleryTest packages/ui/test/gallery-unstyled.png bin/ui/$(GFX_TARGET)/gallery-unstyled.png --unstyled $(if $(BLESS),--bless)
	LIBGL_ALWAYS_SOFTWARE=1 env -u DISPLAY bin/ui/$(GFX_TARGET)/StressTest
	LIBGL_ALWAYS_SOFTWARE=1 env -u DISPLAY bin/ui/$(GFX_TARGET)/EmojiTest packages/ui/test/emoji.png bin/ui/$(GFX_TARGET)/emoji.png
	LIBGL_ALWAYS_SOFTWARE=1 env -u DISPLAY bin/ui/$(GFX_TARGET)/BoxTest packages/ui/test/boxes.png bin/ui/$(GFX_TARGET)/boxes.png
	xvfb-run -a -s "-screen 0 640x480x24" bin/ui/$(GFX_TARGET)/ClipboardTest
	xvfb-run -a -s "-screen 0 640x480x24" bin/ui/$(GFX_TARGET)/TextInputTest
	xvfb-run -a -s "-screen 0 640x480x24" bin/ui/$(GFX_TARGET)/WindowTest
	# (AT-SPI: the window's tree read by another process through libatspi, in a D-Bus session)
	LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 640x480x24" dbus-run-session -- sh -c 'bin/ui/$(GFX_TARGET)/LinuxAccessTest & p=$$!; bin/ui/$(GFX_TARGET)/AtspiProbe; s=$$?; wait $$p && exit $$s'
	xvfb-run -a -s "-screen 0 640x480x24" bin/ui/$(GFX_TARGET)/NativeTest bin/ui/$(GFX_TARGET)/native.png

ui-web-check: $(TOOL) $(STD)
	$(call hxmc,bin/ui/WebTodo.wasm,$(UI_CP) -main WebTodo $(HXMC_ARGS) -D hxmc.target=wasm32-wasi)
	$(NODE) packages/ui/test/web.mjs bin/ui/WebTodo.wasm bin/ui
	$(call hxmc,bin/ui/NativeForm.wasm,$(UI_CP) -main NativeForm $(HXMC_ARGS) -D hxmc.target=wasm32-wasi)
	$(NODE) packages/ui/test/native-web.mjs bin/ui/NativeForm.wasm bin/ui
	$(call hxmc,bin/ui/WebField.wasm,$(UI_CP) -main WebField $(HXMC_ARGS) -D hxmc.target=wasm32-wasi)
	$(NODE) packages/ui/test/web-field.mjs bin/ui/WebField.wasm
	$(call hxmc,bin/ui/gc/WebTodo.wasm,$(UI_CP) -main WebTodo $(HXMC_ARGS) -D hxmc.target=wasm32-wasi -D hxmc.wasm-gc)
	$(NODE) packages/ui/test/web.mjs bin/ui/gc/WebTodo.wasm bin/ui/gc
	$(call hxmc,bin/ui/gc/NativeForm.wasm,$(UI_CP) -main NativeForm $(HXMC_ARGS) -D hxmc.target=wasm32-wasi -D hxmc.wasm-gc)
	$(NODE) packages/ui/test/native-web.mjs bin/ui/gc/NativeForm.wasm bin/ui/gc
	$(call hxmc,bin/ui/gc/WebField.wasm,$(UI_CP) -main WebField $(HXMC_ARGS) -D hxmc.target=wasm32-wasi -D hxmc.wasm-gc)
	$(NODE) packages/ui/test/web-field.mjs bin/ui/gc/WebField.wasm
# (the dev loop: each program run twice, the second from the first's snapshot)
DEV_OS_CP := -cp packages/os/src -cp packages/os/test
DEV_VIEW_CP := -cp packages/os/src -cp packages/view/src -cp packages/view/test -D hxmc.view.renderer=TestRenderer
dev-check: $(TOOL) $(STD) $(HOST_RT)
	$(call hxmc,bin/dev/HotTest,$(DEV_OS_CP) -main HotTest $(HXMC_ARGS) -D hxmc.dev)
	$(call hxmc,bin/dev/HotTestChanged,$(DEV_OS_CP) -main HotTest $(HXMC_ARGS) -D hxmc.dev -D hot_changed)
	bin/dev/HotTest save bin/dev/hot.snapshot
	HXMC_DEV_SNAPSHOT=bin/dev/hot.snapshot bin/dev/HotTest restore -
	HXMC_DEV_SNAPSHOT=bin/dev/hot.snapshot bin/dev/HotTestChanged restore - > bin/dev/changed.log 2>&1 || { cat bin/dev/changed.log; exit 1; }
	cat bin/dev/changed.log; grep -q "changed reset: its type changed" bin/dev/changed.log
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) $(DEV_OS_CP) -D hxmc.dev --run HotTest save bin/dev/hot-eval.snapshot
	ulimit -s unlimited 2>/dev/null || true; HXMC_DEV_SNAPSHOT=bin/dev/hot-eval.snapshot $(TOOL) $(DEV_OS_CP) -D hxmc.dev --run HotTest restore -
	$(call hxmc,bin/dev/RefreshTest,$(DEV_VIEW_CP) -main RefreshTest $(HXMC_ARGS) -D hxmc.dev)
	bin/dev/RefreshTest save bin/dev/refresh.snapshot
	HXMC_DEV_SNAPSHOT=bin/dev/refresh.snapshot bin/dev/RefreshTest restore -
	$(call hxmc,bin/dev/RefreshTestChanged,$(DEV_VIEW_CP) -main RefreshTest $(HXMC_ARGS) -D hxmc.dev -D refresh_changed)
	HXMC_DEV_SNAPSHOT=bin/dev/refresh.snapshot bin/dev/RefreshTestChanged restore - > bin/dev/refresh-changed.log 2>&1 || { cat bin/dev/refresh-changed.log; exit 1; }
	cat bin/dev/refresh-changed.log; grep -q "main.tuned reset: its initial value changed" bin/dev/refresh-changed.log
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) $(DEV_VIEW_CP) -D hxmc.dev --run RefreshTest save bin/dev/refresh-eval.snapshot
	ulimit -s unlimited 2>/dev/null || true; HXMC_DEV_SNAPSHOT=bin/dev/refresh-eval.snapshot $(TOOL) $(DEV_VIEW_CP) -D hxmc.dev --run RefreshTest restore -
	ulimit -s unlimited 2>/dev/null || true; $(NODE) packages/os/test/dev/dev-web.mjs $(TOOL) bin/dev/web
	ulimit -s unlimited 2>/dev/null || true; $(NODE) packages/os/test/dev/dev-web.mjs $(TOOL) bin/dev/web-gc --wasm-gc
	ulimit -s unlimited 2>/dev/null || true; $(if $(filter linux-%,$(HOST)),xvfb-run -a -s "-screen 0 640x480x24") $(NODE) packages/os/test/dev/dev-native.mjs $(TOOL) bin/dev/native
	ulimit -s unlimited 2>/dev/null || true; $(NODE) packages/os/test/dev/server-verify.mjs $(TOOL)
	ulimit -s unlimited 2>/dev/null || true; $(NODE) packages/os/test/dev/dev-verify.mjs $(TOOL) Counter web


# --- The website (site/) ---

# The pages, rendered by site/src (on the tool's Eval, with @hxmc/web's static
# renderer), which also builds each package example for wasm32-wasi (legacy
# exception handling: every browser with WebGPU has it, those with WebGL2
# since 2021), reads the packages' API with the tool, measures the hxmc
# page's sizes and build times, and copies the packages' browser modules;
# then the playground's compiler (bin/wasm), the pages' JavaScript
# (site/client and site/islands, compiled by the port: site/build.hxml), the
# std subset the playground's compiler reads (site/tools/MkBundle.hx), the
# measured results (site/data), lix under tools/ (LIX_DIR), the benchmark
# history (BENCH_DATA) and the build facts. Needs the DejaVu Sans fonts (the
# ui examples'; fonts-dejavu-core). The site's build in the addresses of the
# files its pages fetch (Version.hx, Site.asset): a deploy reaches browsers at once.
mb = awk '{printf "%.1f MB", $$1 / 1048576}'
SITE_VERSION ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
SITE_CP := -cp packages/view/src -cp packages/web/src -cp packages/web/examples -cp site/islands -cp site/src -cp packages/ui/tools -D hxmc.view.renderer.html=hxmc.web.StaticRenderer
site: wasm $(TOOL) $(STD) $(HOST_RT) $(PORT_BIN)
	rm -rf bin/site && mkdir -p bin/site
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) $(SITE_CP) --run Site --out bin/site --build bin/site-build --tool $(TOOL) --version $(SITE_VERSION) --jobs $(JOBS)
	cp bin/wasm/hih.wasm bin/wasm/hih-legacy.wasm bin/site/
	$(PORT_BIN) -D site_version=$(SITE_VERSION) site/build.hxml
	$(RUN) -cp site/tools --run MkBundle $(HAXE_STD_PATH) bin/site/std.bundle
	cp site/data/*.json bin/site/
	cp -r site/playground bin/site/playground
	if [ -n "$(LIX_DIR)" ]; then mkdir -p bin/site/tools && cp $(LIX_DIR)/lix-* bin/site/tools/; fi
	if [ -n "$(BENCH_DATA)" ] && [ -f "$(BENCH_DATA)/history.json" ]; then mkdir -p bin/site/bench && cp $(BENCH_DATA)/history.json bin/site/bench/ && { cp $(BENCH_DATA)/latest.json bin/site/bench/ 2>/dev/null || true; }; fi
	if [ -n "$(BENCH_DATA)" ] && [ -f "$(BENCH_DATA)/targets.json" ]; then cp $(BENCH_DATA)/targets.json bin/site/targets.json; fi
	printf '{\n\t"date": "%s",\n\t"commit": "%s",\n\t"wasmSize": "%s",\n\t"wasmGz": "%s",\n\t"wasmLegacyGz": "%s",\n\t"dataGz": "%s",\n\t"lixSize": "%s"\n}\n' \
		"$$(date -u +%Y-%m-%d)" "$$(git rev-parse --short HEAD)" \
		"$$(wc -c < bin/site/hih.wasm | $(mb))" \
		"$$(gzip -9c bin/site/hih.wasm | wc -c | $(mb))" \
		"$$(gzip -9c bin/site/hih-legacy.wasm | wc -c | $(mb))" \
		"$$(gzip -9c bin/site/std.bundle | wc -c | $(mb))" \
		"$$(if [ -f bin/site/tools/lix-linux-x86_64 ]; then wc -c < bin/site/tools/lix-linux-x86_64 | $(mb); else echo -; fi)" > bin/site/build-info.json
	cat bin/site/build-info.json
	rm -rf bin/site-build
	$(NODE) site/tools/weights.mjs bin/site

# the site's checks in headless browsers (Playwright, with its browsers):
# every page in Chromium, the key pages in Firefox and WebKit too
# (site/tools/browser-test.mjs)
site-check:
	$(NODE) site/tools/browser-test.mjs bin/site $(or $(BROWSERS),chromium firefox webkit)


# (Examples.hx with the site's class paths; Harness from hxmc's haxe/test)
examples-check: $(TOOL) $(STD) $(HOST_RT)
	ulimit -s unlimited 2>/dev/null || true; $(TOOL) -cp test -cp $(HXMC)/haxe/test $(SITE_CP) --run ExampleBuilds


clean:
	rm -rf bin/gfx bin/3d bin/audio bin/android bin/ios bin/ui bin/view bin/web bin/theme bin/dev bin/os bin/site bin/site-build bin/hxmc-t
