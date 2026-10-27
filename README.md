# helder

An experimental stack for building games and apps in Haxe, for desktop,
mobile and the web, from one npm package. Built on
[hxmc](https://github.com/benmerckx/hxmc), the Haxe compiler with a native
and WebAssembly target. **Unstable**: APIs change without notice.

The goal (the CLI does not exist yet, see the roadmap):

```sh
npm install helder
npx helder dev            # this machine, with live reload
npx helder dev android    # boots an emulator, installs, live reloads
npx helder build ios
```

## Aims

- **One package, one CLI.** `helder` is all a user installs: it carries the
  compiler (hxmc stays an implementation detail, never a second tool to
  learn) and the platform tooling behind `helder dev` and `helder build`.
- **Little configuration.** A project is a folder with a `Main`; targets,
  SDKs, emulators and signing for development are found or set up by the
  CLI. Configuration is for overriding defaults, not for getting started.
- **Live reload on every platform.** Desktop, web, Android and iOS, with
  state kept across a reload, from the same `helder dev`.
- **A GC-free core, GC user code.** The engine (layout, text, rendering,
  scene, physics, audio) is written on `helder.scoped`: memory that lives in
  a scope and is freed with it, no garbage collector involved. User code
  sits on top as ordinary Haxe with the GC, and should not have to know.
- **Performance, small binaries, fast compiles.** Measured, not assumed:
  each package has a benchmark, and binary size and compile time are
  tracked like test results.
- **Familiar APIs.** Each package's API stays close to the solution people
  already know for that problem, so it can be learned from their docs. The
  3D API resembles three.js (scenes, meshes, materials, cameras, loaders),
  informed by a look at Babylon.js, PlayCanvas, Godot and Bevy; UI resembles
  the DOM and CSS; 2D resembles the common sprite and tilemap libraries.
- **Markup for scenes too.** Games and 3D scenes can be written in view's
  markup, as react-three-fiber does for three.js, without giving up
  performance: markup compiles to direct calls and signals update only the
  property they are bound to, with no reconciliation.
- **Consistency.** The packages share naming, error handling, units,
  coordinate conventions and resource lifetimes, and read as one library.

## Packages

All under `src/helder`, Haxe package `helder.<name>`:

| | |
| --- | --- |
| `os` | windows, input, the app loop and audio: X11, Cocoa, Win32, Android, UIKit, the browser |
| `gfx` | a portable GPU API: GL/GLES, Metal, D3D11, WebGPU, WebGL2; shaders written in Haxe |
| `text` | TrueType and CFF fonts in pure Haxe: rasterizing, shaping, bidi, layout, a glyph atlas |
| `image` | PNG, JPEG, GIF and WebP decoded in pure Haxe, and animations' frames |
| `view` | signals and JSX-like markup, compiled to direct calls on a renderer chosen at compile time |
| `ui` | flexbox layout, events, focus and accessibility, drawn on gfx or as the platform's controls |
| `web` | `view` on the web: DOM and static renderers, hydration, islands |
| `scene` | 3D on gfx: glTF, a PBR renderer, animation, input actions |
| `physics` | a small rigid-body core for `scene` |
| `scoped` | scoped memory on any Haxe target, and a checker that keeps it out of the GC heap |
| `async` | a loop per thread for Haxe 5's coroutines: tasks, timers, TCP, child processes, file watching, an HTTP and WebSocket server; the browser's loop |
| `dev` | the dev host and state kept across a reload |

`examples/` has a program per folder; `tests/Run.hx` has the checks:

```sh
bun install
bun run test              # the lanes that need no GPU, display or browser
bun run test help         # every lane
```

## Roadmap

In order: each phase leans on the one before it.

### 1. Cleanup

- **Fix the references the restructure left behind** in `tests/`: comments
  there still point to `docs/`, `packages/`, `make` and `npm test` (`src/`
  is done).

### 2. Async core, then the CLI on it (desktop and web)

- **The async core first** (`helder.async`, done as a first slice): a loop
  per thread for Haxe 5's coroutines, tasks with structured concurrency
  and cancellation, timers, TCP, child processes, polled file watching and
  an HTTP and WebSocket server natively, the same loop turned by the
  browser's on the web; `examples/async-dev` serves, watches and streams a
  child's output at once. What the CLI still needs of it:
  - **backends behind its completion-based I/O**: io_uring on Linux (select
    where it is disabled: Android apps, some containers), kqueue on macOS,
    IOCP on Windows; I/O buffers outside the moving GC heap for them;
  - **native watchers** (inotify, FSEvents, `ReadDirectoryChangesW`) behind
    `Watcher`, and a process's exit without polling (pidfd, kqueue, a wait
    handle);
  - **processes with a working directory and an environment** (hxmc's
    `processRun` takes neither), and Windows' pipes without threads;
  - **tested on macOS and Windows** (both build; neither has run).
