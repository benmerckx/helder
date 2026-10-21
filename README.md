# universe

An experimental app and GUI stack written in Haxe on
[hxmc](https://github.com/benmerckx/hxmc), the Haxe compiler port with a
native and WebAssembly target. **Unstable**: APIs change without notice,
checks are allowed to fail, nothing here is a release.

These packages grew inside hxmc while its target was being shaped (they
showed what the target needs: C interop, shared libraries, Android and iOS
apps, the dev loop). They were split out of hxmc at commit
[`a994ea3`](https://github.com/benmerckx/hxmc/commit/a994ea385dfe623a3b237077a4116bbc801b4844)
([hxmc#10](https://github.com/benmerckx/hxmc/issues/10), "Making this boring
tech"), with their history. hxmc does not depend on universe in any way;
universe depends on hxmc.

| Package | |
| --- | --- |
| `@hxmc/os` | windows, input and the app loop: X11, Cocoa, Win32, Android's NativeActivity, UIKit and the browser canvas; audio; the dev loop's host and fast refresh (`hxmc.dev`) |
| `@hxmc/gfx` | a portable GPU API: GL/GLES, Metal, D3D11, WebGPU and WebGL2, shaders written in Haxe |
| `@hxmc/text` | TrueType fonts in pure Haxe: parsing, rasterizing, shaping, layout, a glyph atlas |
| `@hxmc/view` | signals and JSX-like markup compiled to direct calls on a renderer chosen at compile time |
| `@hxmc/web` | `@hxmc/view` on the web: DOM and static renderers, hydration, islands in JavaScript or WebAssembly |
| `@hxmc/ui` | a UI toolkit: flexbox layout, events and focus, drawn on gfx or as the platform's controls, widgets |
| `@hxmc/theme` | the look of ui's widgets, after shadcn/ui |
| `@hxmc/3d` | a scene layer for 3D games on gfx: glTF, a PBR renderer, animation, input actions |
| `@hxmc/physics` | a small rigid-body core for `@hxmc/3d` |
| `@hxmc/3d-ui` | `@hxmc/view`'s markup on `@hxmc/3d`'s scene graph (a prototype) |

Each package has a README in `packages/<name>/`.

## Layout

- `packages/<name>/`: the packages, with their `examples/` and `test/`
  (golden images included);
- `site/`: the website hxmc had until the split, built with `@hxmc/web`
  (pages, the examples gallery, the API reference; docs/site.md);
- `test/ExampleBuilds.hx`: every package example built, not run;
- `docs/`: the packages' tests (docs/testing.md), the dev loop with the
  packages (docs/dev.md), the site (docs/site.md) and the design plans that
  are about the packages (`docs/plans/`: ui, view, web, theme, 3d, document,
  native-or-drawn, syntax, ui-next, graphics; wasmgc-ui: the WasmGC
  experiment measured on the packages). Links in them to hxmc's docs
  (`docs/hxmc.md`, `docs/plans/compiler.md`, ...) are to the hxmc
  repository.

## Building and testing

hxmc is built from source: `make hxmc` clones it into `hxmc/` at the commit
the Makefile pins (`HXMC_REV`), builds its tool (`bin/hxmc/hxmc`), merged std
and runtime objects there, and links them into `bin/`. The checks are the
ones hxmc's Makefile had for the packages:

```sh
make hxmc           # needs node 22 and git
make headless       # view, text, ui, theme, gfx's shaders, the examples built
make gfx-check      # Mesa and Xvfb on Linux, Metal on macOS
make help           # every check
```

`HXMC=<dir>` uses another hxmc checkout (`make headless HXMC=../hxmc`).
Paths in the docs such as `hxmc/test/ApkCheck.hx` are in that checkout.

CI (`.github/workflows/ci.yml`) builds hxmc at `HXMC_REV` and runs the
headless checks (required), the Mesa checks and the Chromium checks (not
required).

## State

Imported from hxmc `a994ea3` unchanged, except: the dev loop's tests find
`dev.mjs` and the upstream std in the hxmc checkout (`HXMC_DIR`), and the
Makefile builds hxmc from source. hxmc pinned at `d0c1758`, the nightly
of 2026-10-21 (`@hxmc/cli@0.1.0-nightly.20261021.d0c1758`), past the
split; `make headless` passes with it.

Left to do:

- The dev host may move into hxmc's std (hxmc keeps `hxmc dev` and the
  compiler's side of it).
- The site (`make site`) still reads hxmc's docs for its docs pages
  (site/src/Docs.hx) and expects hxmc's layout: it needs its own content.
- CI: the first run (39422902930) passed all three jobs (headless, the
  Mesa checks, the Chromium checks) against hxmc a994ea3; the Mesa and
  Chromium jobs stay not required while the stack is unstable.
- The lanes hxmc dropped at the split, which only made sense with the
  packages, live here and are not in CI yet:
  - Android on an emulator: `make android-device-check` (gfx's cube,
    native views, a GPU view among views, text input, a fling; the dev loop
    on Android, packages/os/test/dev/dev-android.mjs);
  - the iOS simulator: `make ios-sim-check` (a Mac with Xcode; IosTest,
    hxmc dev's host in the app);
  - gfx, ui, 3d and audio on Linux ARM64, Windows (D3D11 WARP, Win32,
    WASAPI under Wine or on a Windows runner) and macOS (Metal, Cocoa,
    CoreAudio), which hxmc's CI ran as gfx-arm64, gfx-windows and gfx-macos;
  - the dev host swapping builds in a running process (devhost-programs,
    packages/gfx/test/host-dev.sh, ios-dev.sh), and `make dev-check`
    (fast refresh in Chromium and natively);
  - the site in Chromium, Firefox and WebKit (`make site-check`).

## License

The packages are MIT (LICENSE), as they were in hxmc; `@hxmc/theme` also
carries shadcn/ui's MIT notice (packages/theme/LICENSE). `site/` and
`test/` come from hxmc's tooling, which is GPL-2.0-or-later (COPYING);
site/playground's try.haxe.org examples are MIT
(site/playground/LICENSE-try-haxe.txt).
