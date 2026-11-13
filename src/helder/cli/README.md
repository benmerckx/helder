# helder.cli

The `helder` command: a native program on `helder.async`, built by hxmc
(`bun run helder ...` builds bin/cli/helder from this checkout when a
source changed, then runs it). It calls hxmc's native compiler itself
(`node_modules/@hxmc/<os>-<cpu>`, given its std and runtime objects as
@hxmc/cli's launcher does), so no node runs; without a platform package it
says so and falls back to `node_modules/.bin/haxe`. With helder's sources
and node at hand it builds with helder's compiler instead (src/helder/compiler:
hxmc's with markup in any function and the TypeScript frontend, built once
into the user's cache by `src/helder/compiler/build.mjs`), hxmc's native one
when that does not build. Installed from npm, both come prebuilt (below).

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
helder run --headless --script s.json --snap a.png --tree t.json   # no display: scripted, a frame and the node tree
helder devices                                # this machine, a browser, Android devices, iOS simulators
helder studio examples/ts-todo                # helder studio (apps/studio) on a project: its screens, code, inspector, MCP
helder build --target android                 # bin/android/<name>.apk (arm64), signed with the debug key (or the release key)
helder build --target android --bundle        # bin/android/<name>.aab for Google Play, signed with the release key
helder publish --play [--track beta] [--dry-run]   # the .aab to Google Play's track (internal by default)
helder publish --testflight [--dry-run]       # the signed .ipa to App Store Connect, for TestFlight
helder build --target macos --package         # a desktop's release in bin/dist: macOS's .app in a zip (windows-x86_64: the .exe; linux-x86_64: a .tar.gz, a Flatpak manifest)
helder publish --notarize [--dry-run]         # on a Mac: the macOS release notarised by notarytool, stapled
helder build --target ios                     # bin/ios/<name>.ipa (an iPhone's; signed for the App Store with HELDER_IOS_*); --target ios-sim: bin/ios-sim/<name>.app
helder run --target android -d emulator-5554  # built for the device's ABI, installed, started, its logcat here
helder dev --target ios                       # on the booted simulator: installed once, each build swapped in
```

## From npm

```sh
npm install -D helder@next        # and typescript@^7.1 for TypeScript projects
npx helder build
```

- **`helder`** (MIT): helder's sources and types (no tests), and the
  `helder` command, `run.mjs`: it runs this machine's platform package's
  CLI in the working directory, `HELDER_COMPILER` naming its compiler (it
  comes before every other one but `HAXE`: `Compiler.hx`), `HELDER_SRC`
  this package's `src/`, and the environment @hxmc/cli's launcher gives
  its compiler (its `toolEnv`: upstream's std, hxmc's, the runtime
  objects' directories). Without a platform package it says so and stops;
  in a checkout it builds bin/cli/helder as before.
- **`@helder.build/<os>-<cpu>`** (darwin-arm64, darwin-x64, linux-x64,
  linux-arm64, win32-x64, win32-arm64): `helder`'s optional dependencies,
  at its version, each `bin/helder` (helder.cli.Cli) and
  `bin/helder-compiler` (helder's compiler: hxmc's compiler sources from
  @hxmc/source with helder's hooks and frontends), two executables: the
  GPL compiler is not linked into the MIT CLI. Their license is `MIT AND
  GPL-2.0-or-later`: the compiler's is hxmc's (COPYING), its README names
  its sources (hxmc's repository at the commit @hxmc/cli was built from,
  helder's at the package's), and both link hxmc's runtime (libuv's and
  Mbed TLS's licenses beside them).
- **`@hxmc/cli`**, a dependency pinned to the nightly the binaries were
  built against: its std (`haxe/upstream/std`, `hxmc/bootstrap/hxmc-std`)
  and, through its own optional dependencies, the runtime objects
  (`@hxmc/<os>-<cpu>/<target>/rt.o`) the programs link with. Its compiler
  goes unused.

`node src/helder/cli/npm.mjs <os>-<cpu> ...` builds the platform packages
into `bin/npm/<os>-<cpu>` from any host (hxmc cross-compiles; a target's
runtime objects from npm's @hxmc/<os>-<cpu> into `bin/npm/hxmc`), at
package.json's version; `npm.mjs version <version>` stamps package.json
with a version and its platform packages before a publish.
`.github/workflows/npm.yml` builds them nightly when main changed (Linux
and macOS runners), installs the tarballs into an empty project on Linux
(x64, arm64), macOS and Windows, builds examples/counter and
examples/ts-counter natively and for the web there, then publishes
from main (`0.1.0-nightly.<yyyymmdd>.<commit>`, npm's tag `next`)
through npm's trusted publishing: each package trusts the workflow, no
token.

## The grammar

```
helder <command> [entry] [options]      entry: a .hx file, a directory or a project (default: .)
helder <entry>                          shorthand for: helder dev <entry>

commands: dev, run, build, test, inspect, publish, share, login, logout, migrate, studio, devices, help

  --target <t>       host (default), web, android, ios, ios-sim, macos (a universal app bundle), or an exact hxmc target (windows-x86_64, android-x86_64, ...)
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
`--host`; run `--headless` and its own (`--snap`, `--tree`, `--script`,
..., below: "Headless runs"); test `-t`, `-w`, `-u`, `--timeout`; inspect `--tree`, `--state`,
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
- **macOS's app bundle** (`--target macos`): `bin/macos/<Label>.app`, its
  executable universal (macos-arm64's and macos-x86_64's slices, lipo's
  fat header: `helder.pack.apple.Fat`, each signed ad hoc as hxmc signs
  it), its Info.plist (the manifest's id, name, version; its icon as
  AppIcon.icns; CFBundleDocumentTypes from the manifest's
  `file_handlers`: Finder's Open With, helder.os's `App.onOpen`).
  x86-64's runtime objects from @hxmc/darwin-x64 (HXMC_RT_DIR) on an
  Apple silicon Mac.
- **Desktop releases** (`--package`, `Desktop.hx`): `bin/dist/<name>-<version>-<platform>`
  (`-o` another directory), the manifest's version. macOS: the universal
  `.app` (sealed: `_CodeSignature/CodeResources`; each slice signed ad hoc,
  or by a Developer ID identity, `HELDER_MACOS_IDENTITY` or
  `HELDER_MACOS_CERTIFICATE` and `HELDER_MACOS_KEY`, with the hardened
  runtime and Apple's timestamp, `HELDER_MACOS_TIMESTAMP_URL`) in a zip;
  `helder publish --notarize` (a Mac's `xcrun notarytool` with
  `HELDER_ASC_KEY_ID`, `HELDER_ASC_ISSUER_ID`, `HELDER_ASC_KEY`, the
  .p8 written for it and removed after; `XCRUN` names another) submits it,
  waits, prints the log when refused, staples the ticket and zips again.
  Windows: the `.exe` made a GUI program, its icon and version as
  resources, signed by Authenticode with `HELDER_WINDOWS_IDENTITY` or
  `HELDER_WINDOWS_CERTIFICATE` and `HELDER_WINDOWS_KEY` (timestamped by
  `HELDER_WINDOWS_TIMESTAMP_URL`, DigiCert's by default, `none`), or by
  `HELDER_WINDOWS_SIGN_COMMAND` (a command given the file's path: a cloud
  HSM's signer), in a zip. Linux: a `.tar.gz` (the program, `install.sh`,
  `share/applications/<id>.desktop` with the manifest's file types,
  hicolor icons from 16 to 512, AppStream metainfo) and
  `<id>.flatpak.json` (the tarball by its SHA-256, the freedesktop
  runtime). Every secret is a file's path or its text, and none is
  printed.
- **Entries**:
  - nothing: the working directory, a project;
  - a project directory: `package.json` and `src/Main.hx`; or its
    `helder.json`'s `entry` (`src/LittleSkies.hx`: an app in a repository
    of its own, helder its dependency), named as the package;
  - an example's directory: its one main file, or the one named as the
    directory (`examples/cube` is Cube.hx, not Targets.hx);
  - a TypeScript program: a `.ts` or `.tsx` file, a project whose entry is
    `src/main.ts(x)` (and no `src/Main.hx`), or a directory with a
    `main.ts(x)`: built by helder's compiler (src/helder/compiler), hxmc's
    with helder's TypeScript frontend (src/helder/typescript), in the compiler's place,
    the app's own `typescript` (7.1 or later) checking it; `helder dev`
    watches the program's files and keeps tsgo up in the compilation
    server, a change checked and rebuilt in a few hundred ms;
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
  beside it, given to every build; the app's name, icons and identity are
  `helder.webmanifest`'s (below).
- **Outputs**: `bin/<target>/<name>` under the project (the name is
  package.json's, else the main module's; `-o` names another); dev builds
  under `bin/dev/`. `build` is a release build (`-dce full`), `dev` adds
  `-D hxmc.dev`. Phones: `bin/android/<name>.apk` (its library, and what
  the build needs of Java, beside it in `<name>.lib/`),
  `bin/ios/<name>.ipa` (and its `.app`), `bin/ios-sim/<name>.app`.

## The app's settings: helder.json

`helder.json` at the project's root (beside `package.json`, or in an
example's directory, which it then makes the project's root: its `bin/`
there) is the app's name, icons, colours and splash, each target's own
settings, and where `helder publish` sends each one (`HelderJson.hx`; its
schema `helder.schema.json`, served at https://helder.build/schema/helder.json
for editors' completion):

```json
{
  "$schema": "https://helder.build/schema/helder.json",
  "name": "Little Skies",
  "description": "Mini golf on three islands in the sky.",
  "id": "build.helder.littleskies",
  "version": "1.2", "build": 3,
  "entry": "src/LittleSkies.hx",
  "icon": "brand/icon-ios.svg",
  "colors": {"theme": "#ffae78", "background": "#fbdfea"},
  "display": "fullscreen",
  "orientation": "landscape",
  "run": {"name": "little-skies", "listed": true, "kind": "game", "tags": ["golf"],
          "source": "https://github.com/helder/little-skies"},
  "targets": {
    "android": {"minSdk": 31, "adaptiveIcon": {"foreground": "brand/fg.svg", "background": "brand/bg.svg"},
                "publish": [{"to": "play", "track": "internal"}], "store": "https://play.google.com/..."},
    "ios": {"bundleId": "build.helder.littleskies", "publish": ["testflight"]}
  }
}
```

- **The app's**: `name`, `label` (the launcher's, else name),
  `description`, `id` (both phones'), `version`, `build`, `entry` (what a
  build of the directory builds), `icon` (a file, or `{any, maskable,
  monochrome}`), `colors` (`theme`, `background`), `splash` (`image`,
  `background`, `dark`), `display`, `orientation`, `lang`, `dir`,
  `categories`, `fileHandlers`: the web manifest's members below, by
  other names.
- **`run`**: helder.run's (below, "helder.run").
- **`targets`**: `android` and `ios` take the web manifest's `"helder":
  {"android"}` and `{"ios"}` members below as they are; each target its
  `publish` list (android: `play`, or `{"to": "play", "track", "draft"}`;
  ios: `testflight`; macos: `notarize`) and `store`, its page in its store
  (helder.run's page links it).
- It is read as the web manifest it stands for, so everything below holds
  for it; its mistakes are named by its own members (`targets.android.minSdk`).
  A web build writes that manifest beside the page without its `"helder"`
  member. `helder migrate [dir]` writes a `helder.webmanifest` as
  `helder.json` and removes it; a project with both reads `helder.json`.

### helder.webmanifest

A project without `helder.json` may keep `helder.webmanifest` at its root:
the app's name, icons, colours, splash and native settings, for every target
(`Manifest.hx`, `Icons.hx`). It is a [W3C Web App
Manifest](https://www.w3.org/TR/appmanifest/), served to browsers as it
is, so its members are the web's wherever the web has one; what only
native apps need is in a `"helder"` member, which browsers ignore. The
name: `.webmanifest` is the manifest's registered extension (its media
type, `application/manifest+json`), and `helder.` says whose it is, as
`helder.hxml` does, unlike a bare `manifest.json`, which bundlers,
browser extensions and PWA tools each claim.

```json
{
  "name": "Expansion",
  "short_name": "Expansion",
  "description": "A real-time strategy game",
  "display": "fullscreen",
  "orientation": "landscape",
  "theme_color": "#3ED6C3",
  "background_color": "#060912",
  "icons": [
    {"src": "icon.svg", "sizes": "any", "type": "image/svg+xml", "purpose": "any"},
    {"src": "icon-maskable.png", "sizes": "1024x1024", "type": "image/png", "purpose": "maskable"},
    {"src": "icon-mono.svg", "sizes": "any", "type": "image/svg+xml", "purpose": "monochrome"}
  ],
  "helder": {
    "version": "1.2",
    "build": 3,
    "id": "org.example.expansion",
    "android": {"package": "org.example.expansion", "minSdk": 29, "targetSdk": 36, "permissions": ["VIBRATE"], "key": "keys/debug",
                "signing": {"certificate": "keys/upload.pem", "key": "keys/upload.key"}},
    "ios": {"bundleId": "org.example.expansion", "minVersion": "15.0", "entitlements": "app.entitlements",
            "signing": {"certificate": "keys/distribution.pem", "key": "keys/distribution.key", "profile": "keys/AppStore.mobileprovision"},
            "sdk": {"version": "26.0", "build": "23A339", "xcode": "2600", "xcodeBuild": "17A324", "machine": "25A354"},
            "nonExemptEncryption": false,
            "privacy": {"NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"]}},
    "splash": {"background_color": "#060912", "image": "splash.svg",
               "dark": {"background_color": "#000000", "image": "splash-dark.svg"}}
  }
}
```

- **The web's members**: `name` (the page's title; the label when there is
  no `short_name`), `short_name` (the launcher's and home screen's label),
  `description`, `lang`, `dir`, `id`, `start_url`, `categories`,
  `screenshots` (the web's alone), `display` (`fullscreen`: the system's
  bars hidden, `-D helder.fullscreen`, `UIStatusBarHidden`; the others
  not), `orientation` (`portrait*` and `landscape*` as `portrait` and
  `landscape` below; `any` and `natural` neither), `theme_color` (the
  browser's), `background_color` (the splash's, the page's, an icon's
  background), `icons` (`src` from the manifest's directory, `sizes`
  `any` or `WxH ...`, `type`, `purpose` `any`, `maskable`, `monochrome`).
- **`"helder"`**: `version` (versionName, CFBundleShortVersionString:
  `1.0`), `build` (versionCode, CFBundleVersion: 1), `id` (both platforms'
  id, else `org.helder.<name>`), `android` (`package`: its id; `minSdk`:
  29, the lowest, Bionic's ELF TLS; `targetSdk`: 36; `permissions`:
  `android.permission.<name>` unless it has a dot; `key`: the debug key's
  file; `signing`: the release key's certificate and key, PEM, below), `ios` (`bundleId`; `minVersion`: 15.0; `entitlements`: an XML
  plist signed with the executable, each key one the provisioning profile
  grants; `signing`: the distribution identity's files, below;
  `sdk`: the SDK and Xcode an iPhone's build says it was made with,
  Info.plist's `DTPlatformVersion`, `DTSDKName` (`iphoneos<version>`),
  `DTPlatformBuild` and `DTSDKBuild` (`build`), `DTXcode`, `DTXcodeBuild`,
  `BuildMachineOSBuild` (`machine`) and `LC_BUILD_VERSION`'s SDK, Xcode
  26.0's by default (the App Store takes builds of a recent SDK only:
  raise them when Apple raises its minimum); `nonExemptEncryption`:
  `ITSAppUsesNonExemptEncryption`, App Store Connect's export compliance
  question answered; `privacy`: `PrivacyInfo.xcprivacy`'s required-reason
  APIs, each category's reasons, over those helder declares for the APIs
  the executable imports), `splash` (`background_color`, else
  the manifest's; `image`, else the icon; `dark`: the same for the dark
  appearance).
- **Mistakes** are the command's error, naming the member: not JSON, a
  member of the wrong type, an unknown `display`, `orientation` or
  `purpose`, a colour CSS does not have, an icon's `sizes` not square or
  not `WxH`, an unknown member of `"helder"` or its objects, an id the
  platform would refuse; at build time an icon whose file is missing, is
  not an image, is not square, is not the size its `sizes` say, or is too
  small for what it makes (more than twice: give a larger one or an SVG).
- **Icons from a few sources** (`Icons.hx`): every size a target needs is
  made at build time from the manifest's icons: an SVG drawn at the size
  (helder.canvas's `Svg`), else the smallest PNG (JPEG, WebP, GIF) at least as
  large, else the largest, scaled (an area's average down, bilinear up),
  placed on its canvas and written as PNG (`helder.image.PngEncoder`).
  One 1024 px icon, or one SVG, is enough.
- **Android** (`Android.resources`, `helder.pack.android.Arsc`): a
  resource table (`resources.arsc`) and `res/` in the APK: the launcher's
  adaptive icon (`@mipmap/ic_launcher`, also the round icon): its
  foreground the maskable icon (its 80% safe zone on the layer's 66 dp),
  else the icon of any purpose inside the safe zone, 108 dp at xxxhdpi;
  its background `background_color`; a monochrome layer (Android 13's
  themed icons) from a monochrome icon. Or the app's own layers,
  `targets.android.adaptiveIcon` (`{"foreground", "background",
  "monochrome"}`: each a full 108 dp layer, its safe zone the middle 66
  dp, drawn whole; the background a picture, a gradient or clouds, not
  only a colour). The activity's theme
  `Theme.Helder` (the framework's it had as its parent): the splash's
  colour as `windowSplashScreenBackground` (Android 12's SplashScreen) and
  `windowBackground` (before it, and Android 10 and 11), the splash image
  as `windowSplashScreenAnimatedIcon` (288 dp, inside the 192 dp circle;
  without one, the system shows the launcher's icon); their dark variants
  in the night configuration. The label is the manifest's.
- **iOS** (`Ios.artwork`), without Xcode: the app icon's asset catalog,
  `Assets.car` (`helder.pack.ios.AssetCatalog`, as actool compiles an
  Xcode 15 single-size icon: iPhone's 120 and 180 px, iPad's 152 and 167
  px, the App Store's 1024 px marketing icon) with the loose
  `AppIcon60x60@2x.png` and `AppIcon76x76@2x~ipad.png` actool writes
  beside it, named in `CFBundleIcons` (and `~ipad`'s: `CFBundleIconName`
  AppIcon), opaque (the maskable icon full bleed, else the icon on
  `background_color`); the
  launch screen `UILaunchScreen`'s `UIImageName`: an image of the splash's
  background as large as the largest screen with the splash image (else
  the icon) at 160 points in its middle (`LaunchImage@3x~iphone`,
  `LaunchImage@2x~ipad`), since `UIColorName` needs an asset catalog's
  colour; all sealed by CodeResources.
- **Web** (`Page.app`): `helder build --target web` copies the manifest
  and the files it names beside the page, makes `apple-touch-icon.png`
  (180 px, opaque) and links them: `<link rel="manifest">`, `theme-color`,
  `description`, an `icon` link per icon of any purpose,
  `apple-touch-icon`. The page's background is the splash's (its dark one
  under `prefers-color-scheme: dark`) and the splash image (else the icon)
  shows in its middle until the program runs. `helder dev` links the
  same from the project's directory.
- **Not yet**: desktop apps have no bundle to put an icon in (helder
  builds a bare executable: a macOS `.app` with an `.icns`,
  `helder.pack.apple.Icns` written already, a Windows executable's icon
  resource, a Linux `.desktop` file are to come); iOS's dark and tinted
  icons and dark launch screen (more of the asset catalog); Android's legacy (pre-adaptive) icons are not needed
  (minSdk 29); the web's splash is not the installed PWA's (the browser
  makes that from `background_color` and the icons).

## helder.run

`helder publish --run` puts the web build on helder.run (`Run.hx`): the
app itself at `<run.name>.helder.run`, full screen on helder.run's own page
and on an origin of its own, and its page at `helder.build/<run.name>` (its
name, screenshots, Play or Open, its stores' links, a QR code, what it can
access). helder.build lists it on https://helder.build/explore when
`run.listed` is true. `helder share` does the same without an account:
unlisted, at a random name, for a week.

```sh
helder login                         # GitHub, through helder.build (its device flow); the token in helder's config directory
helder publish --run                 # this project's run block: <run.name>.helder.run and helder.build/<run.name>, a new version
helder publish examples/planets --run --dry-run   # built, what would be uploaded printed
helder share examples/planets        # anonymous: https://quiet-otter-k7m2.helder.run, for a week
helder logout
```

- **What is uploaded**: the web build (`bin/run/<name>`: the module, its
  assets, fonts, helder's runtime modules), the icon at 512 px, and the
  screenshots: `run.screenshots` when helder.json names images (an
  override), else the project's stories with `store: true`, the stores'
  own screenshots (helder.story's README), rendered as `--screenshots`
  renders them but at a window's size, 1280x800 (a phone's, 390x844 at
  2x, when `orientation` is `portrait`), without the caption band, in the
  stories' order, at most 8 (`bin/shots/run`); else, with no store story,
  one screenshot of the program taken headless (`helder run --headless`;
  either way a GPU or Mesa's llvmpipe; `--no-screenshot`: none). Not the page: helder.run renders its own from the page's values
  (`Page.written`), and accepts only helder's own runtime modules (their
  hashes from helder's main), so only helder's runtime runs there; a
  runtime changed locally is refused. Files are content-addressed: what
  helder.run has (a font, the runtime) is not sent again.
- **Who may publish**: `helder login`'s account (`HELDER_TOKEN` gives a
  token instead); in GitHub Actions the workflow's OIDC token (`permissions:
  id-token: write`, no secret), whose repository the project trusts: its
  first publish from GitHub makes it the repository owner's and trusts that
  repository, helder.build's settings trust others (helder's own examples:
  `.github/workflows/run.yml`). `HELDER_API`: another helder.build (a local one).
- **The address**: `run.name` (3 to 40 lowercase letters, digits and
  hyphens), else the app's name made one; the first to publish an address
  owns it.

## Publishing to the stores

`helder publish` (`Publish.hx`) builds the release, signs it and uploads
it through the store's own API, without fastlane, Transporter or Xcode
(HTTP by curl). With no destination it publishes to each one `helder.json`
names (helder.run's first, when it has a run block, then each target's
`publish` list):

- **`--play`**: the App Bundle (below: the release key's), an access
  token: `GOOGLE_OAUTH_ACCESS_TOKEN` or `HELDER_PLAY_ACCESS_TOKEN` as it
  is (CI's, short-lived, through Workload Identity Federation:
  google-github-actions/auth with `token_format: access_token`), else a
  service account's JSON key (`HELDER_PLAY_SERVICE_ACCOUNT`: its path or
  text; the manifest's `"android": {"serviceAccount"}`;
  `GOOGLE_APPLICATION_CREDENTIALS` when it is one) signed for one: an
  RS256 JWT (`helder.pack.Jwt`, `Rsa`) for the `androidpublisher` scope,
  exchanged at the key's `token_uri`; then the Play Developer Publishing
  API's edit: `edits.insert`, `bundles.upload`, `tracks.update`
  (`--track`: `internal`, the default, `alpha`, `beta`, `production`; the
  release `completed`, or `--draft` for an app never published yet),
  `edits.commit`. The service account needs the app's release
  permissions in Play Console (Users and permissions), and Play needs a
  first bundle uploaded by hand to create the app's listing.
- **`--testflight`**: the `.ipa` signed for distribution (below), an
  ES256 JWT of the App Store Connect API key (`HELDER_ASC_API_KEY`: JSON
  of `key_id`, `issuer_id` and `private_key`, the `.p8`'s text; or
  `HELDER_ASC_KEY_ID`, `HELDER_ASC_ISSUER_ID`, `HELDER_ASC_KEY`: the
  `.p8`'s path or text;
  `helder.pack.Jwt` with `P256`), the app found by its bundle id
  (`/v1/apps`), then Apple's build upload API (App Store Connect API,
  2025): `POST /v1/buildUploads` (the versions, `IOS`), `POST
  /v1/buildUploadFiles` (the file's name, size, `com.apple.ipa`), each
  of its upload operations' parts sent where it says, `PATCH` the file
  uploaded with its MD5, the upload's state read back. No Transporter.
  TestFlight lists the build once App Store Connect has processed it;
  its validation's errors come by email and on the build's page.
  With **`--submit`**: the build waited for while App Store Connect
  processes it (`HELDER_ASC_WAIT` seconds at most, 3600), put on the
  editable App Store version and sent for App Review (a review
  submission, its item, submitted).
- **`--dry-run`**: built and signed, the token got, what is there read
  (the track's releases; the app's id), what would change printed;
  nothing uploaded, nothing committed (Play's edit deleted).
- **`--screenshots`**: the project's stories marked `store: true`
  (helder.story's README) rendered at the stores' sizes with their
  captions into `bin/store` (`helder.cli.Shots`: a program of the
  entry's story files, `*.story.hx` or a TypeScript program's
  `*.story.ts(x)`, built for this machine and run: a GPU, or Mesa's
  llvmpipe; none under the entry's directory, the working directory's
  as `helder test` finds them), with the review sheet
  `bin/store/review.html`. The same stories are helder.run's screenshots
  (`--run`), so the stores and helder.run show the same moments.
- **`--listing`** (with `--play` or `--testflight` for one store, else
  both; `--locale`, en-US): helder.json's `listing` (`Listing.hx`: a few
  fields both stores share, mapped onto each one's; under `play` and
  `appStore` the stores' resources by their API names, their attributes
  sent as they are, so a field a store adds works without helder knowing
  it; `locales` for other languages; `"${NAME}"` from the environment),
  only what differs from the store's sent: Play's listing and details;
  App Store Connect's app, app info (name, subtitle, privacy URL,
  categories, the age rating: questions still unanswered named), the
  version (made when there is none) and its listing, the review's
  contact. Play's icon (the app's, 512 px) and feature graphic (the first
  story with `feature: true`, 1024x500) go with the screenshots. And the
  same screenshots against each store's listing by hash, those not ours deleted and ours missing uploaded:
  Google Play's image types (`phoneScreenshots`) in an edit, committed;
  App Store Connect's version being prepared, its localization's
  screenshot sets by display type (`APP_IPHONE_67`, `APP_IPHONE_65`,
  `APP_IPAD_PRO_3GEN_129`, made when missing), each screenshot reserved,
  sent and committed with its MD5. With `--dry-run` the changes are only
  listed, in the review sheet too.

Checked against a stand-in of both APIs (`tests/pack/publish.mjs`, the
pack lane: the JWTs verified with the keys' public halves, every call
and its order, the uploaded bytes against the files, the dry run's
calls); a real upload needs the owner's accounts (`helder.pack`'s README).

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
  `helder.os.android.Glue` in it; `@:helder.android.views` on a class
  the program makes that shows Android's views as the activity's content:
  none does now, a drawn window needs NativeActivity's surface; tested on
  the counter example), and APK Signature Scheme v2
  (ECDSA P-256 with SHA-256, RFC 6979's nonces: `P256`, `Der`; v2 only,
  which minSdk 29 allows). targetSdk 36 by default; predictive back
  opted out (`enableOnBackInvokedCallback="false"`), so the back key and
  gesture still reach `App.onBack` as `AKEYCODE_BACK` (an
  `OnBackInvokedCallback` of Glue's is to come). Debuggable with the
  debug key; with a release key not.
- **Android's release signing and App Bundles**: `HELDER_ANDROID_UPLOAD_IDENTITY`
  (the certificate and the key in one PEM), or `HELDER_ANDROID_SIGNING_CERTIFICATE`
  and `HELDER_ANDROID_SIGNING_KEY` (PEM, RSA or P-256: each a file's path
  or its text), else the manifest's `"android": {"signing": {"certificate",
  "key"}}`, sign the APK (v2, RSA PKCS#1 or ECDSA) instead of the debug
  key, not debuggable; one without the other is an error. `helder build
  --target android --release --bundle` writes `bin/android/<name>.aab`
  (`helder.pack.android.Aab`): both ABIs built (`android-arm64`,
  `android-x86_64`), the manifest and resource table in aapt2's protobuf
  forms (`Pb`), the res files, `classes.dex` and the assets under `base/`,
  `BundleConfig.pb`, signed with JAR signing (v1: `META-INF/MANIFEST.MF`,
  `HELDER.SF`, a PKCS#7 `HELDER.RSA` or `.EC`) by the release key, Play's
  upload key; a bundle without one is an error. A keystore is not read:
  `keytool -importkeystore -srckeystore upload.jks -destkeystore
  upload.p12 -deststoretype PKCS12`, then `openssl pkcs12 -in upload.p12
  -nokeys -out upload.pem` and `-nocerts -nodes -out upload.key`. Checked
  by the pack lane (the protobufs read back, the JAR digests, `jarsigner
  -verify`, `openssl cms -verify`; bundletool `validate` and `build-apks`
  in CI's android job).
- **Android's runtime objects** (`android-arm64`, `android-x86_64`'s
  `rt.o`, `ssl.o`, `uv.o`) are not on npm: @hxmc/cli's package.json names
  the GitHub release of benmerckx/hxmc built from the same sources
  (`"hxmc": {"rt": "rt-<16 hex>"}`). On first use `build`, `run` and
  `dev` fetch the target's `<target>-<object>.gz` assets from it (curl),
  gunzip them into `<helder's cache>/rt/<tag>/<target>/`, say so in one
  status line (`fetching android-arm64's runtime objects, once`) and add
  that directory to the compiler's `HXMC_RT_DIR` (`Runtime.hx`); a new
  hxmc's tag fetches again. A directory already in `HXMC_RT_DIR` holding
  the target's objects is used instead, nothing fetched;
  `HELDER_RT_URL` names another place for the releases
  (`<it>/<tag>/<asset>`: a mirror, a `file://` directory).