- **Then the CLI on it:**
  - **`helder dev [target]`, `helder run [target]` and `helder build
    [target]`**, for the host and `web` first; Android and iOS follow in
    phase 4. Project scaffolding (`helder new`) and a `helder doctor` wait.
  - **A native program**, written in Haxe and built by hxmc, shipped like
    the compiler: one optional npm dependency per OS and CPU
    (`@helder/<os>-<cpu>`, as `@hxmc/<os>-<cpu>`). No node at run time; it
    also exercises the native target's sockets, processes and file watching,
    which helder needs anyway.
  - **The compiler stays its own process**, a resident compilation server
    (`--server-connect`) the CLI drives: a crash of the compiler does not end
    the session, and hxmc's GPL-licensed compiler is not linked into the
    MIT CLI. The CLI gives it its std and runtime objects itself, so users
    never install or call hxmc.
  - **The dev loop ported from hxmc's `dev.mjs`** (node today): the link to
    the compilation server, file watching (polling first, then inotify,
    FSEvents and `ReadDirectoryChangesW`), the HTTP and WebSocket server for
    `web`, the reload protocol (JSON lines), and changed assets sent without
    a recompile.
  - **Live reload in the process on every desktop**: the dev host
    (`helder.dev`, under the CLI now) loads each build as a shared library on
    Linux; macOS (dylibs) and Windows (DLLs) restart with a snapshot today and
    get the same host.
  - **Conventions instead of configuration**: `src/Main.hx` is the entry
    point, `assets/` is packed by the build and reloaded live by dev, `bin/<target>`
    holds the outputs; name, version and app id come from `package.json`,
    overrides from a `"helder"` key in it, and a `helder.hxml` beside it is
    the escape hatch.
  - **Every build reports its compile time and binary size.**
  - **The examples are the CLI's fixtures**, laid out as projects: each
    builds and reloads with no configuration of its own, in CI.

### 3. Foundations

Side by side, as they constrain each other. The async design comes from a
study of Dart's isolates, Go's channels, Goose, Kotlin's dispatchers, Unity's
jobs (Burst) and the Fiberus Haxe target, against hxmc's runtime: one GC heap
shared by all threads, collected stop-the-world, where a thread joins a
collection only when it allocates or blocks.

