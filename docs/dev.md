# The dev loop with the packages

hxmc's docs/dev.md as it was at the split (hxmc a994ea3). `hxmc dev`
itself (the dev server, packages/cli/hxmc/bootstrap/dev.mjs) is part of
hxmc; the dev host (`hxmc.dev.DevHost`, `hxmc.dev.Hosted`), fast
refresh's primitives (`hxmc.dev.Hot`) and the swaps of windows and GPU
contexts live in `@hxmc/os` (packages/os/src/hxmc/dev) and its users here.


Save a file, see the change, keep where you were. `hxmc dev` builds the
program, runs it, and on every save builds it again and swaps it in; the
new build starts fresh, with the old build's state carried over by key
(fast refresh). Nothing reloads or restarts (step 3, "No reloads"): in the
browser the new module runs in the same page, on the same canvas and GPU
device; natively each build is a shared library loaded into the same
process, the dev host, on the same window and GPU context (Linux, macOS,
Windows); on Android and the iOS simulator the app is the host. The design and what comes next:
[plans/dev-loop.md](plans/dev-loop.md) (steps 1 and 2 are built, step 3 in
the browser, natively, on Android and on the iOS simulator).

```sh
npx haxe --dev build.hxml          # the npm package
bin/hxmc/hxmc dev build.hxml       # the repository's tool
```

The arguments are the build's, as for `haxe` (an hxml file, or options);
the output, `--custom-target hxmc=<out>`, says how the program runs:

- `<out>.wasm` (`-D hxmc.target=wasm32-wasi`): in the browser. The dev
  server serves a page at `http://localhost:4321/` (`--port <n>`, or
  `HXMC_DEV_PORT`; on this machine only, `--host 0.0.0.0` for a phone on
  the network) that runs the module with the browser modules of the
  packages the build uses (their `imports.mjs`, `@hxmc/os`'s
  `browser.mjs`, DejaVu Sans for `@hxmc/text`). WasmGC (`-D hxmc.wasm-gc`)
  works the same way.
- anything else: a native program, started by the dev server (its output
  in the terminal). On Linux a window needs the glibc mode (`-D
  hxmc.libc=glibc`), as always.

What happens:

