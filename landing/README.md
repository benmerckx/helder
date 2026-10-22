# The landing page

A static site for GitHub Pages where every example is a world: a planet on
its package's orbit around the compiler (a trail of planets on a phone).
Entering one compiles its Haxe source **in the browser** and runs it on a
canvas. Its code opens beside it (on a phone: over it, the program still
running in a corner): an editor with the compiler's completion, hover,
signatures and errors, where every edit is kept (IndexedDB) and, once
typing pauses, built and swapped into the running program with its state.
The dock's *Download native* compiles the same source, edits included, for
the visitor's OS and CPU (detected, or any of seven from the dropdown:
Linux, macOS and Windows on x86-64 and ARM64, and an Android APK, the
default on an Android phone). On a phone, a corner over the code shows the
running program or a map of the code, a tab each.
Nothing is compiled ahead: the site ships Haxe source, the compiler and the
runtime objects; and the site itself is Haxe.

```sh
make hxmc           # the tool, which runs the build and builds the compiler
make landing        # bin/landing (node 22; DejaVu fonts: fonts-dejavu-core)
make landing-check  # the page's builds, in node
npx http-server bin/landing
```

CI (`.github/workflows/pages.yml`) builds and checks it on pushes to main and
deploys `bin/landing` as the Pages artifact (Pages source: GitHub Actions).

## The widgets page

`widgets.html`: every widget of `@hxmc/ui`, each the example beside it in
`packages/ui/examples/widgets`, on one page, twice, a switch between them:
**GPU**, drawn by a wasm program on the GPU (`widgets/WidgetsPage.hx`, built
ahead by the tool: `widgets.wasm`), and **DOM** (`#dom`), the same page
compiled to JavaScript with `hxmc.web`'s DOM renderer (`widgets-dom.js`)
under the theme's CSS scoped to `.hxmc` (`shadcn.css`). A search, dark and
right to left at a switch. Six examples style plain views in ways the DOM
renderer has no form for; the DOM's page says so on their cards. The six
that open their popup at start (the theme's reference images want them
open) wait for a click.

## The compiler: resident

`compiler/Reactor.hx` is hxmc's `haxe` (the same port and generators as
`@hxmc/wasm`) as a compilation server that never waits on a socket: its
`main` sets up the server's context and returns, and the page calls its
`request` (a `@:hxmc.callback`, named through `hxmc_web`'s `define` as
`hxmc.web.Exports` does) with each build's or display request's arguments.
Typed modules, lowered bodies and compiled objects stay in its memory, as
with `hxmc dev`, so a build after an edit types and compiles only what
changed:

| | first build | after an edit | display request |
| --- | --- | --- | --- |
| gfx's Cube | 2-4 s | 0.3-0.7 s | 0.5 s |
| ui's Counter, Todo | 9-11 s | 0.9-1.7 s | 0.5-1.8 s |

One compiler per program (the worker keeps the last two; one on a phone or
a machine with 4 GB or less: a ui program's compiler takes about 460 MB, a
gfx program's 180-320 MB). A compiler that stops (out of memory, most
likely) is dropped with the others and the build made again in a fresh
one; what it printed is shown. A world that cannot run says why over the
stage, with Show in the code, Reset my edits and Try again. a server's macros
keep state across builds (gfx's shader registry), right for the builds of
one program, wrong across programs. The tool builds it from hxmc's sources
in about 20 s, twice: `reactor.wasm` with exnref exception handling
(Chrome and Edge 137+, Firefox 131+, Safari 18.4+) and
`reactor-legacy.wasm` with the legacy instructions (Chrome and Edge 95+,
Firefox 100+, Safari 15.2+); the page detects which one the browser runs
and fetches only that (`?eh=legacy` forces it).

## The page

All of it is Haxe (`src/`), compiled to JavaScript by `@hxmc/wasm`'s
compiler under node:

| File | |
| --- | --- |
| `Main.hx` | the routes (`#/<example id>`), the universe and the worlds |
| `Universe.hx`, `Sky.hx` | the planets on their orbits (or the trail), the sky and its warp |
| `World.hx` | a world: the first build (the forge over the stage), the live builds, the code, the download |
| `Forge.hx` | the loader: the compiler's actual file reads and writes drive its rings and its ticker |
| `Editor.hx`, `DisplayJson.hx` | CodeMirror 6 (`editor.js`, the global `CM`) with the compiler's display requests: completion, hover, signature help (the info bar under the editor, for touch screens), the errors as diagnostics; a key bar above a phone's keyboard |
| `Runner.hx` | a program on the stage (`@hxmc/os`'s `browser.mjs`), and a new build swapped in from its snapshot (`hxmc_dev`'s imports, as `hxmc dev`'s page: `Hot`'s state, signals included, carries over) |
| `Store.hx` | the edits in IndexedDB, the progress in localStorage |
| `Download.hx`, `Zip.hx` | the target detected, the picker, the zip (the executable's mode kept) |
| `CompilerClient.hx`, `Protocol.hx`, `CompilerWorker.hx` | the worker the compiler runs in: downloads once, keeps its file system, answers the last of the waiting display requests and builds the last edit of a program (the others superseded) |
| `Compiler.hx`, `Wasi.hx`, `Pack.hx` | the compiler over WASI preview 1 in memory, the packs mounted in it; shared by the worker and the check |
| `Check.hx` | `make landing-check` |

`build/Build.hx` (run by the tool, as the site's `Site.hx`) fetches the
nightly npm packages of the hxmc commit the Makefile pins (`HXMC_REV`;
`HXMC_NPM_VERSION=<version>` picks another), builds the compiler, writes
the packs (`std.pack`, `src.pack`: the packages' `src/` and `examples/`;
`rt/<target>.pack`), bundles the editor (`editor/`: CodeMirror's pinned
packages, esbuild), compiles the page, the worker and the check, and
writes `manifest.json` (the examples read from their `// title:`,
`// summary:`, `// demo:` headers, as site/src/Examples.hx reads them).

What a first visit downloads: the compiler, 4 MB gzipped; the std and the
sources, 1.3 MB; the editor (130 KB) when the code first opens; a target's
runtime with its first download (0.35 to 1.2 MB). The compiler wakes at the
first touch anywhere, so it is mostly downloaded by the time a world is
picked.

## Where it could go

- **More worlds, written for the page.** The examples are the packages'
  own; worlds made to be played (a small game per package: a physics toy,
  a shader you drag, a UI you poke) would be the point of the site.
- **The sky in Haxe, on the GPU.** The page is Haxe compiled to JavaScript;
  the sky could be a wasm program on `@hxmc/gfx` built when the page opens,
  as the first thing the visitor sees compile.
- **Go to definition, find references.** The compiler answers
  `display/definition` and `display/references`; the editor could open the
  packages' files read-only.
- **iOS.** hxmc writes iOS apps too, but a phone installs none from a
  download; TestFlight or a simulator build for Macs are the ways in.
- **Sharing.** Edits are this browser's; a world's edits could be a link.
- **Signing.** macOS downloads are signed ad hoc, so Gatekeeper quarantines
  them (the page says how to run them); Windows' SmartScreen warns.