- **Async on the app's loop**, on phase 2's `helder.async` (a loop per
  thread, a coroutine never changing thread, structured concurrency and
  haxe.coro's cancellation are there):
  - **the main loop driven by `App.run`**: a turn of it at a fixed point of
    the frame, the waits of X11, Cocoa and Win32 bounded by its timers and
    woken by its sockets, and it keeps running without frames (a hidden
    browser tab pauses `requestAnimationFrame`; natively, replies from
    workers wake `App.run`);
  - **scopes owned by the app**, children cancelled with their parent;
  - first on it: `Fetch` (an awaitable one exists, `helder.os.Fetch` to
    follow), the next frame, asset loading.
- **Background work as jobs on workers**, the same API natively and on
  the web:
  - natively, threads over the shared heap with the semantics of isolates
    (no shared mutable GC state);
  - on the web, Web Workers instantiating the program's own compiled
    module, a job named by its index in the function table (no cross-origin
    isolation needed; SharedArrayBuffer only as a fast path), and an inline
    fallback where workers are missing;
  - **two tiers of jobs**: GC-free jobs on scoped data, checked by the
    compiler, which the collector never waits for (the default for the
    engine: decoding, physics, pathfinding); and ordinary GC jobs for user
    code, allowed as freely as measurements say;
  - **channels** between threads carrying values that can be sent (checked
    by a macro, as Swift's `Sendable`): flat values, scoped structs, Strings
    and Bytes (copied), and owned buffers (handed over without a copy
    natively, transferred on the web).
- **The core on `helder.scoped`.** Start with one package as a pilot (text's
  rasterizer and glyph atlas, or ui's layout), with a benchmark before and
  after, then the rest: ui, gfx's command recording, scene, physics, audio.
  The GC-facing API of each package stays.
  - **A scope never spans an await**: the checker rejects scoped values in a
    coroutine's body; coroutines call `@:scoped` functions, which return
    before the next await.
  - A slice or span never crosses threads: an owned buffer does.
  - Each worker has its own scoped stack; scoped's slow paths (the pool's
    lock, its errors) become GC-free, and its limit of 31 buffers is
    revisited for pools of workers.
- **To prototype first, and what decides it**: the main loop with the
  next frame (`Fetch` and a delay are there); then one worker on the web;
  then a 4K PNG decoded on the main thread, as a GC job and as a GC-free job while the
  main thread renders, measuring the frames' p99 and longest time and the
  collector's pauses. If a GC job keeps the main thread's longest pause
  under about 1 ms, GC jobs are allowed freely; if not, the engine uses only
  GC-free ones. (Upstream's hxcoro or a runtime of our own: our own,
  `helder.async`, which hxcoro's tasks run on.)

### 4. Mobile

- **`helder dev android` and `helder dev ios`**: a connected device, a running
  emulator or simulator, or one booted for it; the host installed once,
  each build swapped into it.
- **The frame loop from the display**: Choreographer on Android,
  CADisplayLink on iOS (Android polls its looper today, iOS paces from the
  layer's drawables).
- **Audio on Android (AAudio) and iOS (RemoteIO)**, and a mixer above every
  back end.
- **Multi-touch and gestures**: touches as events in `os` (one drag today,
  `TouchDrag`), gesture recognizers (pan, pinch, rotate, long press) in ui.
- **Assets in bundles**: in the APK and the iOS app bundle, read through one
  API on every platform, packed by `helder build`.
- **CI on an Android emulator and the iOS simulator.**

### 5. Graphics, 3D and 2D

- **Compressed textures**: ETC2 and ASTC on mobile (and BC on desktop),
  chosen per target by the asset step.
- **MSAA** render targets in gfx.
- **The 3D API close to three.js** (see Aims), after a study of three.js,
  Babylon.js, PlayCanvas, Godot and Bevy.
- **The scene in view's markup**, react-three-fiber's model on
  `helder.scene.view` (a prototype today, tests/3d-ui):
  - the tags generated from the 3D API's classes, their props its
    properties, so markup and code stay one API;
  - bindings that store into the scene's flat data; signals' changes
    applied once per frame, before rendering;
  - markup for structure, not for every value that moves: an `onFrame`
    that writes the nodes it is given, and instancing elements with their
    per-instance data in scoped arrays (particles, crowds, foliage);
  - hxmc passing a closure returning a struct value (a `Vec3`) where a
    binding expects one (the prototype goes through a signal);
  - measured against the same scene written by hand, at thousands of
    nodes.
- **`helder.2d`**: sprite batches and tilemaps on gfx and `helder.image`,
  in code and in markup alike.

### 6. Editor

- **A VS Code extension**: the language server, syntax highlighting, and
  support for view's markup.

## License

MIT (LICENSE).
