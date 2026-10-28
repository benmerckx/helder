# helder.asset

Files of the program by path: images, fonts, models, sounds and bytes,
anywhere in the project (no `assets/` folder), checked when compiling,
taken by every build that still uses them after dead code elimination,
read one way on every platform, and reloaded in place under `helder dev`.
A package of its own, not `scene`'s: ui, text and plain programs load
files too, and each kind's loader lives with what it makes (an image's
in `ImageAsset`, a model's in `helder.scene.render.Model`), so a program
links only the kinds it names.

```haxe
import helder.asset.Asset;

@:coroutine static function start() {
  var ship = Asset.model("models/ship.glb").load();   // suspends until loaded
  ship.instantiate(world, device);
}

// several at once: tasks
Async.scope(task -> {
  var a = task.async(_ -> Asset.image("ui/icons/sword.png").load());
  var b = task.async(_ -> Asset.font("fonts/Inter.ttf").load());
  Async.all([a, b]);
});

// the frame loop, without suspending
var icon = Asset.image("ui/icons/sword.png");
if (icon.ready) draw(icon.peek());
```

| | |
| --- | --- |
| `Asset.image(path)` | an `helder.image.Image`: a PNG decoded as a GC-free job (`ImageJobs`), JPEG, GIF and WebP by `Image.decode` |
| `Asset.font(path)` | a `helder.text.FontFile` (its first face), its faces added to `SystemFonts` (ui finds them by family) |
| `Asset.model(path)` | a `helder.scene.render.Model`, its names typed from the file (`model.nodes.LeftHand`), as `Model.of` types them |
| `Asset.sound(path)` | the file's bytes (no decoding yet) |
| `Asset.bytes(path)` | the file's bytes |
| `Asset.embed(path)` | the bytes built into the code itself, there at once (small files; not bundled, not reloaded) |

Each returns a handle at once, its load started: one per kind and path
(the same handle each time). `load()` is a coroutine: it returns the value
once loaded (at once if it is) and throws an `AssetError` if the load
failed. Without suspending: `ready`, `peek()` (null until loaded), `state`
(`Loading`, `Ready`, `Failed(error)`). `value` is the value as a signal
(helder.view): read in markup, a memo or an effect it is tracked, and its
readers run again when a reload replaces it; read before the asset is
loaded it throws `AssetPending` (a mistake outside of a boundary that
waits for it: `load()` in a coroutine, `ready` or `peek()` in the frame
loop), after a failure the `AssetError`. Loads run on the
main thread's loop (helder.async: `App.run` turns it; `Assets.poll()`
for a loop of the program's own, which `Stages.frame` calls).

## Paths

A path is the file's key on every platform (`AssetPath`): relative, `/`
between its parts, none of them empty, `.` or `..`, no backslash, colon
or control character, and the case of the file on disk (Android's and
the web's file names are case-sensitive, macOS's and Windows' disks
usually not). It is looked for under the class paths, then under the
project (the folder of package.json; `-D helder.root`, which the CLI
gives). A path that breaks a rule, or names no file, or a file in
another case, is an error at the call:

```
Asset.bytes("files/Kept.txt"): "Kept.txt" is "kept.txt" on disk (paths are case-sensitive on Android and the web)
```

## What a build takes

Each call names its key in a marker, a string literal of its own
(`helder.asset.key:<key>\x01`; `now:` for `Model.of`'s, read before
main). hxmc emits the literals of the code it keeps, so the keys whose
markers the output has (the executable, the library, the module) are the
files the program uses (`Bundle.scan`); a file named only in code that
dead code elimination removes is in no bundle. After each build `helder`
(`helder.cli.AssetStep`) reads them from the output, finds their files
as the macro does, and:

