# helder.cli

The `helder` command: a native program on `helder.async`, built by hxmc
(`bun run helder ...` builds bin/cli/helder from this checkout when a
source changed, then runs it). It calls hxmc's native compiler itself
(`node_modules/@hxmc/<os>-<cpu>`, given its std and runtime objects as
@hxmc/cli's launcher does), so no node runs; without a platform package it
says so and falls back to `node_modules/.bin/haxe`.

```sh
helder dev                                  # the project here, on this machine, live
helder dev web examples/counter/Counter.hx  # a page at http://127.0.0.1:4321/, live
helder build                                # bin/linux-x86_64/<name>: time and size
helder build windows-x86_64                 # any hxmc target (its runtime objects installed)
helder build web examples/counter           # bin/web/Counter.wasm, .html and its modules
helder run tests/cli/tally -- 3             # built, then run with arguments
helder test                                 # the *.test.hx files (src/helder/test)
helder inspect --tree                       # a running helder dev's ui tree (--log, --frames, --state)
```

## Conventions

`helder <command> [target] [entry]`: a known target name is a target,
anything else the entry.

- **Targets**: `host` (the default, this machine), `web` (wasm32-wasi with
  its page; legacy exception handling, which every browser with WebGPU
  has), or an exact hxmc target for `build`: `linux-x86_64`,
  `windows-x86_64`, `macos-arm64`, `wasm32-wasi`, ... Linux builds use the
  glibc mode (the GPU's and the sound's drivers are loaded).
- **Entries**:
  - nothing: the working directory, a project;
  - a project directory: `package.json` and `src/Main.hx`;
  - an example's directory: its one main file, or the one named as the
    directory (`examples/cube` is Cube.hx, not Targets.hx);
  - a file: `examples/counter/Counter.hx`. Its module is the main class,
    its class path the directory its `package` line makes it (one up per
    segment: `src/app/Hello.hx` in `package app` is `-cp src -main
    app.Hello`).
- **Class paths**: the entry's, then the nearest `package.json`'s at or
  above it (`"haxe": {"classPath"}`, `src` for a project: this checkout's
  helder), then its dependencies' that are Haxe packages
  (`node_modules/helder`); else the CLI's own checkout's `src`.
- **Overrides**: `package.json`'s `"helder"` key, `{"main": "app.Main",
  "name": "game", "defines": {"key": "value"}}`, and a `helder.hxml`
  beside it, given to every build.
- **Outputs**: `bin/<target>/<name>` under the project (the name is
  package.json's, else the main module's; `-o` names another); dev builds
  under `bin/dev/`. `build` is a release build (`-dce full`), `dev` adds
  `-D hxmc.dev`.
- **Renderers, a stopgap**: an entry whose sources import `helder.ui.`
  gets `-D helder.view.renderer.ui=helder.ui.view.NodeRenderer`
  (`helder.scene.view.` the scene's), as the examples need, until
  renderers are boundary tags in markup (`Entry.renderers`).

## The dev loop

Ported from @hxmc/cli's `dev.mjs`, and speaking the same protocol to the
program (`helder.dev.Hot`, `helder.os.App`'s client, the page):

- the compiler is a resident compilation server (`--server-connect`, a
  request at a time on one connection), each change's files invalidated
  first (`server/invalidate`), `-D disable-hxb-cache`;
- what the last build read is watched (`helder.async.SampledWatcher`,
  esbuild's polling): the module files a `--macro helder.cli.Deps.write`
  lists (under the class paths, but helder's own when it is a package),
  their directories' listings, `assets/`, package.json and helder.hxml; the
  set replaced after each build. Each 100 ms tick checks the 16 paths that
  changed last and a shuffled slice of the rest (all of them in about 2 s:
  2.3 ms of CPU a tick for 10k files, where scanning them takes 56 ms); a
  file's stat key, or its content while its mtime is within 2 s;
- a build with errors changes nothing: the last good build keeps running,
  the errors show in the terminal (and the page's overlay);
- natively the program runs with `HXMC_DEV` (our socket, JSON lines) and
  `HXMC_DEV_SNAPSHOT`. On Linux, Windows and macOS it runs in the dev host
  (`helder.dev.DevHost`, built once into the user's cache:
  ~/.cache/helder/dev-host, %LOCALAPPDATA%\helder\dev-host,
  ~/Library/Caches/helder/dev-host): each build a shared library (.so, .dll,
  .dylib) under a name of its own, `<out>.dev/<n>.<ext>` (a library loaded
  is not written over, and Windows locks it; a DLL's base one of three in
  turn), swapped in the same process: the window and the GPU device or
  context kept (X11 and EGL; the HWND, the D3D11 device, context and swap
  chain; the NSWindow, its views and the CAMetalLayer). The libraries the
  host has closed are deleted. With `HELDER_DEV_HOST=0`, or when the host
  does not build, the program writes its snapshot and exits, and the new
  build starts from it;
- for `web` the page (`page.html`) runs the module with helder.os's
  `browser.mjs` and the browser modules of the packages it imports (an
  `imports.mjs` naming one of its import modules), DejaVu Sans for
  helder.text; the WebSocket is at `/__hxmc/ws`, the module at
  `/__hxmc/app.wasm` (409 for a swap after a failed build), the project's
  files at `/`. A reload swaps the new build into the same page.

It prints `built`, `rebuilt in N ms`, `reloaded in N ms (build M ms)` (from
the change seen to the new build's first frame) and `error`.

## The devtools' relay

`helder dev` speaks the devtools protocol (src/helder/devtools/README.md)
with a program built with its agent: the program is started with
`HXMC_DEV_PROTOCOL=1` and says `Runtime.hello`, a reload is a
`Runtime.reload` request answered once the snapshot is saved
(`Devtools.hx`; @hxmc/cli's `{"type"}` lines to a program that does not
say hello). Tools connect to a WebSocket at `/__helder/devtools` on the
dev server's HTTP port, which runs natively too (`--port`, 4321 or the
next free one), named by `bin/dev/devtools.json`. Their requests go to the
program, the responses back by id, the notifications to the tools that
enabled their domain; the program's log is always on, its output and the
builds' errors with it, the last 500 entries kept for a tool that comes
late or after a crash.

`helder inspect [--tree] [--state] [--log] [--frames] [--port <n>] [dir]`
is a small client: it finds bin/dev/devtools.json from dir (or here) up,
prints the ui tree (`Ui.getTree`: tag, id, box, direction, background,
text) and the state `Hot` keeps once, and streams the log (the default:
what was kept, then each entry) and the frames' stats (a line a second:
mean and longest frame, work, GC bytes a frame, collections and pauses,
the agent's bytes) until `helder dev` ends.

## Workarounds for hxmc (each in one place)

- `processRun` takes no working directory or environment: `HXMC_DEV` and
  `HXMC_DEV_SNAPSHOT` (and the server's `RT_OLD_MB`, `RT_MINOR_KB`) are set
  with `Sys.putEnv` around the spawn and removed after (`DevCommand.start`,
  `CompileServer.start`); programs run in the CLI's directory.
- stat's mtime has a 1 s resolution: `SampledWatcher` compares the
  content of a file whose mtime was within 2 s when it was watched, and
  `PollWatcher` hashes files changed in the last 3 s.
- `haxe --wait` finds the runtime objects only through `HXMC_RT_DIR`, and an
  empty connection ends it (fixed in hxmc a85b139): `Compiler.find` sets
  HXMC_RT_DIR, `Compiler.start` probes with a request.
- (Not a bug: `--server-connect`'s builds are given hxmc's std by the
  client, as dev.mjs does: `CompileServer.request`.)

Tests: the `cli` lane (`bun run test cli`: builds by file, directory and
project, natively and for web; `tests/cli/dev.mjs`, the dev loop natively
and for web without a browser), the `devtools` lane (`tests/devtools`: the
relay and `helder inspect` against a console and a ui program), the
`examples` lane (every example by
`helder build <file>`), and `tests/os/dev/dev-web.mjs` and `dev-native.mjs`
with `--helder=bin/cli/helder` (Chromium; a window under Xvfb).

Not yet: the devtools' agent on the web (the page relaying it), changed assets sent without a
recompile, the page held back while the module is generated (dev.mjs's
`hxmc dev: generating`), native watchers, the CLI on npm as a binary,
Android and iOS, `helder new`, `helder doctor`.
