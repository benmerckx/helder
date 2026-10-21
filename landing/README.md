# The landing page

A static site for GitHub Pages where every example is a world: a planet on
its package's orbit around the compiler (a trail of planets on a phone).
Entering one compiles its Haxe source **in the browser** and runs it on a
canvas; the dock's *Download native* compiles the same source for the
visitor's OS and CPU (detected, or any of six from the dropdown) and hands
over the executable. Nothing is compiled ahead: the site ships Haxe source,
the compiler and the runtime objects.

```sh
make landing        # bin/landing (node 22; DejaVu fonts: fonts-dejavu-core)
make landing-check  # every example built as the page builds it, in node
npx http-server bin/landing
```

CI (`.github/workflows/pages.yml`) builds and checks it on pushes to main and
force-pushes `bin/landing` to the `gh-pages` branch, which Pages serves.

## How it works

| File | |
| --- | --- |
| `build.mjs` | fetches the nightly npm packages of the hxmc commit the Makefile pins (`@hxmc/wasm`: the compiler as a wasm32-wasi module; `@hxmc/cli`: the std and each target's runtime objects) and writes the site: the page, `haxe.wasm`, `std.pack`, `src.pack` (the packages' `src/` and `examples/`), `rt/<target>.pack`, os's `browser.mjs` and the packages' `imports.mjs`, the fonts, `manifest.json` (the examples read from their `// title:`, `// summary:`, `// demo:` headers, as site/src/Examples.hx reads them) |
| `wasi.js` | WASI preview 1 over a file system in memory, the packs mounted in it |
| `compile.js` | one build: the compiler's arguments for an example and a target, its output and the files it loads beside it (`Model.of`'s assets) |
| `compiler.js` | the worker the page compiles in: downloads once, keeps its file system (a second build for a target reuses the first one's objects) |
| `app.js`, `sky.js`, `style.css` | the universe, the worlds, the forge (the loader: the compiler's actual file reads and writes drive its rings, its ticker and the sky's warp), the download (a zip keeping the executable's mode; a bare `.exe` for Windows) |
| `test.mjs` | `make landing-check` |

What a first visit downloads: the compiler, 4 MB gzipped; the std and the
sources, 1.3 MB. A target's runtime is fetched with its first download
(0.35 to 1.2 MB gzipped). The compiler wakes at the first touch anywhere,
so it is mostly downloaded by the time a world is picked. A gfx example builds
in 2 to 4 s, a ui one in about 10 s (Chromium, a laptop).

## Where it could go

- **More worlds, written for the page.** The examples are the packages'
  own; worlds made to be played (a small game per package: a physics
  toy, a shader you drag, a UI you poke) would be the point of the site.
- **The sky in Haxe.** The background is JavaScript; it could be a wasm
  program built by the same compiler when the page opens, as the first thing
  the visitor sees compile.
- **Browsers without exnref.** `@hxmc/wasm` is built with exnref exception
  handling (Chrome 137+, Firefox 131+, Safari 18.4+); a `-D
  hxmc.wasm-eh=legacy` build of it, as hxmc's playground has, would reach
  older Safari. The page says so instead, for now.
- **Android and iOS downloads.** hxmc writes APKs and iOS apps
  (`make android-programs`, `ios-programs`); a phone visitor could get one
  for the phone in hand rather than a desktop's.
- **Faster second builds.** The compiler's module cache (hxmc's
  `HXMC_MODULE_CACHE`) could persist the typed std in the worker, or in
  IndexedDB between visits.
- **Signing.** macOS downloads are signed ad hoc, so Gatekeeper quarantines
  them (the page says how to run them); Windows' SmartScreen warns.