- **desktop** (Linux, Windows, macOS): the files are in the executable,
  resources of hxmc's (`Context.addResource`, from the macro: a cached
  module keeps them), each after a header naming it; read through
  hxmc's table of resources (`Files`: no file opened, the system pages the
  data in when it is first touched; one copy out of it per load). The
  macro builds in the files a last build used (`-D helder.asset.keep`,
  a file in helder's cache; every file named when there is none): when the
  output's differ from those it uses (a reference added, or left in dead
  code only), the CLI writes them and builds again (the modules naming
  assets typed again; the rest from the module cache);
- **Android**: the APK's `assets/<key>`, stored and 4-byte aligned, read
  through `AAssetManager` (`AAsset_getBuffer`: the APK's pages mapped, one
  copy out);
- **iOS**: the app's `assets/<key>`, beside the executable, sealed by
  `_CodeSignature/CodeResources` before hxmc links and signs (the last
  build's files, then the same check);
- **the web**: `assets/<key>` beside the module, fetched (the page's base);
  those read before main listed in `<module>.assets.json`, which
  browser.mjs fetches while the module loads (`Model.of`'s).

Dev builds build nothing in: their files are read from this machine's
disk (Android's app asks `helder dev` for them), so a phone's reload sends
only its library. A build of hxmc's own, without the CLI, builds every
file named into a desktop executable and copies them beside a web module.

Cost, natively (Linux x86-64): an asset adds its bytes to the executable
and a header of 18 bytes and its key (32 MB: 33.76 MB against 0.2 MB
without), and its
time to a warm build (the same 32 MB: 0.71 s against 0.28 s: the module
cache's copy of the resource, hxmc writing it, the CLI's scan of the
output); a cold load of all of it 18 ms. Programs that name none pay
nothing.

## Reloading

Under `helder dev` the files a build uses are watched. A change builds
nothing: the running program is told (natively the devtools protocol's
`Assets.changed {key}` on its dev connection, on the web the page's
WebSocket), loads the file again and puts it behind the same handle:

- an `Image`'s pixels and size replaced in the same object
  (`Image.replace`: renderers upload it again; ui's `ImageNode` lays out
  again when its size changed);
- a `FontFile` replaced in the same object (`FontFile.replace`: a new id,
  so atlases draw its glyphs again; ui lays its texts out again);
- a `Model`'s meshes' primitives and materials replaced in the mesh
  objects its instances draw (`Model.replace`; their nodes, morphs and
  skins stay as they were made: a changed hierarchy shows in new
  instances only);
- bytes and sounds: the new bytes behind the handle;

and `value`'s readers run again. A failed reload keeps the last value.
Tested natively (tests/cli/dev.mjs: an image swapped in the same Image,
with the dev host and without, a text's reader run again), in Chromium
(tests/os/dev/dev-asset.mjs), against stand-ins for adb and simctl
(tests/pack/dev.mjs: the dev APK without assets, `asset <key>`, the
notification) and on CI's emulator (tests/os/dev/dev-android.mjs).

## Tests

`AssetPath.test.hx` (the paths' rules, on Eval too) and
`tests/asset/Assets.test.hx` (natively and as wasm32-wasi: the bundle has
what runs and not a file named only in dead code; loads, several at once,
a failure, `value` a signal); the asset lane (the paths the macros reject,
`tests/asset/Checksum.hx` built for this machine and run alone in an empty
directory, built for the web: exactly its files beside the page, run under
node); the pack lane (the APK's `assets/`, the app's and the .ipa's,
CodeResources' hashes: PackCheck); CI's emulator and simulator jobs run
Checksum (tests/pack/android.sh, ios.sh: tests/asset/checksum.txt's
lines; codesign --verify).

## Not yet

Settings beside a file (`sword.png.meta`) and formats per target
(compressed textures: ETC2, ASTC, BC) would be read and applied where the
macro embeds a file and the CLI copies one (`Bundle`'s note). A Bytes
view of an embedded file without the copy (the data is read-only, and a
Bytes may be written), sounds decoded, assets by a path known only at run
time bundled (`Model.load` fetches one, unbundled).
