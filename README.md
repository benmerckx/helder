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
- **An allocation-free core, GC user code.** The engine's hot paths
  (layout, text, rendering, scene, physics, audio) allocate nothing per
  frame or per call, so the collector never pauses it: buffers kept and
  reused between calls, or `helder.scoped`'s memory where it measures
  better (temporaries within a call, data handed to a GC-free job). User
  code sits on top as ordinary Haxe with the GC, and should not have to know.
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

- **Tools in the box.** One devtools app, built with helder's own ui,
  runs the program beside its assets, stories, inspectors and profiler, on
  every platform, and shows what the allocation-free core promises: the
  garbage of every frame.

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
| `test` | tests as bun writes them, without macros: `describe`, `test`, hooks, assertions as functions, async tests on `async`'s loop; `helder test` runs the `*.test.hx` files |
| `cli` | the `helder` command, a native program on `async`: `helder test` so far |

`examples/` has a program per folder; `tests/Run.hx` has the checks, and
the `*.test.hx` files are helder.test's, run by the CLI built from this
checkout (bin/cli/helder, rebuilt when its sources change):

```sh
bun install
bun run test              # the lanes that need no GPU, display or browser
bun run test help         # every lane
bun run helder test       # the *.test.hx files (--target all, --watch, -t <name>)
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
  - **`helder test [filter]`** and **`helder.test`**, done as a first slice
    (src/helder/test/README.md): the CLI's first command, a native program
    on `helder.async` (`bun run helder test` builds and runs it from the
    checkout); the `*.test.hx` files under `src/`, `tests/` and the class
    paths linked into bin/test/src (Haxe takes no dot in a module's name), a
    main generated that calls each one's `tests()`, built once and run on
    the host, Eval or wasm32-wasi (`--target all`), the paths written back as
    the real files'; `-t`, `--watch` (a compilation server's builds) and `-u`
    for text snapshots. The library has no macros: `describe`, `test`
    (`.skip()`, `.only()`, `.timeout()`), the four hooks, `async(coroutine)`
    bodies on `helder.async`'s loop, `assert`, `equals` (deep, both values
    shown), `notEquals`, `approx`, `throws`, `require`, `fail`, `snapshot`.
    AsyncTest's tasks, cancellation, errors and timers moved to it
    (tests/async/Tasks.test.hx). Still to come:
    - the rest of `tests/` moved to it, and golden images beside snapshots;
    - editor support: the display server takes `Foo.test.hx` for the module
      `Foo` (a test file has no diagnostics, hover or completion);
    - `--target web` (Chromium), Windows' links tried (developer mode, else
      copies), the CLI shipped as a binary on npm;
    - a macro later (`@:test` collection, an `assert` showing its values).
  - **Every build reports its compile time and binary size.**
  - **One message format on the dev connection** for reloads, logs and
    the devtools (phase 3): JSON-RPC as the Chrome DevTools Protocol and
    Dart's VM service have it, methods in domains (`Ui`, `Scene`,
    `Signals`, `Profiler`, `Assets`, `Log`, `Stories`) that cost nothing
    until a tool enables them, libraries adding their own (as Godot's
    debugger), get, query and set on properties (as Bevy's BRP), profiler
    samples as a binary stream, node ids kept across reloads, versioned.
  - **The examples are the CLI's fixtures**, laid out as projects: each
    builds and reloads with no configuration of its own, in CI.

- **Renderers as tags in markup**, react-three-fiber's `<Canvas>` model,
  replacing the `-D helder.view.renderer.<name>` defines (the CLI adds
  them from imports until then):
  - **`<Surface>`**, the root ui draws into: a window natively (the window,
    its GPU surface, a ui root, the frame loop; reactive props, several for
    several windows), the app's screen on a phone, a canvas filling the page
    on the web. Nested in the DOM's or static HTML's markup it is a
    `<canvas>` element sized by the page's styles (a ResizeObserver), the
    static renderer's an island the wasm program hydrates; a page can hold
    several. `App.run(<Surface ...>)`.
  - **Boundary tags** switch renderer for their children: `<Scene>` a box in
    ui's layout whose children are scene nodes, `<Ui>` back to ui inside a
    scene (following a node, as drei's `<Html>`), `<Dom>`/`<Html>` for the
    web's. Each subtree is compiled once, for the renderer that owns it
    (today every literal is compiled once per renderer), and only renderers
    a program reaches get a runtime: no defines, no guessing.
  - Components compiled for each renderer that uses them, or pinned to one
    by their return type; `Render.render(markup, node)` stays for mounting
    into a node of your own. To settle: errors for a tag in the wrong
    renderer, pointer events across a boundary (picking through a scene),
    `<Page>` as the root for servers and static sites.

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
- **An allocation-free core**, measured by `bun run test bench`
  ([baseline](tests/bench/results/baseline.md)), with whatever storage
  measures best. The text pilot ([results](tests/bench/results/text.md))
  removed its garbage (a warm atlas allocates nothing), but scoped memory
  made a cold atlas 6% slower natively and 35% on wasm32; on GC buffers
  kept for the next call it is 6% and 8% faster than before, with the same
  garbage. Physics ([results](tests/bench/results/physics.md)) allocates
  nothing in steady state (from 40-720 KB a step): contacts in reused GC
  arrays, struct-of-arrays, no boxed vectors; scoped memory measured within
  5% either way, with a larger, slower build, so GC buffers. TextLayout's
  output is flat glyph data, read by index, in buffers a layout keeps and
  wraps again at another width ([results](tests/bench/results/ui-text.md)):
  ui's full layout of 10k nodes from 11 MB of garbage to 94 bytes, 3.9x
  faster natively, 3.1x on wasm32. Next: ui's pointer moves (578 bytes
  each: the hover paths' Arrays, the events); flexbox and scene allocate
  next to nothing. The GC-facing API of each package stays.
- **`helder.scoped` where it fits**, the default once it costs less:
  cheaper access (natively the base in a register, on wasm32 no table),
  memory a GC object can own (caches), a way through interfaces
  (callbacks).
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
- **The devtools app** (`helder devtools`; design from a study of Unity's,
  Unreal's, Godot's, Defold's and Bevy's tools, Flutter DevTools, Tracy,
  Storybook, Makepad Studio and Bezi), built with helder's ui, natively and
  as a page `helder dev` serves; an editor's shell without scene authoring:
  - **the program in a panel**: hosted by the dev host natively, its canvas
    in the page on the web, a phone attached through the CLI (which holds
    every build's connection, and outlives a crash with its logs);
  - **an agent in dev builds only** (`-D hxmc.dev`, as `Hot`; a few tens of
    KB): counters and spans that do not allocate, GC bytes and pauses per
    frame, tree snapshots on request, commands, pick and highlight;
  - **the assets** with previews (images, fonts, glTF, audio) and their
    import settings, reloaded live;
  - **stories**, as Storybook's: `Foo.story.hx` files (linked as
    `.test.hx` files are) whose `stories()` registers
    `story("Inventory/full", c -> ...)`, built into dev builds only; controls
    are signals (`c.number`, `c.bool`, a choice, a colour), so an edit
    updates only what is bound; the story and its controls kept across a
    reload; a story is a test too, rendered headlessly by `helder test`
    against a snapshot (an image, or the tree as text), with a scripted
    interaction and assertions;
  - **inspectors**: the ui tree (layout, styles, accessibility), signals and
    view's graph, each node traced to its markup line; the state a reload
    kept and dropped;
  - **a profiler**: frame time, spans, GC bytes per frame split into the
    engine's and the program's; logs and a console; pause and step;
  - **literals edited without a recompile**, as Makepad's live design: in
    dev builds markup literals (styles, numbers, colours, strings) read from
    a table keyed by their source position, which the CLI patches when an
    edit changes only literals; an inspector's or a control's edit written
    back to the source the same way;
  - **an MCP server in the CLI** over the same protocol (inspect, set,
    stories, a screenshot), so an agent sees and checks a running program,
    its edits ordinary diffs;
  - Chrome-trace or Tracy files exported until the timeline is drawn in ui.

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
- **Devices in the devtools**: their logs, a screenshot or a recording, a
  story picked on the phone.

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
- **Games in the devtools**: stories for scenes (a world at a set point,
  its seed, camera and fixed step: deterministic, paused, stepped, scripted
  input), a scene inspector, debug drawing, GPU timings ("open in
  RenderDoc" on desktop), input recorded and replayed; the program's panel
  as a separate process sharing its frames as a GPU texture (as Makepad
  Studio: IOSurface, a DXGI shared handle, dmabuf), so a crash leaves the
  devtools running.

### 6. Editor

- **A VS Code extension**: the language server, syntax highlighting, and
  support for view's markup.
  The devtools in it as a webview (it is a page already), jumping to
  source from spans and markup nodes; `.test.hx` and `.story.hx` files
  mapped for the display server.

## License

MIT (LICENSE).
