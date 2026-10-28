# helder

An experimental stack for building games and apps in Haxe, for desktop,
mobile and the web, from one npm package. Built on
[hxmc](https://github.com/benmerckx/hxmc), the Haxe compiler with a native
and WebAssembly target. **Unstable**: APIs change without notice.

The goal (desktop and web work from this checkout: `bun run helder ...`,
src/helder/cli/README.md; the rest is on the roadmap):

```sh
npm install helder
npx helder dev                    # this machine, with live reload
npx helder dev --target web       # a page, with live reload
npx helder build                  # bin/<target>/<name>, its compile time and size
npx helder inspect --tree         # a running dev build's ui tree (--log, --frames)
npx helder devices                # where it can run: this machine, a browser, phones
npx helder build --target android # an APK, signed with your debug key (no SDK)
npx helder dev --target android   # on the device or emulator adb reaches: installed once, live reloads
npx helder run --target ios       # on the booted iOS simulator (macOS)
```

`helder <command> [entry] [options]`: the entry (a .hx file, a directory or
a project; the default: .) is what is built, the flags where it runs:
`--target` (host, web, android, ios, ios-sim or an exact hxmc target), `-d` (which
phone, emulator or simulator), `-o` (the output), `--` (the program's
arguments). `helder <entry>` is `helder dev <entry>`.

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
- **Tools in the box.** A VS Code extension (and the same panels as pages
  `helder dev` serves, for other editors) puts the program's assets,
  stories, inspectors and profiler beside the code, on every platform, and
  shows what the allocation-free core promises: the garbage of every frame.

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
| `jobs` | background work awaited from a coroutine: GC-free jobs and GC jobs on a pool's threads or a browser's workers, channels, the sendable check |
| `dev` | the dev host and state kept across a reload |
| `devtools` | the devtools protocol (JSON-RPC on the dev connection) and its agent in dev builds: log, frame stats, the ui tree |
| `test` | tests as bun writes them, without macros: `describe`, `test`, hooks, assertions as functions, async tests on `async`'s loop; `helder test` runs the `*.test.hx` files |
| `cli` | the `helder` command, a native program on `async`: `dev`, `build`, `run`, `test` and `inspect`, for desktop, the web, Android and iOS |
| `pack` | Android's APKs and iOS's app bundles around hxmc's native code, without an SDK: zip, binary XML, DEX, v2 signing (P-256), the debug key; Info.plist, CodeResources, .ipa |

`examples/` has a program per folder; `tests/Run.hx` has the checks, and
the `*.test.hx` files are helder.test's, run by the CLI built from this
checkout (bin/cli/helder, rebuilt when its sources change):

```sh
bun install
bun run test              # the lanes that need no GPU, display or browser
bun run test help         # every lane
bun run helder test       # the *.test.hx files (--target all: host and wasm, --watch, -t <name>)
bun run helder examples/counter/Counter.hx       # an example, live (helder dev; --target web: a page)
```

## Roadmap

In order: each phase leans on the one before it. Now: phase 4, a mobile 3D
game; the editor integration (phase 3's VS Code extension) and sound wait
until after it.

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
    hxmc target; one grammar, `helder <command> [entry] [options]`: the
    positional is what is built, never a target (a project, package.json and
    `src/Main.hx`, an example's directory or a file:
    `helder dev examples/counter/Counter.hx`; `helder <entry>` is dev's), the
    flags where it runs (`--target web`, `--target windows-x86_64`, `-d`
    for a phone: phase 4), `-o`, `--`;
    `helder devices` lists this machine, the browser, adb's devices and
    emulators, iOS's simulators;
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
  - closing the program's window ends `helder dev` (an exit code of 0, as
    `tauri dev` and electron-forge do); a crash keeps it up, waiting for a
    change to build and start it again; closing a page does not (vite's);
  - cargo's, bun's and vite's look: a header line, aligned status verbs
    (built, reloaded, failed, crashed) with their times, the compiler's
    errors with file:line:column in front, a spinner, `helder test` with
    ✓ and ✗; plain text without a terminal, with `NO_COLOR` or `TERM=dumb`
    (`FORCE_COLOR` forces colours);
  - every build's compile time and binary size reported; warm builds of the
    examples 185-575 ms;
  - conventions over configuration: package.json's `"helder"` key and a
    `helder.hxml` beside it as the overrides; every example built by
    `helder build <file>` with no flags (the examples lane).
- **`helder test` and `helder.test`** (src/helder/test/README.md): the
  `*.test.hx` files under `src/`, `tests/` and the class paths, linked into
  bin/test/src (Haxe takes no dot in a module's name), one generated main,
  built once, run on the host or wasm32-wasi (`--target all`; Eval only
  for the files that opt in, `@:test.interp`: compile-time code), paths
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
    60 ns enabled, 0.4 ns disabled), `Ui.getTree` (a hook helder.ui
    registers);
  - the agent in dev builds only (27 KB; a release build unchanged, byte
    for byte), `helder dev` as the relay (a WebSocket at
    `/__helder/devtools` on its HTTP port, natively too, named by
    bin/dev/devtools.json), `helder inspect --tree --log --frames --state`;
  - @hxmc/cli's `{"type"}` lines still spoken to a program its `dev.mjs`
    runs; the `devtools` lane, headless.

- **hxmc's fixes in a nightly** (@hxmc/cli 0.1.0-nightly.20261027.a4195c7),
  their workarounds removed: processes' cwd, env and signals and
  nanosecond mtimes (#81), sockets' connect and `poll` (#79, the native
  backend), allocation-free IntMap, resize and short sorts (#84, where as
  fast), `GcStats` (#85), `Blocking` and `IoBuffer` (#86), a `--wait`
  server kept by an empty connection; WasmGC's lanes removed (hxmc drops
  it, #90); `haxe.Timer.stamp` without the event loop, hxmc's std
  overrides trimmed by DCE (#89: the devtools agent and helder.test on
  `Timer.stamp` again; native builds 100 to 210 KB smaller: Todo 2042 to
  1849 KB, Planets 2438 to 2234, Counter 1663 to 1499, Walker 708 to 607,
  a one-test `helder test` 297 to 262; wasm32 4 KB smaller); the platform
  package's compiler finding its runtime objects beside itself (#93: the
  CLI no longer gives HXMC_RT_DIR).

Still to come:

- **Assets anywhere, bundled by use:** no `assets/` folder; code names a
  file by its path (`Asset.image("ui/icons/sword.png")`), a macro checks it
  exists and records it, and `helder build` bundles only what is referenced
  (dead-code elimination for assets), each in its target's format; settings
  that differ from the defaults in a sidecar (`sword.png.meta`); dev builds
  read them from disk and a change is sent without a recompile (the running
  program's texture, font or model reloaded);
- **The dev loop:** the dev host on Windows and macOS run on the machines
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

  Still to come: warm builds of a program with markup still a little slower
  than before (every runtime and the late code made by macros each build;
  hxmc da5aa2b's #94 took Todo's warm build from 0.76 to 0.55 s, the late
  code from the cache waits on hxmc's "one cache" rewrite); late code kept whole by DCE natively (on JavaScript
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
  - **the main loop driven by `App.run`** (done, a first slice:
    src/helder/async/README.md, "The loop"): a turn of it in each of the
    app's, after the events and before the frame; X11's wait polls the
    loop's descriptors and its wake pipe with the connection's, bounded by
    its timers (a timer or a job's reply ends an idle `App.wait(1)` within
    0.5 ms: the `app` lane); Cocoa, Win32, Android and UIKit wait at most 10
    ms while I/O or a post may come; the page turns the loop between frames
    and while there are none (a hidden canvas: the `jobs-web` lane). Left:
    the OS loops watching the descriptors themselves (CFFileDescriptor,
    MsgWaitForMultipleObjects with an event, ALooper_addFd) instead of the
    10 ms bound;
  - **scopes owned by the app**, children cancelled with their parent;
  - first on it: `Fetch` (an awaitable one exists, `helder.os.Fetch` to
    follow), the next frame, asset loading.
- **Background work as jobs on workers**, the same API natively and on
  the web (done, a first slice: `helder.jobs`, src/helder/jobs/README.md;
  `Jobs.run(f, input)` awaited from a coroutine, a GC-free job's output an
  IoBuffer handed back without a copy natively and transferred on the web,
  errors as `JobError`s, cancellation through the task; a 4K PNG through
  it: frames' max 5.8-6.4 ms and longest pause 0.5-0.6 ms natively, 9.6
  and 4.4 ms on wasm32's workers, as with no job; a round trip 28 µs
  natively, 45-53 µs on wasm32. Left: channels toward a worker, enums as
  sendable values, files in a browser's worker, SharedArrayBuffer as a fast
  path):
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
    natively, transferred on the web). Done for a first slice: `Channel<T>`
    from any thread or job to the loop of the thread that made it;
    anonymous structures and Arrays of these are sendable too (copied).
  - **first user: image decoding** (done): helder.image's one PNG decoder,
    `PngCore`, is `@:hxmc.unsafe` over native memory, the same code
    `PngDecoder` runs on the calling thread and `ImageJobs` as a GC-free
    job (every colour type, depth, Adam7, APNG's frames; the old decoder
    removed: 1.4x faster, a quarter of the garbage, 83 KB smaller). Left:
    JPEG, GIF and WebP still decode on the calling thread, and scene's
    `Images` hook is synchronous (textures made as a model loads).
  - **next: text's shaping and glyph rasterizing**, the spiky part of
    text (a cold atlas about 5 ms; a relayout of 10k nodes is 0.008 ms): a
    new paragraph shaped and its glyphs drawn into the atlas as GC-free
    jobs, the result a frame later or a fallback glyph meanwhile, as
    browsers and games do for fonts. The plan, as PNG's: `Rasterizer`'s
    coverage and an outline's flattening over `Raw`-like memory, one
    implementation for the atlas's warm path and the job; a font's bytes in
    an IoBuffer the jobs share read-only (natively one copy, in a browser
    one per worker); `GlyphAtlas.get` of a cold glyph queues it and answers
    a fallback (the glyph at a size it has, scaled, or a blank of its
    advance), a frame's queue one job (the outlines flattened on the main
    thread, cheap), its bitmaps placed when it is back and the atlas's
    version bumped, so that a renderer uploads them; TextLayout needs no
    pixels (its metrics are the font's). Shaping as a job after it.
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
  - Done since: the main loop with the frames, workers on the web,
    `helder.jobs` (above). (Upstream's hxcoro or a runtime of our own: our
    own, `helder.async`, which hxcoro's tasks run on.)
- **The devtools as a VS Code extension** (design from a study of Unity's,
  Unreal's, Godot's, Defold's and Bevy's tools, Flutter DevTools, Tracy,
  Storybook, Makepad Studio and Bezi). The editor already has the file
  tree, tabs, the code, a terminal, problems, search and a test explorer;
  helder adds what is its own, organised around the files as Defold's editor
  is. Cursor and Windsurf run it too. Its panels are pages served by
  `helder dev`, drawn by helder's ui as wasm (dogfooding), shown in VS
  Code's webviews and openable in a browser, so other editors (JetBrains,
  Zed, Neovim) get them as pages beside the protocol, `helder inspect` and
  the MCP server. Scenes and ui stay markup in `.hx` (no scene format of its
  own, as Defold's `.gui` and `.collection`): stories preview them, and an
  inspector's edit writes back to the literal.
  - **Commands and tasks**: dev, build, test, the target; build errors in
    the problems panel; `helder test`'s files and results in the test
    explorer, a failure's line a click away.
  - **Language support** on the Haxe extension (vshaxe): view's markup
    highlighted in `.hx`, `.test.hx` and `.story.hx` mapped for the display
    server (today they have no diagnostics, hover or completion), jumping to
    source from inspector nodes and profiler spans.
  - **Custom editors per kind of file**, wherever it is in the tree: an
    image's preview, its settings per target and the code using it (bundled
    or not); a glTF's viewport and node tree; a font's specimen; audio's
    waveform; a story file's stories with their controls; edits to settings
    in a sidecar (`.meta`), reloaded live.
  - **The program**: its own window natively (kept by the dev host across
    reloads), a web build in a webview, a phone attached through the CLI
    (which holds every build's connection, and outlives a crash with its
    logs).
  - **An agent in dev builds only** (`-D hxmc.dev`, as `Hot`; a few tens of
    KB): counters and spans that do not allocate, GC bytes and pauses per
    frame, tree snapshots on request, commands, pick and highlight. Its
    protocol is there (phase 2: src/helder/devtools/README.md, frame stats,
    the log and the ui tree), and `helder inspect` a small client of it.
  - **Stories**, as Storybook's: `Foo.story.hx` files anywhere (linked as
    `.test.hx` files are) whose `stories()` registers
    `story("Inventory/full", c -> ...)`, built into dev builds only; controls
    are signals (`c.number`, `c.bool`, a choice, a colour), so an edit
    updates only what is bound; the story and its controls kept across a
    reload; a story is a test too, rendered headlessly by `helder test`
    against a snapshot (an image, or the tree as text), with a scripted
    interaction and assertions.
  - **Panels**: the inspector (the ui tree with layout, styles and
    accessibility, signals and view's graph, each node traced to its markup
    line; the state a reload kept and dropped); the profiler (frame time,
    spans, GC bytes per frame split into the engine's and the program's);
    the console; pause and step.
  - **Literals edited without a recompile**, as Makepad's live design: in
    dev builds markup literals (styles, numbers, colours, strings) read from
    a table keyed by their source position, which the CLI patches when an
    edit changes only literals; an inspector's or a control's edit applied
    as an edit in VS Code (its undo works).
  - **An MCP server in the CLI** over the same protocol (inspect, set,
    stories, a screenshot), so an agent sees and checks a running program,
    its edits ordinary diffs.
  - Chrome-trace or Tracy files exported until the timeline is drawn in a
    panel.
  - **First slice**: the extension with the commands and the test explorer;
    the `.test.hx`/`.story.hx` mapping and markup highlighting; the image
    editor (once assets are referenced by path); the console and frame
    stats over the protocol. Then the stories editor, the inspector with
    jumping to source, the glTF and font editors.

### 4. Mobile, and a first game: a mobile 3D game

Next, ahead of sound and the editor integration (phase 3's VS Code
extension, which waits until after the game). The game itself is the
driver: built as an example, on a phone, every rough edge it hits the next
fix.

- *Landed*: **packaging moved from hxmc into helder** (`helder.pack`,
  ported with its tests, MIT): app-level and bound to change a lot
  (manifests and plists, permissions, orientation, icons, assets bundled
  by use, debug and release signing, AAB), so helder's CLI owns it and
  hxmc's output ends at native code (Android's `libmain.so`, iOS's signed
  Mach-O, `-D hxmc.codesign-*` binding the bundle's files). `helder build
  --target android` (an APK: manifest, classes.dex when the program needs
  it, 16 KB aligned, v2-signed with the user's debug key, now made from
  the system's random source on Windows too, under helder's names:
  `HELDER_ANDROID_KEY`, helder's cache), `--target ios` (an .ipa) and
  `ios-sim` (an .app, ad hoc signed); `helder run` on a device, emulator
  or simulator (`-d`, else the one there is). Android's runtime objects,
  not on npm, fetched on first use from the hxmc release @hxmc/cli's
  package.json names (`hxmc.rt`) into helder's cache, then given to the
  compiler as `HXMC_RT_DIR`. Tested on Linux without a
  device (the `pack` lane: the outputs checked structurally, the v2
  signature recomputed and verified by openssl, the Mach-O's signature
  slots; `helder run` and `dev` against stand-in adb and simctl); on an
  emulator and a simulator only in CI, untested until it runs. Next:
  hxmc removes its copy. Later: iOS device signing (a certificate and a
  profile, through `codesign` on a Mac), release signing, icons and
  assets.
- *Landed*: **`helder dev --target android` and `--target ios`**: a
  connected device or a running emulator (`-d`, from `helder devices`),
  or a simulator, booted for it when it is not; the dev host's app
  installed once, each build swapped into it (Android: its library
  fetched by the app over `adb reverse` and loaded in the same process;
  the simulator: a dylib it loads from the Mac's disk), as the desktop's
  dev host does. Closing the app on the phone does not end `helder dev`
  (helder.cli.ExitPolicy's Mobile: it keeps serving, the next build
  installs and starts the app again). Tested against stand-ins for adb and
  simctl (tests/pack/dev.mjs); on an emulator only in CI
  (tests/os/dev/dev-android.mjs), untested until it runs. Later: booting
  an emulator for it.
- *Landed*: **`<Surface>` on phones**: the safe area on both
  (`Window.safeTop`... in pixels: iOS's `safeAreaInsets`, Android's
  window insets through JNI, API 30's `getInsets(systemBars |
  displayCutout)` or API 29's system window and cutout insets; a `Resize`
  when they change), in ui as CSS's `env(safe-area-inset-*)` in markup's
  literal attributes (with `calc()`, `max()`, `min()`; bound to
  `SafeArea.insets`, laid out again when they change), `Ui.safeArea`, and
  `SceneBox.safeArea()` for a scene's HUD; `Window.scale` (Android's
  density, iOS's `nativeScale`, a `ScaleChange` when the configuration
  changes it); `Window.immersive` (Android's immersive mode, iOS's status
  bar and home indicator hidden); package.json's `"orientation"`
  (portrait, landscape, any: the manifest's `screenOrientation`, the
  plist's `UISupportedInterfaceOrientations` and `UIRequiresFullScreen`)
  and `"fullscreen"` (`-D helder.fullscreen`, `UIStatusBarHidden`); a
  rotation resizes the surface through the existing `Resize`. Tested: the
  options' manifest and plist (`App.test.hx`, `Apk.test.hx`,
  `Bundle.test.hx`; the pack lane's PackCheck on the built APK and app:
  `screenOrientation`, the orientations, the define reaching the
  program), `env()` and its binding (`SafeArea.test.hx`, natively and as
  wasm32-wasi); on CI's emulator (a Pixel 6, API 34) and simulator
  `tests/pack/Screen.hx` (tests/pack/screen.mjs): the window's size and
  scale (the Pixel 6's 2.625, the iPhone 17's 3), the insets (Android:
  the navigation bar's 126 px at the bottom; iOS: the island's 186 at the
  top, the home indicator's 102 at the bottom), immersive on Android (the
  bars' inset gone, the window into the camera's cutout: its 128 px at the
  top), a rotation on Android (wider than high, the cutout at the side).
  Not checked anywhere yet: the simulator's rotation (simctl has no
  command for it), immersive's effect on iOS's safe area (none on the
  island's iPhone), a ui drawn on a phone with the insets applied. Later:
  `env()` in runtime-set attributes and in sheets' rules, the keyboard's
  inset kept apart from the bars'.
- *Landed*: **the frame loop from the display**: Choreographer
  (`AChoreographer_postFrameCallback64`, NDK only, on the program's own
  looper: `helder.os.android.Vsync`) on Android, a `CADisplayLink` on
  iOS (its callback stops the run loop's wait); `App.run` asks for the
  next vsync only while a frame may be drawn, sleeps until it comes, and
  draws with `App.frame` (a `FrameClock`: the vsync's time in
  `haxe.Timer.stamp()`'s seconds, the delta, the display's period); an
  idle frame (`App.wait`) asks for none until it has slept; the
  background, a lost window and an inactive app (`onPause`, the window
  destroyed; `willResignActive`, `didEnterBackground`) ask for none, the
  first frame after them a period's delta. Tested: `FrameClock.test.hx`
  (natively and as wasm32-wasi: 60 and 120 Hz, a missed frame, a pause,
  nothing allocated); on CI's emulator and simulator the fixture's first
  frames vsyncs, 120 of them at the display's pace (16.67 ms on both)
  with nothing allocated, Suspend and Resume and the first
  frame after (the delta a period); desktop and web keep their loops
  (`App.frame` from the turn's start: the gfx, ui-draw, app and browser
  lanes). Later: ProMotion's 120 Hz (`preferredFrameRateRange`,
  `CADisableMinimumFrameDurationOnPhone`), Android's frame rate API.
- **Multi-touch and gestures**, after a study of the platforms' and
  engines' models (web Pointer Events, Android MotionEvent, UIKit's touches
  and gesture recognizers, Flutter's gesture arena, Unity's Input System,
  Godot), in four steps:
  1. *Landed*: one pointer stream in `os` (`Pointers`: mouse, touch, pen;
     dense ids, phases, cancellation, coalesced samples; per event and per
     frame, allocating nothing; `emulate` keeps a touch's old click and
     scrolls). Tested natively (no allocation) and in Chromium (fingers,
     a pen, the mouse); Android's and iOS's back ends are written and
     compile, not run on a phone yet (CI's emulator and simulator jobs
     come first).
  2. *Landed*: ui's pointers (fingers and pens with ids, capture and
     `releaseCapture`, `onPointerCancel`, `onLostPointerCapture`; a tap
     clicks, the first finger's drag scrolls in ui itself; a press on
     ui's own nodes marks the pointer the ui's), a `<Scene>` picking at
     each pointer's press only (the node hit owns it), one `SceneEvent`
     per box. Tested natively and as wasm32-wasi
     (`src/helder/ui/Pointers.test.hx`), the todo's touch drag, flick and
     tap in Chromium (ui-web).
  3. *Landed*: touch in scene's input actions (`Touch(zone)`,
     `TouchDelta` look zones, `VirtualStick` floating or fixed,
     `VirtualButton`, a press owned by its control until it lifts, ui's
     presses left alone, cancels letting go; `<Stick>` drawn in ui), read
     once a step from `Pointers` with nothing allocated. Tested natively
     and as wasm32-wasi (`TouchActions.test.hx`), `<Stick>` under Xvfb.
  4. *Landed*: gestures in ui competing for each pointer (an arena:
     `Tap`, `Pan`, `Scale`; `onTap`, `onPan`, `onPinch`, `onScale` in
     markup; a recogniser that wins takes the click), `onTap` on scene
     nodes and `<OrbitControls>` for a `<Scene>`'s camera (one finger
     turns it, two pinch about their centre, move and twist it; the mouse
     and the wheel too; a glide). Tested natively and as
     wasm32-wasi (`Gestures.test.hx`, `OrbitControls.test.hx`), a tap and
     an orbit over a GPU's `<Scene>` under Xvfb.

  Tested where: the desktop (Linux, natively, and its GPU under Xvfb)
  and the browser (wasm32-wasi in headless Chromium, touches and pens
  through the DevTools protocol); Android's and iOS's back ends are
  written and compile, not run on a phone yet. Later:
  long press, double tap and `waitFor`, rotate alone, `touch-action` on
  nodes, pen tilt and pressure in use, prediction, Windows' and X11's
  touch screens, macOS's trackpad gestures (magnify, rotate).
- **Assets by path, bundled into the APK and the app** (phase 2's "assets
  anywhere, bundled by use"), read through one API on every platform.
- **The game**: a small mobile 3D game as an example (a camera the fingers
  drive, picking, a HUD and a menu in ui, a save), built and live-reloaded
  on an Android device and the iOS simulator. Save data (a small store on
  every platform, the web's included) and tweens for gameplay come with it.
- *Landed*: **CI on an Android emulator and the iOS simulator**: the
  `android` job (a Pixel 6's emulator, API 34: hello through `helder
  run` and adb, the screen fixture, Android's dev loop) and the
  `ios-simulator` job (the newest iPhone's simulator: hello through
  `helder run`, the screen fixture), green, not required.
- Later in this phase: **audio** (decoders: WAV, Ogg Vorbis; a mixer above
  every back end, running as a kernel; AAudio on Android, RemoteIO on iOS;
  a simple `Sound.play`), **a compositor thread for scrolling and
  animations**, so a busy main thread does not show (as Ladybird's
  compositor, Core Animation, Flutter's raster thread): the main thread
  hands ui's renderer a retained layer tree (layers, transforms, clips,
  scroll offsets) in flat, off-heap buffers; a render thread, a GC-free job
  in a safe region, scrolls, runs transform and opacity animations and
  presents at the display's rate; input routed to compositor-scrolled
  layers. Layout itself stays on the main thread (10k nodes laid out in
  4.2 ms, allocating next to nothing): moved off it only if a measurement
  shows layout holding frames back. On the web, workers share no heap: the
  layer tree transferred, or a SharedArrayBuffer behind cross-origin
  isolation. And **devices in the extension**: their logs, a screenshot or
  a recording, a story picked on the phone.

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
- **Games in the extension**: stories for scenes (a world at a set point,
  its seed, camera and fixed step: deterministic, paused, stepped, scripted
  input), a scene inspector, debug drawing, GPU timings ("open in
  RenderDoc" on desktop), input recorded and replayed; the program's panel
  shown in a panel as a separate process sharing its frames as a GPU
  texture (as Makepad Studio: IOSurface, a DXGI shared handle, dmabuf), so a
  crash leaves the editor running.

### 6. Editor

Folded into phase 3: the VS Code extension is the devtools.

### 7. Later

- **Routing between screens**, as Flutter's Navigator and go_router or
  React Router have it: a router with routes and their parameters, a
  navigation stack (push, pop, back: the system's back button and gesture
  on phones), nested routes, deep links, URLs on the web (the address bar
  and history), and transitions between screens; in view's markup, with
  signals for the current route. An app-framework feature, so helder's.

## License

MIT (LICENSE).