- **The debug key**: the user's own, made on first use and kept, so a
  reinstall keeps the signature: `HELDER_ANDROID_KEY` names its file or
  holds its text (a CI secret's: newlines, or `\n` written for them), else
  the manifest's `"helder": {"android": {"key"}}`, else
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
  `.ipa` zips the bundle under `Payload/`. An iPhone's build (`--target
  ios`) has Xcode's `DT*` keys and `PrivacyInfo.xcprivacy` (no tracking;
  the required-reason APIs the executable imports, `stat` and
  `mach_absolute_time` among them, with the reasons an app of its own
  gives, and the manifest's); signed for the App Store and TestFlight
  when an identity is given (below), else ad hoc, which no device runs.
- **Signing for distribution** (`helder.pack.apple.CodeSign`, no
  codesign, no Mac): `HELDER_IOS_IDENTITY` (the certificate, its chain and
  the key in one PEM), or `HELDER_IOS_CERTIFICATE` (the Apple Distribution
  certificate with its chain, PEM), `HELDER_IOS_KEY` (its private key,
  PEM, RSA or P-256, unencrypted) and `HELDER_IOS_PROFILE` (the App
  Store provisioning profile, optional: without it the build fetches
  the bundle id's active App Store profile for the certificate from App
  Store Connect, `/v1/bundleIds` and their `profiles`, with the API key
  below), each a file's path or its contents (PEM's
  text; the profile's base64, as CI secrets hold them), else the
  manifest's `"ios": {"signing": {"certificate", "key", "profile"}}`
  (paths from the project). Some of them without the others is an error
  naming the missing; so are a key of another certificate, an encrypted
  key, a profile without the certificate, expired, for another bundle id
  or not granting an entitlement the app asks for. From Keychain's .p12:

  Apple's WWDR intermediate (G3 or G4) is added when the PEM has the
  leaf alone (`helder.pack.apple.Wwdr`), and a key or `.p8` is read
  however it was pasted (on one line, `
` for its newlines, CRLF, its
  base64 without the armour: `Identity.pem`):

  ```sh
  openssl pkcs12 -in distribution.p12 -nokeys -out distribution.pem     # (-legacy for an older .p12)
  openssl pkcs12 -in distribution.p12 -nocerts -nodes -out distribution.key
  HELDER_IOS_CERTIFICATE=distribution.pem HELDER_IOS_KEY=distribution.key \
    HELDER_IOS_PROFILE=AppStore.mobileprovision helder build --target ios --release
  ```

  The bundle gets `embedded.mobileprovision`, CodeResources is sealed
  again over every file, and the executable's ad hoc signature is
  replaced by a distribution one: the CodeDirectory (SHA-256 pages; the
  special slots of Info.plist, the requirements, CodeResources, the
  entitlements as XML and DER), codesign's designated requirement
  (`anchor apple generic`, the leaf's common name, WWDR's intermediate),
  the entitlements (the profile's `application-identifier`, team,
  `get-task-allow` false, `beta-reports-active`, keychain access group,
  with the manifest's file's), and a CMS signature with Apple's cdhash
  attributes; `LC_BUILD_VERSION`'s SDK becomes `sdk.version`. Uploading
  the `.ipa` to TestFlight needs App Store Connect: on a Mac, `xcrun
  altool --upload-app --type ios --file bin/ios/<name>.ipa --apiKey <key
  id> --apiIssuer <issuer id>` (the key `~/.appstoreconnect/private_keys/AuthKey_<key id>.p8`), or Transporter
  (`iTMSTransporter -m upload -assetFile <ipa> -apiKey ... -apiIssuer ...`, on Linux too);
  its validation is the test of what was not testable here (`helder.pack`'s
  README).
- **An app's identity**: the project's `helder.webmanifest` (below); else,
  deprecated (a warning says so), `package.json`'s `"helder"` key
  (`App.hx`): `"id"` (both platforms'), `"label"`, `"version"` (the
  build's number), `"versionName"`, `"orientation"`, `"fullscreen"`,
  `"android": {"permissions", "minSdk", "targetSdk", "key"}`, `"ios":
  {"minVersion", "entitlements"}`, as the manifest's members below (no
  icons, no splash). With both, the manifest's wins.
- **run**: on Android `adb -s <id>` installs (`install -r`), starts (`am
  start`, after `force-stop`) and streams logcat's `hxmc` tag (the
  program's stdout and stderr) until the app's process ends; on iOS `xcrun
  simctl` boots the simulator when it is not, installs, and launches with
  `--console` (its output here, its end the command's).
- **assets** (helder.asset: src/helder/asset/README.md): after each build
  the keys whose markers the output has are the program's assets
  (`AssetStep`: their files found under the class paths, then the
  project; a manifest in helder's cache); desktop's executable has them
  built in (the macro's resources, `-D helder.asset.keep=<file>`: those a
  last build used; a build whose built-in files differ is made again);
  the web's beside the module (`assets/<key>`, `<name>.wasm.assets.json`
  for those read before main, which the page passes to browser.mjs);
  Android's APK in `assets/`, stored and 4-byte aligned; iOS's bundle in
  `assets/`, sealed by CodeResources before the link. Dev builds have none
  built in or copied (read from this machine's disk; Android's app asks
  for them, below).
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
  simctl's. A changed asset is sent as on desktop (`Assets.changed`); the
  Android app asks for an asset's bytes on a connection of its own, `asset
  <key>` (`ok`, then the bytes; `missing`), the simulator's reads it from
  this machine's disk.

## The dev loop

Ported from @hxmc/cli's `dev.mjs`, and speaking the same protocol to the
program (`helder.dev.Hot`, `helder.os.App`'s client, the page):

- the compiler is a resident compilation server (`--server-connect`, a
  request at a time on one connection), each change's files invalidated
  first (`server/invalidate`), `-D disable-hxb-cache`;
- what the last build read is watched (`helder.async.SampledWatcher`,
  esbuild's polling): the module files a `--macro helder.cli.Deps.write`
  lists (under the class paths, but helder's own when it is a package),
  their directories' listings, the program's assets (the files whose
  markers the build has: AssetStep's manifest), package.json and
  helder.hxml; the set replaced after each build. Each 100 ms tick checks the 16 paths that
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
  files at `/`. A reload swaps the new build into the same page;
- a change to an asset builds nothing (`asset <key> · sent, nothing
  built`): natively the program is told on its connection (the devtools
  protocol's notification `Assets.changed {key}`) and loads the file again
  behind the same handle (helder.asset: an image's pixels, a font's glyphs,
  a model's meshes swapped in place; `value`'s readers run again), the
  page by `{"type":"asset","key"}` on its WebSocket (the module fetches
  `/__hxmc/assets/<key>`; the files read before main at
  `/__hxmc/app.wasm.assets.json`).

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

## Headless runs

`helder run --headless [entry] [options]` (`HeadlessCommand.hx`,
src/helder/headless) runs any app, Haxe or TypeScript, a UI (`UiWindow`)
or a scene (helder.gfx, helder.scene), without a display, so an agent or
a test can see and drive it. It is run's flag rather than a command of
its own because it is a run of the same program (the same entry, built
the same way, its arguments after `--`); only where it draws and what
drives it differ, as Rune's tools are its programs' flags.

```sh
helder run --headless examples/todo --snap out.png [--at 0.4|end|mark:end+0.5] [--size 480x560] [--scale 2] [--theme dark] [--reduced-motion]
helder run --headless examples/todo --tree tree.json [--at T]
helder run --headless examples/todo --script demo.json --snap a.png --at mark:added --snap b.png --at end
helder run --headless examples/todo --script demo.json --frames 30 --every 3 --start 0.2 -o frames/
helder run --headless examples/todo --script demo.json --video demo.mp4 [--fps 60] [--duration 3|auto] --keys [--keys-at top-right] --pointer
helder run --headless examples/todo --script demo.json --trace run.jsonl
helder run --headless examples/glow --snap glow.png --at 0.5 --size 320x240
```

- **The build**: `-D helder.headless` into `bin/headless/<name>` (a
  release build's otherwise; a build without the define has none of it:
  each hook is behind it, or behind a constant that folds). Its options go
  to it as JSON in `HELDER_HEADLESS`, which is what `helder.headless.Headless`
  reads (the built program runs headless again with the same variable).
  With `--headless`, `-o/--out` is the frames' directory.
- **The windows**: helder.os's `Window` is a `HeadlessWindow`: a headless
  `Surface` of the window's size in points (`--size`, else the program's)
  times `--scale` (1), which the real renderer draws into offscreen
  (helder.gfx: Linux's GL on an EGL pbuffer of Mesa's surfaceless
  platform, Metal's and D3D11's offscreen targets); `Device.endFrame` reads
  the first window's frame back for the outputs. `App.prefersDark` is
  `--theme`'s (light by default); `--reduced-motion` sets helder.ui's
  `Clock.reducedMotion` (Style's transitions of transform and shadow, and
  Motion's transition and spring, jump; fades and colours still ease).
  `FileDialog.open` takes the script's next `file-dialog` answer.
  helder.os's `Store` starts empty and stays in memory (what an earlier
  run or the user's own copy of the app kept changes nothing; the run
  keeps nothing).
- **The clock**: `App.run` never waits: each turn is frame n at n / fps
  seconds (`--fps`, 60) of a virtual clock (`helder.headless.Time`), which
  `App.frame`, helder.ui's `Clock` and events (`Ui.now`), Pointers'
  times and helder.async's timers read; the script's events due by a
  frame are handled before it, each at its own time. The run ends at the
  last time an output needs (`--at`, the frames', the video's), or at the
  script's end without one; a program that closes its window before then
  fails the run, naming what was not written.
- **Times** (`--at`, `--start`): seconds; `end` (the default: the
  script's `end` mark, else a second after its last step ends, else 1 s);
  `mark:<name>`, `mark:<name>+0.5`, `mark:<name>-0.2`. Each `--at` is the
  time of the `--snap`s and `--tree`s before it that have none (one before
  them all: theirs).
- **Scripts** (`--script`, `Script.hx`): a JSON list, or `{"events":
  [...]}`, of steps `{"t": seconds, "type": ...}`: `move`, `down`, `up`
  (`button`: left, middle, right), `tap` (`hold`, 0.05 s), `double-click`
  (`hold`, `gap`: 0.15 s), `drag` (`dx`, `dy` points over `dur`, 0.3 s),
  `wheel` (`dx`, `dy` points), `key` (`name`: Enter, Escape, Tab,
  Backspace, Delete, Space, ArrowLeft..., Home, End, PageUp, F1...,
  or one character; with `shift`, `ctrl`, `alt`, `cmd`, `secondary`:
  Command on a Mac, Control elsewhere; a character typed when no Control,
  Alt or Command is held), `key-up`, `type` (`text`, a key a character,
  `every` seconds apart), `resize` (`width`, `height` or `dw`, `dh` points,
  over `dur`, eased), `menu-pick` (`id` or `label`: the open pop-up menu's
  item; `menu-cancel`), `drop` (`files`: paths dropped from the system on
  the target, a Drop event), `file-dialog` (`path`: the next file dialog's
  answer, whenever it opens; `file-dialog-cancel`), `mark` (`name`).
  Pointer steps aim at `x`, `y` (points), or at a node: `tag`, a `path`
  of tags (`list/checkbox`: a descendant chain, as CSS's), `role` (ARIA's:
  `button`, `checkbox`, `textbox`) and `label` (its accessible name, else
  its text), each given narrowing it; `index` the n-th match (0); at its
  centre, or `ox`, `oy` from its top left; without any, where the pointer
  is. A node is found when its step comes, as the tree is then; one not
  there fails the run (`helder headless: step 6 (tap at 1 s): no node
  checkbox (tags shown: draft, add, list, ...)`), as does one not shown, a
  window without a node tree (a scene's: aim at x, y), a menu-pick with no
  menu open.
- **`--tree`** (helder.ui's `UiInspector`): `{time, frame, size, pointer,
  nodes}`, each node displayed in tree order (the root's children, then
  the overlay's popups): `id` (stable for the run), `tag`, `path` (its
  tags from the root down), `parent`, `depth`, `role`, `label`, `text`,
  `value`, `checked`, `selected`, `posinset` and `setsize` (an item's place
  in its set: a virtual list's rows among all of them), `disabled` (the
  accessibility tree's), `rect`
  ([x, y, width, height] where it is drawn, in points: through its
  ancestors' scrolling and transforms), `opacity` (through its
  ancestors'), `fill` and `color` (`#rrggbb`, `#rrggbbaa`), `hover`,
  `press`, `focus`, `moving` (a transition running on it, or its rect or
  opacity changed since the frame before), `source` (where markup wrote
  it: `{file, line, col, end: {line, col}, offsets: [start, end]}`, its
  tag's span, file a full path, bytes and 1-based lines and columns) and
  `component` (the innermost component mounting it: `{name, call,
  definition}`, two such spans, the definition null for helder's own
  from TSX). A scene has `"nodes": null`.
- **`--trace`**: a JSON line a frame, `{t, frame, nodes}`, each tagged
  node (a tag other than view, text, span, b, i, scroll) with its `rect`,
  `opacity` and `moving`.
- **`--stats`**: each frame's work in milliseconds of the machine's
  clock (from its script events to its frame drawn, before the outputs
  are written: a keystroke's frame is the time from the key to the frame),
  the GC bytes it allocated and the collections (hxmc's `GcStats`), and
  its input events by kind (keys, wheels, pointers), and what it recorded
  on the GPU (helder.gfx's `FrameCounts`: `passes`, `draws` (draw calls),
  the `instances` they drew, `pipelines` and `textures` set; helder.ui's
  renderer's `quads`, the bytes of them `uploaded`, its CPU `uiMs` from
  painting to its pass encoded, of that `uploadMs` (the glyph atlas's and
  the quads' upload) and `encodeMs` (the draw calls: the driver's work
  in them, Mesa's llvmpipe's vertex stage too), the GC bytes it
  allocated (`uiBytes`, painting included); all 0 for a frame that
  drew nothing), as one JSON file `{fps, frames: [{frame, t, ms,
  gcBytes, gcs, keys, wheels, pointers, passes, draws, instances,
  pipelines, textures, quads, uiMs, uploadMs, encodeMs, uploaded,
  uiBytes}]}`
  written at the end, and a summary of the frames drawn printed (each
  column's median, the passes' and draw calls' largest). The machine's
  times: not part of the determinism below (tests/bench/code.mjs reads
  it: the code-bench lane).
- **`--frames N -o dir`**: `frame_0000.png`... from `--start`, every
  `--every`-th written (named by their frame); `-o` without `--frames`:
  `--duration`'s (auto: to the end). A sequence keeps its first frame's
  size (a window resized during it cropped or padded).
- **`--video`**: helder has no encoder yet: the run writes its frames as
  PNGs beside the video (`<name>.frames/`), then ffmpeg (on the PATH;
  without it the command says so before building) encodes them, `.mp4`
  as H.264 yuv420p with `+faststart`, `.webm` VP9, `.mov` ProRes 4444, and
  the frames are removed. `--frames N` or `--duration` (auto: to the end)
  from `--start`. A platform encoder (Media Foundation, AVFoundation) is
  for later.
- **`--keys`, `--pointer`** (`Overlay.hx`): keycaps of the script's keys
  (typing within a second one cap, a key again within a second counted:
  `↓ ×2`; ⌃⌥⇧⌘, named keys as ↩ ⎋ ⇥ ⌫ ␣ ← →), springing in and fading out
  1.5 s after their last key, three at most, at `--keys-at` (bottom-left,
  bottom, bottom-right, top-left, top, top-right) in `--keys-theme`'s
  colours (else `--theme`'s); a ripple at each press. Drawn on the CPU
  (helder.canvas) over the frame after the app's, so they are in `--snap`,
  the frames and the video, never in `--tree` or `--trace`.
- **Determinism**: the same script gives byte-identical outputs on one
  machine (the headless-run lane checks it): the virtual clock; the
  jobs on helder.jobs' threads awaited at each frame (every run handed to
  the pool by then lands in that frame, `Loop.settle`, not whenever its
  thread ends: the viewer's decodes); Math.random and Std.random seeded (`--seed`, 1: hxmc's xoshiro256**
  state from it); text by helder's own engine (helder.text, the fonts
  found on the machine: DejaVu Sans for the examples); Linux's GL forced
  to llvmpipe (`LIBGL_ALWAYS_SOFTWARE`), no `DISPLAY`; `LC_ALL` and `LANG`
  C.UTF-8, `TZ` UTC. Across machines, Mesa's releases and the fonts
  installed move text's edges a little: compare with a tolerance.
- **Not yet**: wasm (a headless run is native: its outputs are files),
  phones; a window resized by a script on Metal and D3D11 (their offscreen
  targets keep their first size; GL's pbuffer is made again); several
  windows composited (the first window's frame and nodes are the
  outputs); the time `Sys.time()` and `Date.now()` read stays the system's
  (a program animating from them is not frame exact: `App.frame.time` is
  the clock), as do haxe.Timer's delays; helder.jobs' work runs on its
  threads in real time, so a result the script waits for needs a margin
  (the viewer's decode in tests/headless/viewer.json has most of a
  second).

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
  HXMC_RT_DIR. An empty or set HXMC_RT_DIR adds to the launcher's search
  too (0.1.0-nightly.20261028.23a0a79), and @hxmc/cli's package.json
  names its release of Android's objects (`hxmc.rt`), which `Runtime`
  fetches: no matching of rt.o's bytes against releases.
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
  tests/pack/Hello.hx, tests/pack/Screen.hx (a window: CI's emulator and
  simulator run it) and a project with an app's options (tests/pack/project:
  an id, a permission, iOS's minimum and entitlements, landscape,
  fullscreen) built for
  android-arm64, android-x86_64, ios-arm64 (.ipa) and ios-sim-arm64 (.app)
  by `helder build`, checked by tests/pack/PackCheck.hx: the zip's layout
  and 16 KB alignment, the manifest, the library (readelf: 16 KB segments,
  soname, the export, DT_NEEDED), screenOrientation, the v2 signature's digest recomputed and
  openssl verifying it (apksigner, zipalign and aapt when on the PATH:
  CI's); the bundle, Info.plist (its orientations, UIRequiresFullScreen,
  UIStatusBarHidden), the program built with -D helder.fullscreen (its
  line in the binary), the Mach-O's build version, its code
  signature with its page hashes and special slots (1 Info.plist, 2 the
  requirements, 3 CodeResources, 5 the entitlements). Then `helder run`
  and `helder dev` against stand-ins for adb and xcrun (tests/pack/fake,
  tests/pack/dev.mjs: the first build installed and started, the app's
  connection, a reload's library fetched by `lib <n>` and the same as the
  build's, the simulator's dylib, the app closed and started again by the
  next change). The runtime objects: tests/pack/runtime.mjs fetches
  macos-arm64's from npm (@hxmc/darwin-arm64) and Android's from the
  release @hxmc/cli's package.json names (`hxmc.rt`; not on npm); without
  them those builds are skipped (PACK_REQUIRE=1: a failure). The CLI's own
  fetch: a build with no HXMC_RT_DIR and an empty cache, from a stand-in
  release of those objects (tests/pack/release.mjs, `HELDER_RT_URL` a
  `file://` directory): the status line, the objects in
  `<cache>/rt/<tag>/`, the APK checked.
- **Only in CI, untested until it runs** (`.github/workflows/ci.yml`; no
  emulator, simulator or Mac where it was written): the `android` job,
  an x86-64 emulator (API 34) running tests/pack/android.sh (`helder run
  --target android`'s hello line from logcat, then the APK by adb alone)
  and tests/os/dev/dev-android.mjs (`helder dev --target android`: two
  edits swapped into the same process, the state kept); the
  `ios-simulator` job on macos-15, the pack lane (with codesign --verify
  and plutil -lint) and tests/pack/ios.sh (`helder run --target ios -d
  <a new simulator>`'s hello line); both then run tests/pack/Screen.hx
  (its window's size, scale and safe area, the display's frames, the bars
  hidden, a rotation on Android, the background and back: checked by
  tests/pack/screen.mjs). Never yet on a real phone.

Not yet: the devtools' agent on the web (the page relaying it), the page
held back while the module is generated (dev.mjs's `hxmc dev:
generating`), native watchers, iOS devices
(signing), Android's release signing, icons in the APK and the bundle,
booting an emulator, `helder new`, `helder doctor`.
