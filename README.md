# helder

An experimental stack for building games and apps in Haxe, for desktop,
mobile and the web, from one npm package. Built on
[hxmc](https://github.com/benmerckx/hxmc), the Haxe compiler with a native
and WebAssembly target. **Unstable**: APIs change without notice.

The goal (desktop and web work from this checkout: `bun run helder ...`,
src/helder/cli/README.md; the rest is on the roadmap):

```sh
npm install helder
npx helder dev            # this machine, with live reload
npx helder dev web        # a page, with live reload
npx helder build          # bin/<target>/<name>, its compile time and size
npx helder inspect --tree # a running dev build's ui tree (--log, --frames)
npx helder dev android    # (to come) boots an emulator, installs, live reloads
npx helder build ios      # (to come)
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
  reused between calls, or off-heap buffers for data handed to a GC-free
  job. User code sits on top as ordinary Haxe with the GC, and should not
  have to know.
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
| `view` | signals and JSX-like markup, compiled to direct calls on the renderer each subtree's tag chooses |
| `ui` | flexbox layout, events, focus and accessibility, drawn on gfx or as the platform's controls |
| `web` | `view` on the web: DOM and static renderers, hydration, islands |
| `scene` | 3D on gfx: glTF, a PBR renderer, animation, input actions |
| `physics` | a small rigid-body core for `scene` |
| `async` | a loop per thread for Haxe 5's coroutines: tasks, timers, TCP, child processes, file watching, an HTTP and WebSocket server; the browser's loop |
| `dev` | the dev host and state kept across a reload |
| `devtools` | the devtools protocol (JSON-RPC on the dev connection) and its agent in dev builds: log, frame stats, the ui tree |
| `test` | tests as bun writes them, without macros: `describe`, `test`, hooks, assertions as functions, async tests on `async`'s loop; `helder test` runs the `*.test.hx` files |
| `cli` | the `helder` command, a native program on `async`: `dev`, `build`, `run`, `test` and `inspect`, for desktop and the web |

`examples/` has a program per folder; `tests/Run.hx` has the checks, and
the `*.test.hx` files are helder.test's, run by the CLI built from this
checkout (bin/cli/helder, rebuilt when its sources change):

```sh
bun install
bun run test              # the lanes that need no GPU, display or browser
bun run test help         # every lane
bun run helder test       # the *.test.hx files (--target all, --watch, -t <name>)
bun run helder dev examples/counter/Counter.hx   # an example, live (dev web: a page)
```

## Roadmap

In order: each phase leans on the one before it.

### 1. Cleanup

- **Fix the references the restructure left behind** in `tests/`: comments
  there still point to `docs/`, `packages/`, `make` and `npm test` (`src/`
  is done).

### 2. Async core, then the CLI on it (desktop and web)

Done as a first slice:

- **`helder.async`** (src/helder/async/README.md): a loop per thread for
  Haxe 5's coroutines, tasks with structured concurrency and cancellation,
  timers, TCP, child processes, an HTTP and WebSocket server natively, the
  browser's loop on the web, I/O behind a completion-based backend
  (poll(2) natively: sockets, pipes, Linux's pidfds; select on Eval);
  processes with a working directory, an environment and signals, the
  process's own SIGINT and SIGTERM on the loop; file watching as esbuild polls (`SampledWatcher`: what the
  last build read, the hot files every 100 ms, the rest sampled, 2.3 ms a
  tick for 10k files) and a whole-tree `PollWatcher`.
- **The `helder` CLI** (src/helder/cli/README.md), a native program on it,
  run from this checkout by `bun run helder`:
  - `helder dev`, `build` and `run` for the host and `web`, `build` for any
    hxmc target; an entry is a project (package.json, `src/Main.hx`), an
    example's directory or a file (`helder dev examples/counter/Counter.hx`);
  - hxmc's native compiler called directly (no node), its std and runtime
    objects given by the CLI; a resident compilation server for dev, its own
    process (the GPL compiler not linked into the MIT CLI), stopped with the
    CLI (SIGTERM, then SIGKILL);
  - the dev loop ported from hxmc's `dev.mjs`: a failed build keeps the last
    good one running; natively each build a library (.so on Linux, a DLL on
    Windows, a dylib on macOS) swapped into the dev host's process (the
    window and the GPU device or context kept: no new window per edit), a
    restart with a snapshot when the host does not build or with
    `HELDER_DEV_HOST=0`; on the web the module swapped in the same page;
    save to reload about 300 ms natively, 400-440 ms on the web;
  - every build's compile time and binary size reported; warm builds of the
    examples 185-575 ms;
  - conventions over configuration: package.json's `"helder"` key and a
    `helder.hxml` beside it as the overrides; every example built by
    `helder build <file>` with no flags (the examples lane).
- **`helder test` and `helder.test`** (src/helder/test/README.md): the
  `*.test.hx` files under `src/`, `tests/` and the class paths, linked into
  bin/test/src (Haxe takes no dot in a module's name), one generated main,
  built once, run on the host, Eval or wasm32-wasi (`--target all`), paths
  written back as the real files'; `-t`, `--watch`, `-u` for text
  snapshots. The library has no macros: `describe`, `test` (`.skip()`,
  `.only()`, `.timeout()`), hooks, `async(coroutine)` bodies, `assert`,
  `equals` (deep, both values shown), `notEquals`, `approx`, `throws`,
  `require`, `fail`, `snapshot`.
- **One message format on the dev connection**
  (src/helder/devtools/README.md): JSON-RPC 2.0, versioned by a
  `Runtime.hello` exchange, methods in domains enabled per tool:
  - `Runtime` (hello, reload as a request answered once saved, ready,
    state: the keys `Hot` keeps and dropped; the CLI's built, buildError,
    reloaded, connected, exited), `Log` (traces with their positions, the
    program's output and the builds' errors, the last 500 kept by the CLI
    for a tool that comes late), `Frame` (time, work, GC bytes, collections
    and pauses per frame, 10 batches a second, no garbage per frame:
    50 ns enabled, 0.4 ns disabled), `Ui.getTree` (a hook helder.ui
    registers);
  - the agent in dev builds only (27 KB; a release build unchanged, byte
    for byte), `helder dev` as the relay (a WebSocket at
    `/__helder/devtools` on its HTTP port, natively too, named by
    bin/dev/devtools.json), `helder inspect --tree --log --frames --state`;
  - @hxmc/cli's `{"type"}` lines still spoken to a program its `dev.mjs`
    runs; the `devtools` lane, headless.

- **hxmc's fixes in a nightly** (@hxmc/cli 0.1.0-nightly.20261027.ec71785,
  hxmc 8841f02), their workarounds removed: processes' cwd, env and signals
  and nanosecond mtimes (#81), sockets' connect and `poll` (#79, the
  native backend), allocation-free IntMap, resize and short sorts (#84,
  where as fast), `GcStats` (#85), `Blocking` and `IoBuffer` (#86), a
  `--wait` server kept by an empty connection; WasmGC's lanes removed
  (hxmc drops it). Still to come in a nightly: `Timer.stamp`'s size (#89);
  the platform package's compiler finding its runtime objects alone (the
  CLI gives HXMC_RT_DIR).

Still to come:

- **The dev loop:** changed assets sent without a recompile, assets packed
  by `build`; the dev host on Windows and macOS run on the machines
  themselves (tested on Linux: cross-compiled, Windows' under Wine with
  D3D11 on WineD3D, macOS's built only); the page held back while the
  module is generated;
  macro-only modules in the watched set.
- **The dev connection's protocol, the rest**: the agent on the web (the
  page relaying between the module and the WebSocket; only the log today),
  the other domains (`Scene`, `Signals`, `Profiler`, `Assets`, `Stories`)
  and libraries' own (as Godot's debugger; `Agent.method` is the hook), get,
  query and set on properties (as Bevy's BRP), profiler samples as a binary
  stream, node ids kept across reloads, `Runtime.evaluate`.
- **Packaging:** the CLI on npm as a binary, one optional dependency per OS
  and CPU (`@helder/<os>-<cpu>`, as `@hxmc/<os>-<cpu>`); name, version and
  app id from package.json into the builds; the examples laid out as
  projects, each reloaded in CI. `helder new` and `helder doctor` wait;
  Android and iOS are phase 4.
- **Tests:** the rest of `tests/` moved to `helder.test`, golden images
  beside snapshots, `--target web` (Chromium); editor support for
  `.test.hx` files (the display server takes `Foo.test.hx` for the module
  `Foo`: no diagnostics, hover or completion); a macro later (`@:test`
  collection, an `assert` showing its values).
- **`helder.async`'s backends:** io_uring on Linux (poll where it is
  disabled: Android apps, some containers), kqueue on macOS, IOCP on
  Windows, on hxmc's `IoBuffer` and `@:hxmc.blocking`; a process's exit
  without polling on macOS (Linux: its pidfd, done); Windows' pipes
  without threads; macOS and Windows run.


- **Renderers as tags in markup**, react-three-fiber's `<Canvas>` model
  (src/helder/view/README.md): done as a first slice. No define names a
  renderer: a literal is compiled when typed, for the renderer that owns
  it (the tag around it, `Render.render`'s parent, a `ViewOf<R>` expected
  or returned), or for each renderer the program reaches; only those get a
  runtime. A component pinned to another renderer, a root in a renderer's
  markup, an element a renderer does not list are compile errors at the tag.
  - **`<Surface>`** (`UiWindow.run(<Surface ...>)`): a window natively, its
    props reactive, several for several windows; on the web a canvas
    filling the page, or the canvas a page gives it. In a page's markup
    (DOM or static) helder.web's `<Surface>` is a `<canvas>` the page's
    styles size (a ResizeObserver) running a wasm ui program, an island in
    a static page.
  - **`<Scene>`**: a box in ui's layout drawing scene nodes (its world into
    a texture of its size, before ui's pass); ui's pointer events picked in
    the scene (bounds) and given to the scene nodes' listeners. **`<Ui>`**:
    back to ui over a scene node.
  - Every example built by `helder build <file>`, natively and for web,
    with no flags; the defines, the CLI's and the tests', are gone.

  Still to come: warm builds of a program with markup 0.2 s slower (every
  runtime and the late code made by macros each build, where the module
  cache served them before: runtimes as modules of their packages, the late
  code from the cache); late code kept whole by DCE natively (on JavaScript
  per literal); `<Surface>` on phones; `<Ui>` laid out a frame late and
  without its own events past ui's; picking against triangles; the scene's
  feature pipelines (skins, normal maps, the sky) in a `<Scene>`'s target;
  `<Dom>`/`<Html>` (not needed yet: a page's markup is the DOM's or static
  HTML's by where it is mounted); `<Page>` (static sites keep
  `Static.document(<html>...)`, a StaticRenderer literal: a tag adds nothing
  until a server renders pages).

- **TypeScript for apps (optional, after the boundary tags)**: end users
  write their app in TS/TSX; helder itself stays Haxe, and the output is
  hxmc's, native or wasm, with no JavaScript in it.
  - **A `helder` ts frontend** the CLI runs when a project's entry is
    `src/main.ts(x)`, on TypeScript 7.1's API (`typescript/sync`, a client
    of the Go compiler; node at build time only): the program checked by
    TypeScript, each module emitted as Haxe into `bin/ts/`, hxmc compiling
    it as any helder program; `helder dev` feeds its watcher's changes to
    the API's snapshots (`snapshot.update`, `fileNotifications`) and
    re-emits only what changed; errors and stack traces mapped back to the
    `.ts` lines, as `.test.hx` paths are.
  - **TSX as helder.view's markup**, typed against helder's elements and
    compiled by its macros to direct calls on signals, no virtual DOM;
    `<Scene>` in TSX once scenes take markup.
  - **helder's API as `.d.ts` files** in the npm package, generated from the
    Haxe API when helder is published (a `.hx` content mapper, TypeScript
    7.1's plugin point, only if apps mix their own `.hx` files in).
  - **A generous subset**, since app code is GC code: classes, functions,
    interfaces as anonymous structures, unions as generated enums,
    `async`/`await` on `helder.async`, `number` as `Float` (an `i32` alias
    for `Int`); refused: `any` spread through code, mapped and conditional
    types beyond what Haxe can express, prototypes changed at run time.
    Shaders in TS (to Haxe shader classes) later, for games.
  - A proof first: the `.d.ts` for view and ui, the emitter, the counter
    and todo examples in TSX built and live-reloaded by `helder dev`; started
    once TypeScript 7.1's API is out of beta.

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
  - **two tiers of jobs** ([measured](tests/bench/results/jobs.md)):
    GC-free jobs, `@:hxmc.unsafe` functions over off-heap buffers (hxmc's
    `IoBuffer`), run in a safe region (`hxmc.unsafe.Blocking`) the
    collector never waits for: the default for the engine (decoding,
    physics, pathfinding). And ordinary GC jobs for user code: on the web
    isolates, natively only for short loops, since a collection waits for
    a GC job's longest loop without allocation (35-55 ms for a 4K PNG);
  - **channels** between threads carrying values that can be sent (checked
    by a macro, as Swift's `Sendable`): flat values, hxmc structs, Strings
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
- **`helder.scoped`: not needed, archived.** It lost or tied against GC buffers in
  text and physics, and as a GC-free job's memory it lost to off-heap
  memory: decoding a 4K PNG took 240 ms against 169, the variant added
  149 KB of code against 4, it needed the checker (1.8 s builds against
  1.0), its job's freedom from the GC went unchecked, and its pixels could
  not cross threads ([results](tests/bench/results/jobs.md)). Archived:
  removed from the tree, kept under the tag `archive/scoped`.
- **Prototyped, and what it decided** ([results](tests/bench/results/jobs.md)):
  a 4K PNG decoded while the main thread renders 60 fps.
  - Between frames, the decode is one frame of 224 ms natively, 443 ms on
    wasm32.
  - As a GC job, it made the main thread's collections wait 35 ms (up to
    55): the 1 ms bar fails, so the engine uses GC-free jobs.
  - As a GC-free job in a safe region, on scoped or off-heap memory, the
    longest pause is 0.3-0.6 ms, as with no job; without the region, 176-235
    ms.
  - On wasm32, a worker instance leaves the frames alone; the pixels cost
    the main thread one 15 ms copy into its memory, avoidable by uploading
    from the transferred buffer.
  - Still to do: the main loop with the next frame, then one worker on
    the web. (Upstream's hxcoro or a runtime of our own: our own,
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
    frame, tree snapshots on request, commands, pick and highlight. Its
    protocol is there (phase 2: src/helder/devtools/README.md, frame stats,
    the log and the ui tree), and `helder inspect` a small client of it;
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
  `helder.scene.view` (a prototype: `<Scene>` in ui's layout, `<Ui>`, picking
  by bounds; examples/planets, tests/3d-ui):
  - the tags generated from the 3D API's classes, their props its
    properties, so markup and code stay one API;
  - bindings that store into the scene's flat data; signals' changes
    applied once per frame, before rendering;
  - markup for structure, not for every value that moves: an `onFrame`
    that writes the nodes it is given, and instancing elements with their
    per-instance data in flat arrays (particles, crowds, foliage);
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