- The compiler stays resident: the dev server starts it as a compilation
  server (`--server-connect`: it connects to the dev server and takes each
  build on that one connection) and each build is a request to it, with
  `-D hxmc.dev` added. Typed modules, lowered bodies and compiled objects
  stay in memory; a build types again only the modules that changed and
  those that depend on them. The typed modules are kept as they are
  (`-D disable-hxb-cache`, Haxe's in-memory server cache), not written as
  HXB after each build and read back in the next (`HXMC_DEV_HXB_CACHE=1`:
  the HXB cache, Haxe's default); either way a build makes the bytes a
  fresh build makes (`make dev-check`).
- The class paths and libraries the build names (and its hxml files) are
  watched; a change builds again (several changes close together: one
  build).
- A build that compiles swaps the new build in. In the browser the page
  fetches the new module as soon as the program is typed (the server says
  so; the module is held back until the build ends and compiled as it
  arrives), while the old build keeps running and showing its frames. Then
  the old instance snapshots and is disposed (below), and the new module is
  instantiated in the same page, from the snapshot, against the same canvas
  (its last frame shown until the new build's first), the same `GPUDevice`
  (or the canvas's WebGL2 context: the page's `?gfx=webgl2`) and the same
  fonts. Natively on Linux (the dev host, below) the running build writes
  its snapshot, disposes and returns, and the host loads the new build
  into the same process. Elsewhere natively the program writes its
  snapshot to a file and exits, and the new build starts once the snapshot
  is written.
- The dev host (Linux, the glibc mode; `HXMC_DEV_HOST=0`: a process per
  build instead): `hxmc.dev.DevHost`, a small executable built once (and
  cached in `~/.cache/hxmc/dev-host`), is the process of the whole session.
  Each build is a shared library (`-D hxmc.shared -D hxmc.dev-host`,
  added by the dev server; the output renamed `<out>.dev/<n>.so`, a fresh
  name per build), with its own runtime and heap: the host writes the
  address of its state block into the library's `hxmc_dev_state` and calls
  `hxmc_dev_run`, which runs the program's main on a thread of its own
  (`hxmc.dev.Hosted`). The state block holds what survives a swap: the X
  display connection and the window (`hxmc.os`'s X11 window) and the EGL
  display, config, context and window surface (`hxmc.gfx`'s GL back end),
  made by the first build and taken by each next one instead of made; the
  window keeps its size and position, its last frame shown until the new
  build's first. At a reload the dev server names the new library
  (`"library"`); the build snapshots, disposes (its GL objects deleted, the
  context released from its thread, its input method closed: nothing of
  the host's destroyed) and returns from main; its runtime gives its heap
  back (the old space's regions, the nursery, the stacks: `Gc.releaseHeap`,
  shared libraries only), and the host opens the new library before it
  closes the old one, so that the system libraries both use (X11, EGL, the
  GPU driver) stay loaded. The host's memory stays flat across swaps
  (about 125 MB resident for ui's Counter after twelve, as after the
  first). Only the handles and the snapshot cross: no shared heap, no old
  code reachable. A build that ends by itself (its window closed) names no
  next library and the host ends; the next build starts it again. A
  program's own threads must end in its `Hot.onDispose` functions before
  its library is closed. Release builds are the same bytes: all of this is
  under `-D hxmc.dev-host`.
- Disposing an instance in the browser (`host.dispose()`,
  `@hxmc/os`'s `browser.mjs`, option `track`): the program's own disposal
  first (`Hot.onDispose`: the view's roots, and `hxmc.gfx.Device`, which
  releases every buffer, texture, sampler, shader and pipeline it made;
  under `-D hxmc.dev` the GL back end deletes its objects too, the context
  kept), then the packages' (`host.onDispose`: os ends its frames, its
  listeners, observers and audio and keeps its canvases; gfx releases what
  the program left, counted and logged, and leaves the device and the
  canvases' contexts as they are, configured), then whatever the instance
  registered with the page while it ran, recorded as it did: listeners on
  anything it did not create, animation frames, timers, observers, audio
  contexts, and the elements it created (removed; ui's accessibility
  mirror, editors' layer and native controls among them). After that the
  old instance's callbacks do nothing. None of the packages' `imports.mjs`
  has to know about the swap beyond that.
- A build with errors changes nothing: the last good build keeps running.
  The errors show in the terminal and, in the browser, in an overlay over
  the page, which goes away with the next build that compiles. (Errors are
  the typer's; one of hxmc's own, after the page started loading again, a
  link failure, gives the page the last good build again, with the overlay
  and the state carried.)
- Each swap prints its time, from the change seen to the new build's
  first frame: `hxmc dev: swapped in 420 ms (build 346 ms)` (natively
  without the dev host, a new process: `reloaded in`).
- The page reconnects to the dev server when it restarts (and swaps in what
  it built), rather than loading again.

A program that ends by itself (its window closed) starts again with the
next build. A native program without hxmc.os's app loop (a command-line
program) cannot hand its state over: it is stopped and started again.

## The dev host on macOS, Android and iOS

The same host and handover as Linux's, with what each system keeps:

- **macOS.** hxmc writes Mach-O dylibs (`-D hxmc.shared`: `MH_DYLIB`,
  the image at 0, `LC_ID_DYLIB @rpath/<name>`, the exports in the export
  trie, ad-hoc linker-signed), so `hxmc dev` runs a native program on
  macOS in the dev host as on Linux (each build `<out>.dev/<n>.dylib`).
  The program runs on the host's main thread (AppKit's); the first build
  makes the `NSWindow`, its layer's view, text view and `CAMetalLayer` and
  the window's delegate, and each next build takes them (`hxmc.dev.Hosted`
  slots) and replaces the methods of the Objective-C classes the first
  build made (`HxmcWindowDelegate`, `HxmcTextView`) with its own, so the
  window's callbacks reach the running build. The Metal back end leaves
  the layer its device. Checked in CI (gfx-macos: `mac-dev.sh`, the host
  and three builds of `DevHostTest` as dylibs: the count kept, the same
  process and window).
- **Windows.** hxmc writes DLLs (`-D hxmc.shared`: no entry point, the
  exports in an export directory, base relocations, x86-64's included,
  from a preferred base, `-D hxmc.dll-base`, which `hxmc dev` alternates
  between two so that the old build's and the new one's never collide),
  so `hxmc dev` runs a native program in the dev host as elsewhere (each
  build `<out>.dev/<n>.dll`, loaded with `LoadLibrary` on the host's main
  thread, the thread that made the window). The first build makes the
  window and the D3D11 device, its context and the window's swap chain;
  each next build takes them, sets the window's procedure and its class's
  to its own (`SetWindowLongPtr`, `SetClassLongPtr`) and makes its own
  render target views on the swap chain's buffer. Checked in CI
  (gfx-windows, x86-64 and arm64, on WARP: `host-dev.sh` with the host
  and three builds as DLLs, cross-built on Linux) and here under Wine.
- **Android.** The APK is the dev host: `hxmc dev` builds it for its own
  socket (`-D hxmc.dev-server=127.0.0.1:<port>`, the port beside the
  page's, `HXMC_DEV_ANDROID_PORT`; it asks for the `INTERNET` permission,
  `-D hxmc.android-permissions`), installs it (`adb install`, `adb
  reverse`) and starts it once. Its activity glue keeps the window, the
  input queue, the looper and the EGL context: the statics of
  `hxmc.os.android.Activity` and `AndroidWindow` live in the host's state
  block (`hxmc.dev.HostedMacro`, under `-D hxmc.dev-host` only), shared
  with every build loaded later. Each later build is the library of its
  APK (`lib/<abi>/libmain.so`, taken by the dev server): the running build
  fetches it over a connection of its own (`lib <n>`) into the app's files
  directory, writes its snapshot there, hands over and returns from main,
  and the program's thread loads the new library there and runs its
  program, with the same looper, window and context. No reinstall, no
  activity restart, the same process. The libraries and their heaps stay
  loaded (the system's UI thread may still call into a build once: a
  looper's or a frame's callback); a session's memory grows by a build's
  heap per swap. Checked on CI's emulator (`dev-android.mjs`: two edits,
  the same pid, the count kept).
- **iOS, the simulator.** The app is the dev host; each later build is a
  dylib (`-D hxmc.shared` for `ios-sim-arm64`, whose main runs the
  program's body rather than UIKit's start), loaded by the app on the main
  thread inside UIKit's loop once the running build's body returns having
  handed over. The `UIWindow`, its root view controller and the
  `CAMetalLayer`'s view stay; each build replaces the methods of
  `HxmcView` and the app delegate's lifecycle with its own. The simulator
  reads the Mac's files, so the dev server can name the dylib's path
  directly. Checked in CI (ios-simulator: `ios-dev.sh`,
  `DevHostTest.app` and two later builds as dylibs: the count kept, the
  same process and view; `HXMC_DEV_NEXT`, libraries handed over to in
  turn a second after the first frame, is how the test drives it without a
  dev server). `hxmc dev` with an `.app` output for `ios-sim-arm64`
  installs and launches the app on the booted simulator (`xcrun simctl`,
  its output in `<out>.dev/stdout.txt`), then builds each change as a
  dylib (`-D hxmc.shared -D hxmc.output=<out>.dev/next.dylib`, renamed
  `<n>.dylib`) and names it in the reload message (not yet run in CI: the
  simulator job has no compiler).
- **iOS, a device: not possible with a dylib.** What was found (no device
  was tried here): Apple's DTS answer to exactly this question (a dylib
  signed with the developer's identity, sent to a development-signed app
  on an iPhone in Developer Mode, written to its container and `dlopen`ed)
  is no: "you can only open a library that's either built in to the OS or
  embedded within your app" ([Apple Developer Forums
  773210](https://developer.apple.com/forums/thread/773210), Quinn "The
  Eskimo!"); the poster reports it worked on iOS 17 with Xcode attached
  and fails on iOS 18 with "code signature invalid", and works once the
  dylib is inside the app bundle. InjectionNext, which signs each dylib
  with the identity of the app's build ("expanded codesigning identity",
  `codesign --force -s <identity>`, no entitlements) and loads it from the
  app's data container's `tmp/`, has the same failure open on device since
  iOS 18.6 and on iOS 26 ([InjectionNext
  #81](https://github.com/johnno1962/InjectionNext/issues/81): a valid
  signature with the app's TeamIdentifier, "code signature invalid
  (errno=1)"; the maintainer has not reproduced it, contributors conclude
  device injection cannot work on iOS 18+). Library validation also means
  only code signed by the team (or Apple) loads at all
  ([forum thread 670761](https://developer.apple.com/forums/thread/670761)).
  So `CodeSign.hx` signing each dylib with the developer identity (it signs
  ad hoc only today) would not be enough: the only loadable place is the
  app bundle, and installing a new bundle restarts the app. The device
  fallback therefore stays the plan's: the program as wasm run by an
  interpreter inside the host app (UI work, slower; nothing of it is built
  yet), and a restart (reinstall, the snapshot carried) as the last resort.

## Fast refresh: state carried by key

A reload is never a patch of running code: the new build runs its own
`main`, and what it gets from the old one is data, restored by key. So a
reload behaves like a cold start with the same values, on every target, and
there are no stale closures or half-migrated objects. State that cannot be
carried is reset, visibly (a line in the terminal or the console).

**Signals.** Every `signal(...)` of `@hxmc/view` is keyed with no code
written for it:

- its static name: the type and function it is made in and the variable it
  is assigned to (`var open = signal(false)` in `App.Menu`:
  `App.Menu.open`; a field `public final count = signal(0)`: `Gallery.count`),
  else its order among the unnamed ones of that function (`#0`, `#1`).
  Names, not line numbers: edits around a signal keep its key;
- inside the component instance it is made in: each component runs in a
  scope of its name, `Card`, a second one in the same place `Card#1`; with a
  `key` attribute (`<Card key={item.id}/>`) the scope is `Card[<key>]`,
  so a list keeps each item's state even when the items move. `key` is no
  prop: the component does not declare it;
- the rows of `For` and `Index` in a scope of their position, and each
  computation (an effect, a reactive region, `Show`) in a scope of its own,
  so that what a region shows later (a `Show` turned on after a click) is
  keyed as when it first showed, and finds its state when the new build
  shows it at once.

A signal's value is saved with its type's hash; a new build whose signal
has another type (`signal(0)` became `signal("")`, a structure got a field)
resets it and says so:

```
hxmc.dev: Counter.main.count reset: its type changed
```

A signal's initial value is part of it too (its source, hashed, as React
does for `useState`): editing `signal(0)` to `signal(5)` starts it at 5,
and says so (`hxmc.dev: App.main.count reset: its initial value
changed`); an edit elsewhere keeps its value. A class marked
`@:hot(reset)` (or the function a signal is made in) keeps none of its
signals: each build starts them afresh (React's `// @refresh reset`).

Values go through `haxe.Serializer`, so a signal keeps data: numbers,
strings, booleans, arrays, maps, structures, enums and class instances of
data. A signal whose type is not data (a function, `Dynamic`, a node of the
UI, a native handle) is not kept and starts again from its initial value
(the dev server lists them at each reload); so is one whose type is not
known where it is made (`signal([])` with nothing saying what the array
holds: give the type, `var s:Signal<Array<String>> = signal([])`). A value
the old build saved and the new one never asks for (a signal removed) is
dropped after the first frame, and listed.

**State outside components** (models, stores, app-level values) opts in
with a key of its own:

```haxe
var cart = Hot.keep("cart", () -> new Cart());   // the old build's Cart, else a new one
```

**Disposal.** Before the new build starts, the old one releases what it
owns: the roots `Render.render` made are disposed (every effect's cleanups
run), and the functions given to `Hot.onDispose` run, last given first.

**Release builds pay nothing.** All of this exists only with `-D
hxmc.dev`: without it `signal(v)` is `new Signal(v)` as before, components
are called as before, `hxmc.os.App`'s loop has no dev client, and every
`Hot` call compiles to nothing. The counter, the gallery and the cube built
before and after this was added are the same bytes, natively, as wasm and
as WasmGC.

## The primitives: `hxmc.dev.Hot`

Fast refresh is built on a small public layer in `@hxmc/os` (no view or ui
dependency): `hxmc.dev.Hot`. hxmc's signals (`hxmc.view.Refresh`) and
components (the markup macro) are its first clients and use nothing else,
so any state library (a store, another signal library, an ECS, a game's
world) gets fast refresh the same way, without hxmc knowing about it.

| Call | |
| --- | --- |
| `Hot.reloading` | true while this build starts from a snapshot (until its first frame); false on a cold start |
| `Hot.onSnapshot(f)` | `f` runs before the swap, to save values; returns a function that removes `f` (when what it saves is gone) |
| `Hot.onDispose(f)` | `f` runs after the snapshot, before the new build starts: release what this build owns (effects, timers, sockets, GPU buffers); returns a remover |
| `Hot.save(key, value, type, ?encode)` | `value` kept for the next build, by key; `haxe.Serializer` by default, or `encode: T->String` for a value that does not serialize as it is |
| `Hot.load(key, type, ?decode)` | the value the last build saved under `key`, once (`decode: String->T` to match `encode`); null when there is none or its type changed (logged), never cast |
| `Hot.typeOf((_ : T))` | `T`'s shape hashed when compiling (its fields and their types, recursively); `""` for a type that is not data, which `save` skips. Any other expression gives the hash of its type, unevaluated |
| `Hot.here()` | the static identity of the place it is written: `Type.method.variable` |
| `Hot.scope(name, f)` | runs `f` with `name` nested in the keys made inside it (a component instance, a list item); a name given twice in one scope becomes `name#1`, ... |
| `Hot.keep(key, init)` | a value kept as it is: `load`, else `init()`, saved again on each snapshot (a mutable object: its state at the snapshot) |
| `Hot.path()`, `Hot.at(path, f)` | the current scope, and `f` run in a scope taken earlier: for code that runs later (an effect running again, a row added after a click) |

Keys are relative to the scope: `save` and `load` resolve them against it,
and `load` numbers a key loaded twice in one scope (`key#1`), as `scope`
numbers names. The functions given to `onSnapshot` and `onDispose` run in
the scope, and with the key resolutions, of where they were given, so
`save(key)` there reaches what `load(key)` read.

For a library's own macros, `hxmc.dev.HotMacro` gives the same at compile
time: `HotMacro.hash(type)` (what `typeOf` gives) and
`HotMacro.here(Context.currentPos())`, the place of the macro's call
(`Hot.here()` written inside a macro's `macro` block is the place of that
block, as every expression there is). Both give `""` without `-D hxmc.dev`.

Where this differs from the plan's names: Haxe has no explicit type
arguments, so `Hot.typeOf<T>()` is written `Hot.typeOf((_ : T))`;
`onSnapshot` and `onDispose` return removers (a component's signal stops
being saved once the component is gone); `Hot.path()` and `Hot.at()` were
added, because computations that run again later must find their keys
where they first ran.

### A state library

A small store, written as a third-party library would be (it knows nothing
of hxmc.view), is reload-safe in three lines, and its users write nothing
(`packages/os/test/store/Store.hx`, tested in CI by `HotTest`):

```haxe
class Store<S> {
	public var state(default, null):S;

	public function new(key:String, initial:S, type:String) {
		var kept:Null<S> = Hot.load(key, type);           // the last build's state, if its type is the same
		state = kept != null ? kept : initial;
		Hot.onSnapshot(() -> Hot.save(key, state, type)); // and this build's, for the next
	}

	// `var cart = Store.create(...)`: keyed Type.method.cart, its state's type hashed where it is made
	public static macro function create(initial:haxe.macro.Expr):haxe.macro.Expr
		return macro new store.Store($v{hxmc.dev.HotMacro.here(haxe.macro.Context.currentPos())}, $initial,
			hxmc.dev.Hot.typeOf($initial));

	public function update(f:S->S) ...
}

var cart = Store.create(({items: [], total: 0.0} : Cart));
```

Without `-D hxmc.dev` the same code compiles to the store alone: `load` is
null, `onSnapshot` and `save` are nothing, `here` and `typeOf` are `""`.

The type is hashed where the store is made because a generic class only
knows `S` as a type parameter; a library whose primitive is a function
takes the hash as an argument from a macro, as `create` does, or asks its
users for `Hot.typeOf((_ : T))`. A library with code that runs later in its
own scope (as view's effects do) takes `Hot.path()` when it is made and
runs that code in `Hot.at(path, f)`.

## The protocol

The dev server and the program talk in JSON messages: JSON lines over a
TCP connection natively, WebSocket text messages in the browser (the
page's `/__hxmc/ws`), so editors and other tools can drive the loop:

| To the program | |
| --- | --- |
| `{"type":"reload"}` | a new build is ready: snapshot, dispose, hand over. Natively it carries `"snapshot": <file>`: write the snapshot there, answer `saved`, exit (with the dev host, `"library": <file>` too: hand the host's handles over to that library and return from main). In the browser the page fetches the new module (`/__hxmc/app.wasm?swap`: 409 when the build failed, the running one stays), asks the running module for its snapshot, disposes it and runs the new one in the same page |
| `{"type":"error","message":<text>}` | the build failed (the overlay); the program keeps running |
| `{"type":"ok"}` | the build compiles again (the overlay goes) |
| `{"type":"assets", ...}` | reserved: styles and images without a rebuild (step 4) |

| From the program | |
| --- | --- |
| `{"type":"saved"}` | natively: the snapshot is written |
| `{"type":"frame"}` | the first frame of a build is drawn (the reload's time) |
| `{"type":"log","text":<text>}` | the page: a line the module printed |

The snapshot is a string, `haxe.Serializer`'s encoding of an array of
strings: key, type hash, value (`Hot.save`'s encoding), key, ... A native
program finds the dev server in `HXMC_DEV=<host>:<port>` and starts from
the snapshot file in `HXMC_DEV_SNAPSHOT`; with only the latter, a program
starts from a snapshot without any dev server (as the tests do). In the
browser the page gives the module the imports of `hxmc_dev`:
`restore_length()` and `restore_take(p)` (the snapshot it was given, -1:
none), `register(f)` (the `@:hxmc.callback` the page calls for a reload),
`send(p, n)` (the snapshot) and `frame()`. hxmc.os's app loop reads the
dev server's messages at each turn (an idle loop wakes every 10 ms in a dev
build) and reports the first frame.

## Times

The browser's swap (step 3), measured as below (`dev-latency.mjs`, six
edits, the machine less busy, load 0.8-1.3):

| | build | save to frame | the reload before |
| --- | --- | --- | --- |
| Counter, browser (wasm) | 0.35 s | 0.42 s | 0.45-0.49 s |
| Counter, browser (WasmGC) | 0.33 s | 0.43 s | 0.47-0.49 s |
| Gallery, browser (wasm) | 0.72 s | 0.94 s | 1.07-1.14 s |
| Gallery, browser (WasmGC) | 0.77 s | 1.09 s | 1.10-1.11 s |
| Counter, native (Linux, the dev host) | 0.37 s | 0.44-0.45 s | 0.52-0.56 s |
| Gallery, native (Linux, the dev host) | 0.81 s | 0.89 s | 0.90-0.93 s |
| a drawn cube, Android (CI's x86-64 emulator) | 0.15 s | 0.30 s | (a reinstall, many seconds) |

(Android: the dev-android.mjs edits on CI's emulator, one run: the swap
after the build, 0.15 s, is the library taken from its APK, fetched over
adb's reversed socket, written and loaded on the device. The iOS simulator,
macOS and Windows are checked in CI without a timed `hxmc dev`.)
Natively the swap after the build is 0.07-0.09 s (the snapshot, the
dispose, loading the library and its first frame), where the restart was
0.12-0.14 s (most of it loading Mesa and making the window, which the host
keeps). A swap costs no more than the reload did: the reload already overlapped
the page's loading with the build, and the swap overlaps nothing it needs
(the old build runs on during the build); what is left after the build is
compiling the module as it arrives, the snapshot, the dispose and the new
build's start to its first frame.

The reloads before step 3: from the save to the new build's first frame, a one-line edit of the
program's `main` (`node packages/os/test/dev/dev-latency.mjs <compiler>
<example> web|web-gc|native`: the medians of six edits), on a 4-core x86-64
Linux machine, headless Chromium with SwiftShader, natively under Xvfb with
llvmpipe; ui's Counter (about 400 modules, 1700 functions) and Gallery (about
3300 functions):

| | build | save to frame | target |
| --- | --- | --- | --- |
| Counter, browser (wasm) | 0.38-0.40 s | 0.45-0.49 s | 0.5 s |
| Counter, browser (WasmGC) | 0.37 s | 0.47-0.49 s | 0.5 s |
| Counter, native | 0.38-0.42 s | 0.52-0.56 s | 0.5 s |
| Gallery, browser (wasm) | 0.88-0.93 s | 1.07-1.14 s | 1.5 s |
| Gallery, browser (WasmGC) | 0.79-0.80 s | 1.10-1.11 s | 1.5 s |
| Gallery, native | 0.73-0.75 s | 0.90-0.93 s | 1.5 s |

(Two runs each, the machine shared and busy, load 1.1-2.1; runs vary by
about 10%. The build before these changes, measured alongside: Counter
0.95-1.12 s save to frame, Gallery 1.53-1.85 s.) Of an edit's build, in
the compilation server: 0.1-0.15 s is Haxe's (typing the changed module,
DCE 0.06-0.08 s, the module checks; the Gallery's edit types its large
module of markup again, 0.2-0.3 s of macros), and hxmc's is 0.18 s for the
Counter, 0.35 s for the Gallery: lowering (`LowerCache` replays the
bodies of the modules not typed again, as bindHosts left them: 0.06 s, 0.1
s), Reach and the program's facts (0.04 s, 0.08 s), the modules' keys
(`Fingerprint`, on every core: 0.02 s, 0.03 s), the data and the link
(0.05 s, 0.08 s). After the build, the reload: in the browser the page
has loaded again meanwhile (the program typed, the server says so), and
the new module runs to its first frame in 0.05-0.1 s (the Counter) to
0.15-0.3 s (the Gallery, WasmGC); natively the new process starts once
the old one has written its snapshot, and its first frame is 0.12-0.14 s
later, most of it loading Mesa (llvmpipe) and making the window.

Before: the compilation server kept its typed modules as HXB (Haxe's
default), so each build wrote every module as HXB and read each back
(0.3-0.4 s); `-D disable-hxb-cache` (Haxe's in-memory mode) is most of the
difference (with the HXB cache, the builds above are 0.84 s and 1.2 s
natively). The rest: hxmc's lowering, keys and analyses made cheaper
(bindHosts kept with the replayed bodies, an inlined callee's key text
written once a build, string literals' names kept, Reach's and Facts'
fixpoints walking each body once, WasmGC's IrOpt on every core, the
processor count asked once), one connection to the server (a request per
connection could find the server reading before it was sent, which waits
50 ms), the page loading again during the build and fetching its module
and fonts from its start, a 10 ms idle wake in a dev build (was 50 ms)
and a 10 ms window for changes close together (was 20 ms).

Note: the edits the measurement makes are the same each run (`"edit 1"`,
...), so the objects of the edited module are often in the object store
from an earlier run; a new edit compiles that module too (the Gallery's
large one: 0.05 s more).

## Tests

`make dev-check` (CI: the `gfx` job): `HotTest` (the primitives and the
store across a reload, natively and on Eval, a changed type reset),
`RefreshTest` (view's keys: component instances, rows, `key`, a region
shown later), then `hxmc dev` on ui's Counter in headless Chromium (as wasm
and as WasmGC) and natively under Xvfb: an edit keeps the count, a changed
type resets it, a compile error shows in the overlay (the terminal) while
the last good build keeps running, the fix swaps in with the count kept.
Natively on Linux, after each swap the window's id and the process (as
each build prints them, `hxmc.dev: the host's window 0x... (process N)`)
are the same, no program ended, and the last library is the bytes of a
fresh build with the host's options. In the browser, on a WebGPU page and
on a second page with `?gfx=webgl2`,
after each swap: no reload (a marker set on `window` survives, Playwright
saw one navigation, the Performance API's navigation entries and
`timeOrigin` unchanged), the same canvas (the only one), the same
`GPUDevice` or WebGL2 context, and no GPU objects left by the old build;
then the compilation server's builds, asked as `hxmc dev` asks them,
through edits of the Counter, of a module it uses whose API changes and of
a module of markup (an attribute changed, an element added), each against
a fresh build of the same sources, byte for byte
(`packages/os/test/dev/dev-verify.mjs <compiler> [example] [native|web|web-gc]`).

Beyond `make dev-check`, in CI: `dev-android.mjs` on the android job's
emulator (`hxmc dev` on a drawn program built as an APK: installed once,
two edits swapped into the same process, the count kept), `ios-dev.sh` on
the ios-simulator job, and `host-dev.sh` on gfx-macos and gfx-windows
(`DevHostTest`'s app or host and two or three later builds as libraries,
handing over by themselves: the count kept, the same process and window
or view).
## Not yet

- An iOS device cannot load a new build's code (above): the wasm fallback
  is not built. The dev host is tested on macOS, Windows and the iOS
  simulator with `DevHostTest` handing over by itself (`HXMC_DEV_NEXT`),
  and on Linux and Android with `hxmc dev`'s own edits; `hxmc dev` itself
  is not run in CI on macOS, Windows or the simulator.
- Styles and assets without a rebuild (step 4).
- The UI engine's own state (focus, scroll and selection by node key) is
  the UI session's part of step 2; ui's widgets' own signals are keyed
  like any other already.
