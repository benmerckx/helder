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
- **Consistency.** The packages share naming, error handling, units,
  coordinate conventions and resource lifetimes, and read as one library.

## Packages

All under `src/helder`, Haxe package `helder.<name>`:

| | |
| --- | --- |
| `os` | windows, input, the app loop and audio: X11, Cocoa, Win32, Android, UIKit, the browser |
| `gfx` | a portable GPU API: GL/GLES, Metal, D3D11, WebGPU, WebGL2; shaders written in Haxe |
| `text` | TrueType and CFF fonts in pure Haxe: rasterizing, shaping, bidi, layout, a glyph atlas |
| `view` | signals and JSX-like markup, compiled to direct calls on a renderer chosen at compile time |
| `ui` | flexbox layout, events, focus and accessibility, drawn on gfx or as the platform's controls |
| `web` | `view` on the web: DOM and static renderers, hydration, islands |
| `scene` | 3D on gfx: glTF, a PBR renderer, animation, input actions |
| `physics` | a small rigid-body core for `scene` |
| `scoped` | scoped memory on any Haxe target, and a checker that keeps it out of the GC heap |
| `dev` | the dev host and state kept across a reload |
| `theme` | shadcn/ui's look and Tailwind for ui's widgets (to be archived, see below) |

`examples/` has a program per folder; `tests/Run.hx` has the checks:

```sh
bun install
bun run test              # the lanes that need no GPU, display or browser
bun run test help         # every lane
```

## Roadmap

In order: each phase leans on the one before it.

### 1. Cleanup

- **Archive theme, the shadcn widgets and Tailwind.** Not useful in their
  current form. Remove `helder.theme`, `ui/widgets/Widgets.hx`,
  `web/widgets`, `examples/widgets`, `examples/dom-widgets` and their tests
  from the tree (git history keeps them, under a tag). Text editing
  (`TextField`, `TextArea`, `EditableText`) is core and stays in ui; the
  examples that used the theme move to plain styles.
- **Extract images into `helder.image`.** The PNG, JPEG, WebP and GIF
  decoders and animated images leave ui (SVG stays: it draws through ui), so that scene, 2D and the asset
  pipeline use them without depending on ui (scene now reaches them
  through a hook, `Images.decode`).
- **Fix the references the restructure left behind**: comments and package
  READMEs still point to `docs/` and `packages/`, which are gone.

### 2. The CLI

- **`helder dev [target]` and `helder build [target]`**, with hxmc as a
  dependency of helder rather than of the user's project. No configuration:
  the project's layout decides the entry point, the host is the default
  target, `android` and `ios` find the SDK and boot an emulator or
  simulator. The dev host (`helder.dev`) moves under the CLI.
- **Live reload on every target**, checked in CI: the dev loop already runs
  natively, in the browser and on Android (`tests/os/dev`); iOS follows.
- **The examples are the CLI's fixtures**: each builds and reloads with no
  configuration of its own.

### 3. Foundations

Two pieces of work side by side, as they constrain each other:

- **Async: research first, then built in.** Simple `async`/`await`
  coroutines, and fibers or isolates for background work (workers on
  wasm), for asset loading, HTTP (`os/Fetch`) and decoding. To settle
  first: scoped memory keeps a stack per thread, so a coroutine that
  suspends inside a scope, or a fiber, needs a rule (scoped values never
  live across an `await`, or a stack per fiber).
- **The core on `helder.scoped`.** Start with one package as a pilot (text's
  rasterizer and glyph atlas, or ui's layout), with a benchmark before and
  after, then the rest: ui, gfx's command recording, scene, physics, audio.
  The GC-facing API of each package stays.

### 4. Mobile

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

### 5. Graphics and 2D

- **Compressed textures**: ETC2 and ASTC on mobile (and BC on desktop),
  chosen per target by the asset step.
- **MSAA** render targets in gfx.
- **The 3D API close to three.js** (see Aims), after the research.
- **`helder.2d`**: sprite batches and tilemaps on gfx and `helder.image`.

### 6. Editor

- **A VS Code extension**: the language server, syntax highlighting, and
  support for view's markup.

## License

MIT (LICENSE).
