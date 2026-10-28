# helder.cli

The `helder` command: a native program on `helder.async`, built by hxmc
(`bun run helder ...` builds bin/cli/helder from this checkout when a
source changed, then runs it). It calls hxmc's native compiler itself
(`node_modules/@hxmc/<os>-<cpu>`, given its std and runtime objects as
@hxmc/cli's launcher does), so no node runs; without a platform package it
says so and falls back to `node_modules/.bin/haxe`.

```sh
helder dev                                    # the project here, on this machine, live
helder examples/counter/Counter.hx            # the same as helder dev examples/counter/Counter.hx
helder dev examples/counter --target web      # a page at http://127.0.0.1:4321/, live
helder build                                  # bin/linux-x86_64/<name>: time and size
helder build --target windows-x86_64          # any hxmc target (its runtime objects installed)
helder build examples/counter --target web    # bin/web/Counter.wasm, .html and its modules
helder run tests/cli/tally -- 3               # built, then run with arguments
helder test                                   # the *.test.hx files (src/helder/test)
helder inspect --tree                         # a running helder dev's ui tree (--log, --frames, --state)
helder devices                                # this machine, a browser, Android devices, iOS simulators
helder build --target android                 # bin/android/<name>.apk (arm64), signed with the debug key
helder build --target ios                     # bin/ios/<name>.ipa (an iPhone's); --target ios-sim: bin/ios-sim/<name>.app
helder run --target android -d emulator-5554  # built for the device's ABI, installed, started, its logcat here
helder dev --target ios                       # on the booted simulator: installed once, each build swapped in
```

## The grammar

```
helder <command> [entry] [options]      entry: a .hx file, a directory or a project (default: .)
helder <entry>                          shorthand for: helder dev <entry>

commands: dev, run, build, test, inspect, devices, help

  --target <t>       host (default), web, android, ios, ios-sim, or an exact hxmc target (windows-x86_64, android-x86_64, ...)
  -d, --device <d>   which phone, emulator or simulator (android, ios); `helder devices` lists them
  -o, --out <path>   build's output
  -- <args>          the program's arguments (dev, run)
  -h, --help         this help: helder help, or helder <command> --help
```

The positional is what is built, never where it runs: a word that is a
target's name and not a path is an error (`helder build web`: "`web` is a
target: use --target web"), and `helder web` too. `--target` has no short
form; `helder test`'s takes a list (`host,wasm`; `all`: host and wasm;
`interp`, only asked for: the files with `@:test.interp`), and keeps
bun's `-t`/`--test-name-pattern`. The first word is a command or an entry
(`helder examples/todo/Todo.hx` is dev's); `helder` alone prints the help.
Each command has its own options beside the common ones: dev `--port`,
`--host`; test `-t`, `-w`, `-u`, `--timeout`; inspect `--tree`, `--state`,
`--log`, `--frames`, `--port`. One parser (`Options.hx`) reads them all,
and writes `helder help` and `helder <command> --help` from the same
table; a mistake is one line, `helder <command>: <what>` (an unknown
option: `helder build: unknown option --x (helder build --help)`), exit
code 2. `-d` goes with `--target android` or `ios` only (`ios-arm64`, an
iPhone, is build's only: its app needs a signing identity). `helder
devices` lists what it finds: this machine (host, with its target), a
browser through the dev server (web), Android's devices and emulators
(`adb devices -l`: `ADB`, else adb on the PATH, else
`$ANDROID_HOME/platform-tools`; else "adb not found"; one not ready has
its state after the kind: `device, unauthorized`) and iOS's simulators
(`xcrun simctl list devices available`, on macOS; `XCRUN` names another):
id, name, kind, target. Without `-d`, dev and run take the one device
there is (Android's ready one, iOS's booted simulator), and with several,
or none, say so and name them (`Devices.pick`); `-d` takes an id (a
simulator's name too: `-d "iPhone 16"`), and a simulator not booted is
booted.

## Conventions

- **Targets** (`--target`): `host` (the default, this machine), `web`
  (wasm32-wasi with its page; legacy exception handling, which every
  browser with WebGPU has), or an exact hxmc target for `build`:
  `linux-x86_64`, `windows-x86_64`, `macos-arm64`, `wasm32-wasi`, ...
  Linux builds use the glibc mode (the GPU's and the sound's drivers are
  loaded). Phones (below): `android` (arm64, or the device's ABI for run
  and dev: `android-arm64`, `android-x86_64`), `ios` (an iPhone's,
  `ios-arm64`, for build; the simulator's for run and dev), `ios-sim`
  (`ios-sim-arm64`, Apple silicon's simulator).
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
  "name": "game", "defines": {"key": "value"}}` and an app's identity
  (below), and a `helder.hxml` beside it, given to every build.
- **Outputs**: `bin/<target>/<name>` under the project (the name is
  package.json's, else the main module's; `-o` names another); dev builds
  under `bin/dev/`. `build` is a release build (`-dce full`), `dev` adds
  `-D hxmc.dev`. Phones: `bin/android/<name>.apk` (its library, and what
  the build needs of Java, beside it in `<name>.lib/`),
  `bin/ios/<name>.ipa` (and its `.app`), `bin/ios-sim/<name>.app`.

## Android and iOS

Ported from hxmc (MIT), which wrote APKs and app bundles itself until
then: hxmc's output ends at native code, the packaging is helder's
(`helder.pack`, `Android.hx`, `Ios.hx`). No SDK, NDK, Java or Xcode at
build time.

- **Android**: hxmc links the program as `libmain.so` (its soname is the
  output's name), the program's `ANativeActivity_onCreate` its entry
  (`helder.os.android.Activity`). `helder.pack.android` puts it in an APK:
  `lib/<abi>/libmain.so` stored and 16 KB aligned (Android 15's pages;
  `extractNativeLibs="false"`), the manifest in binary XML (`Axml`:
  NativeActivity, or `org.hxmc.Activity` for a program showing Android's
  views), `classes.dex` when the program has Java's listeners (`Dex`,
  `Glue`; `helder.pack.android.Classes`, a macro of the build, tells from
  the program as generated: `@:helder.android.dex` on
  `helder.os.android.Glue` in it; `@:helder.android.views` on
  `helder.ui.native.NativeHost`, which the program makes: every ui
  program has the class, a drawn window needs NativeActivity's surface;
  tested on the counter and native-form examples), and APK Signature Scheme v2
  (ECDSA P-256 with SHA-256, RFC 6979's nonces: `P256`, `Der`; v2 only,
  which minSdk 29 allows). Debuggable; no release signing, icons,
  resources or `.aab` yet.
- **The debug key**: the user's own, made on first use and kept, so a
  reinstall keeps the signature: `HELDER_ANDROID_KEY` names its file, else
  `package.json`'s `"helder": {"android": {"key"}}`, else
  `<helder's cache>/android/debug-key` (`HELDER_CACHE`, else
  ~/.cache/helder, ~/Library/Caches/helder, %LOCALAPPDATA%\helder). A text
  file: `helder-android-debug-key 1`, the private scalar in hex, its
  self-signed certificate (CN=Android Debug, 30 years) in base64; the
  scalar and the serial come from the system's random source
  (`helder.pack.Entropy`: BCryptGenRandom on Windows, /dev/urandom
  elsewhere). Changed from hxmc's: helder's names (`HXMC_ANDROID_KEY`,
  `hxmc-android-debug-key 1` and hxmc's cache were hxmc's), and Windows no
  longer falls back to the time and `Math.random`. An app signed by hxmc's
  key does not update in place: uninstall it once.
- **iOS**: hxmc links a Mach-O executable (`-D hxmc.ios-min-version`: its
  `LC_BUILD_VERSION`) into `<name>.app`, whose `Info.plist` and
  `_CodeSignature/CodeResources` helder writes first (`helder.pack.ios`:
  `Bundle`, `Plist`), and signs it ad hoc binding them (`-D
  hxmc.codesign-id`: the bundle id; `-info-plist`, `-resources`,
  `-entitlements`), as `codesign -s -` does: enough for the simulator. An
  `.ipa` zips the bundle under `Payload/`. A device's app needs a signing
  identity and a provisioning profile: not yet.
- **An app's identity**: `package.json`'s `"helder"` key (`App.hx`):
  `"id"` (the application id and bundle id; `org.helder.<name>`),
  `"label"` (the name), `"version"` (versionCode, CFBundleVersion: 1),
  `"versionName"` (1.0), `"android": {"permissions": ["INTERNET"],
  "minSdk": 29, "targetSdk": 35, "key"}`, `"ios": {"minVersion": "15.0",
  "entitlements": "<an XML plist>"}`.
- **run**: on Android `adb -s <id>` installs (`install -r`), starts (`am
  start`, after `force-stop`) and streams logcat's `hxmc` tag (the
  program's stdout and stderr) until the app's process ends; on iOS `xcrun
  simctl` boots the simulator when it is not, installs, and launches with
  `--console` (its output here, its end the command's).
- **dev**: the first build is the dev host's app, installed and started.
  Android's APK is built for the dev server's socket (`-D
  hxmc.dev-server=127.0.0.1:<port>`, `adb reverse`, INTERNET asked for),
  and a later build sends its library alone: `{"type":"reload",
  "snapshot":"-","fetch":"<n>"}`, the app asks for `lib <n>` on a
  connection of its own, writes it into its files and hands over to it in
  the same process (`helder.dev.Hot`, `helder.os.android.Activity`); its
  output is logcat's. The simulator's app gets `HXMC_DEV` and
  `HXMC_DEV_SNAPSHOT` (simctl's `SIMCTL_CHILD_`), a later build is a dylib
  (`-D hxmc.shared`) it loads from this machine's files; its output is
  simctl's.

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

It prints `built in N ms`, `rebuilt in N ms`, `reloaded in N ms · build M
ms` (from the change seen to the new build's first frame), `failed in N
ms` after the compiler's errors, `crashed` and `closed` (Output, below).

When the program ends by itself (`ExitPolicy.hx`, as `tauri dev` and
electron-forge): on this machine an exit code of 0 is the program closed
(its window: the dev host ends when a build returns without handing over),
and `helder dev` ends too, the watcher and the servers stopped, exit code
0; any other exit code, or a signal, is a crash: `crashed the program
exited with code N`, and the session stays, the next change building and
starting it again. A program helder dev ended itself (a reload's restart:
without the dev host each reload's program exits 0; one that did not answer
a reload; ctrl-c) decides nothing. On the web a closed tab is a client
gone, the server stays (as vite's). On a phone (`Mobile`) closing the app
there does not end the session: it keeps serving, and the next build
installs and starts the app again (`closed the app on <device> ended; the
next change starts it again` when simctl's launch ends; on Android the
sign is that no app is connected when a build is done).

## Output

`Style.hx` (pure: colours, the status lines, the help's colours),
`Diagnostics.hx` (the compiler's messages) and `Term.hx` (the terminal),
after cargo's, bun's and vite's look:

```
helder dev v0.1.0  linux-x86_64 · app.Main
 watching src
 devtools ws://127.0.0.1:4321/__helder/devtools
    built in 812 ms · 2.1 MB
  rebuilt in 167 ms · 2.1 MB
 reloaded in 242 ms · build 167 ms
    error src/app/Main.hx:12:5
   failed in 120 ms · the last good build keeps running
  crashed the program exited with code 1; the next change builds and starts it again
   closed the program exited; stopping
```

A header (`helder <command>` bold, the version and the details dim), then a
verb right-aligned in a column of 9: green `built`, `rebuilt`, `reloaded`;
cyan `serving`, `watching`, `running`; yellow `warning`; red `error`,
`failed`, `crashed`; dim the rest; times bold, details dim. The compiler's
messages (Haxe's pretty format, and its classic one) get their
file:line:column in front of an `error` or `warning`, the code's gutter
dim, the carets red (yellow for a warning). The help's commands and options
are bold, their descriptions dim; a usage mistake's `helder <command>:` red.
`helder test` gives its runner `--color` (and `--unicode`): bun's ✓, ✗ and
», the summary's pass green, fail red. A spinner (braille, or `|/-\`)
runs on stdout while a build does, only on a terminal, the lines written
meanwhile above it.

Colours: on for a terminal (stdout's and stderr's each), off with
`NO_COLOR` (not empty) or `TERM=dumb`, forced by `FORCE_COLOR` (but `0` or
`false`). Without them the same lines, plain, and the compiler's messages
as it writes them: CI's logs and the cli lane read those. On Windows 10 and
later the console is switched to VT processing (none: no escapes, no
spinner); ✓, ✗ and the braille spinner only when its code page is UTF-8's
(65001), else ASCII (`(pass)`, `|/-\`, `, ` between details); the Linux
console (`TERM=linux`) gets ASCII too.

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

## Stopping

On SIGINT or SIGTERM (`helder.async.Signals`), `helder dev` stops the
program and the compilation server, and `helder test --watch` its
server: each asked to end (SIGTERM), ended (SIGKILL) if it has not within
2 s; then the CLI exits with 128 + the signal. On Windows, where
helder.async has no signals, ctrl-c reaches every process of the console:
the program's (the dev host's) and the compiler's with the CLI's. A program that does not
answer a reload is stopped the same way, within 1 s. The program and the
server are given their environment (`HXMC_DEV`, `HXMC_DEV_SNAPSHOT`; the
server's `RT_OLD_MB`, `RT_MINOR_KB`) through `Process`'s `env`, the CLI's
own left alone.

## hxmc

No workarounds left:

- The platform package's compiler finds its runtime objects beside itself
  (`<its dir>/<target>/rt.o`) and in the other platform packages of its
  version (cross builds: `npm i -D --force @hxmc/win32-x64`), HXMC_RT_DIR
  added to the search (hxmc #93, @hxmc/cli
  0.1.0-nightly.20261027.a4195c7): `Compiler.find` no longer gives it
  HXMC_RT_DIR.
- (Not a bug: `--server-connect`'s builds are given hxmc's std by the
  client, as dev.mjs does: `CompileServer.request`.)

Tests: `src/helder/cli/Options.test.hx` (the grammar: the shorthand, the
positional never a target, `--target`, `-d`, `--`, the options' errors,
the help, `helder devices`' lists and `-d`'s default; in the test
lane), `App.test.hx` (an app's identity: the defaults, package.json's,
the mistakes, the debug key's file), `Style.test.hx`
(colours on or off, the status lines, the help and the compiler's
messages coloured are the plain text with escapes), `ExitPolicy.test.hx`
(closed, crashed, a reload, ctrl-c, web, a phone), the `cli` lane (`bun
run test cli`: the grammar's errors and `helder devices` without adb and
with a stand-in one from the binary, builds by file, directory and
project, natively and for web; `tests/cli/dev.mjs`, the dev loop natively
and for web without a browser, natively without the dev host, and
the exit policy: tests/cli/closer crashing, then closed), the `devtools` lane (`tests/devtools`: the
relay and `helder inspect` against a console and a ui program), the
`examples` lane (every example by
`helder build <file>`, `--target web` for the web), and
`tests/os/dev/dev-web.mjs` and `dev-native.mjs`
with `--helder=bin/cli/helder` (Chromium; a window under Xvfb).

Android and iOS, tested where:

- **Everywhere `helder test` runs** (natively and as wasm32-wasi):
  `src/helder/pack/*.test.hx`: the zip (alignment, modes, read back),
  P-256 against RFC 6979's vectors, the APK (its layout, the manifest
  dumped, the certificate parsed back, the v2 block's digest recomputed
  and its signature the key's), classes.dex (Dex.check), the debug key
  (made from the system's random source, kept, refused when it is not
  one), Info.plist, CodeResources and the .ipa.
- **The `pack` lane** (`bun run test pack`, Linux; part of `headless`):
  tests/pack/Hello.hx and a project with an app's options (tests/pack/project:
  an id, a permission, iOS's minimum and entitlements) built for
  android-arm64, android-x86_64, ios-arm64 (.ipa) and ios-sim-arm64 (.app)
  by `helder build`, checked by tests/pack/PackCheck.hx: the zip's layout
  and 16 KB alignment, the manifest, the library (readelf: 16 KB segments,
  soname, the export, DT_NEEDED), the v2 signature's digest recomputed and
  openssl verifying it (apksigner, zipalign and aapt when on the PATH:
  CI's); the bundle, Info.plist, the Mach-O's build version, its code
  signature with its page hashes and special slots (1 Info.plist, 2 the
  requirements, 3 CodeResources, 5 the entitlements). Then `helder run`
  and `helder dev` against stand-ins for adb and xcrun (tests/pack/fake,
  tests/pack/dev.mjs: the first build installed and started, the app's
  connection, a reload's library fetched by `lib <n>` and the same as the
  build's, the simulator's dylib, the app closed and started again by the
  next change). The runtime objects: tests/pack/runtime.mjs fetches
  macos-arm64's from npm (@hxmc/darwin-arm64) and Android's from hxmc's
  `rt-*` release of the same sources (not on npm); without them those
  builds are skipped (PACK_REQUIRE=1: a failure).
- **Only in CI, untested until it runs** (`.github/workflows/ci.yml`; no
  emulator, simulator or Mac where it was written): the `android` job,
  an x86-64 emulator (API 34) running tests/pack/android.sh (`helder run
  --target android`'s hello line from logcat, then the APK by adb alone)
  and tests/os/dev/dev-android.mjs (`helder dev --target android`: two
  edits swapped into the same process, the state kept); the
  `ios-simulator` job on macos-15, the pack lane (with codesign --verify
  and plutil -lint) and tests/pack/ios.sh (`helder run --target ios -d
  <a new simulator>`'s hello line). Never yet on a real phone.

Not yet: the devtools' agent on the web (the page relaying it), changed assets sent without a
recompile, the page held back while the module is generated (dev.mjs's
`hxmc dev: generating`), native watchers, the CLI on npm as a binary,
iOS devices (signing), Android's release signing, icons and assets in the
APK and the bundle, booting an emulator, `helder new`, `helder doctor`.
