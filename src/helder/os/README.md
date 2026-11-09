# helder.os

Windows, input, the app loop and audio output for hxmc in pure Haxe
(`helder.os`): raw OS bindings (X11, Wayland, the Objective-C runtime, AppKit and
UIKit, Win32, Android's NativeActivity, a canvas in the browser; ALSA, CoreAudio,
WASAPI, WebAudio) and a
portable layer over them. No C of its own: the system's C APIs through
externs, COM vtables, `objc_msgSend` and `dlopen`.

## Windows and the loop

```haxe
var window = new Window("Hello", 640, 480);   // its size in points; window.surface for helder.gfx
App.run(() -> {
	// a frame (paced by the GPU's present)
}, e -> switch e.kind {
	case Close: window.close();               // the last window closed ends the loop
	case KeyDown if (e.key == 0xFF1B): App.quit();
	case _:
});
```

X11 or Wayland on Linux (the glibc mode, `-D hxmc.libc=glibc`; Wayland
when `WAYLAND_DISPLAY` is set and it connects, `HELDER_X11=1` X11's), Cocoa on macOS,
Win32 on Windows, a canvas in the browser (wasm32-wasi: `App.run` returns
and `requestAnimationFrame` runs the loop). `Event` is one object, refilled
for each event: keys as X11 KeySyms, `TextInput` characters (and an input
method's `TextEditing`), the mouse in
pixels from the top left, `Scroll` in pixels, `Resize`, `ScaleChange`,
and every pointer's events (below).

On Android (`helder build --target android`: an APK, helder.pack.android)
the window is the activity's (full screen, one per app; `new Window` waits
for it): the program runs on a thread of its own, `App.run` draws while the
activity has its window, a touch is as in the browser (below: a tap a
click, a drag `Scroll`s that glide), `Suspend` and `Resume` come when the system takes the window and
gives one back (`Surface.lost`: the GPU back end lets go of it), and what
the program prints goes to logcat (`adb logcat -s hxmc`). Text input
(`startTextInput`, once `helder.os.android.TextInput.enable()` was called:
helder.ui's drawn windows do) shows the soft keyboard and brings the input
method's compositions and commits through a hidden `EditText`; a
`ChildSurface` is a GPU view among Android's views. No clipboard there yet. Java from Haxe: `helder.os.android.Jni` (JNI's function tables,
bound like COM's by `helder.os.VTable`), `MainThread` (Java's main
thread, where views live: work handed to it, Choreographer's frames
there) and `Glue` (Java's listeners calling Haxe: helder then writes a
`classes.dex` into the APK).

On iOS (`helder build --target ios` or `ios-sim`: an app bundle,
helder.pack.ios) the window is a `UIWindow` on the whole screen (one per app),
backed by a `CAMetalLayer`: the program's main runs inside UIKit's loop
(`UIApplicationMain` comes first: `helder.os.uikit.UIKitApp`), `App.run`
draws while the app is active, a touch is as in the browser
and on Android, `Suspend` and `Resume` come when
the app goes to the background and back. No keys or text input there yet.

### Files dropped, full screen, a window's place

```haxe
App.run(frame, e -> switch e.kind {
	case Drop: open(e.files[0]);           // paths, at e.x, e.y (pixels)
	case _:
});
window.fullscreen = true;                   // the whole screen, no frame
var p = window.position();                  // the content's top left on the screen (points); null in a browser
window.moveTo(p.x, p.y);                    // put back (a setting kept across runs)
```

A drop of files is a `Drop` event with their paths (`Event.files`) and
where they fell, by each system's own means: Windows' `DragAcceptFiles`
and `WM_DROPFILES` (`DragQueryFileW`, UTF-16), macOS's dragging
destination (the window registered for `public.file-url`, its delegate
answering `draggingEntered:` with a copy when the pasteboard has file
URLs and reading them at `performDragOperation:`), X11's XDND 5 (the
window `XdndAware`; an `XdndEnter` offering `text/uri-list`, each
`XdndPosition` answered by an `XdndStatus`, the drop's
`XdndSelection` converted, the URIs' paths decoded by `UriList`, then
`XdndFinished`). Not yet in the browser, on Android or iOS, nor Wayland
(which helder does not speak yet). `fullscreen`: X11's
`_NET_WM_STATE_FULLSCREEN` asked of the window manager, Windows' borderless
window over its monitor (the frame and place given back after), macOS's
full-screen space (`toggleFullScreen:`; the getter follows once there).
`position` and `moveTo`: the content's top left, in points (X11: pixels;
the frame's extents, `_NET_FRAME_EXTENTS`, taken off when moving; macOS:
from the main screen's top left). A trackpad's pinch on macOS is a
`Scroll` with `Mods.CONTROL` (`deltaY` -180 ln(scale): as browsers send
one, as Control and the wheel; Windows' precision touchpads send it so
themselves). In the browser the canvas's wheel listener is not passive:
a wheel with Control (Chrome's and Firefox's pinch, Control and the wheel)
is prevented, the program's and not the page's zoom, other wheels left to
scroll a page around it; Safari's pinch, its `gesturestart` and
`gesturechange` (prevented too), comes as the same `Scroll` with
`Mods.CONTROL` (-100 ln of the scale's step, in CSS pixels, as Chrome makes
it). Tests: `bun run test window` (tests/os/WindowTest.hx: on X11
a second connection drags two files over the window speaking XDND, on
Windows an HDROP posted as `WM_DROPFILES`, under Wine too
(`GFX_TARGET=windows-x86_64`), on macOS a dragging info of the test's
own class given to the window's dragging destination; then moveTo and
position, fullscreen asked); `src/helder/os/UriList.test.hx`.

### An inset title bar

```haxe
var window = new Window("Studio", 1180, 740, Inset);  // helder.os.TitleBar: the content under the title bar
window.titlebarAt = (x, y) -> y < 40 * window.scale ? Drag : Content;  // the app's answer at a press (pixels)
window.titlebarArea();                      // the bar's area free of the buttons (pixels; null: not inset, full screen)
window.systemControls();                    // macOS's own buttons over the content (null where the app draws its own)
window.placeControls(x, y);                 // ... moved there (macOS)
window.minimize(); window.maximized = !window.maximized;
```

`Inset` runs the content under the title bar, the window's buttons in the
app's own layout (helder.ui's `<WindowControls/>`, `drag-region` and
`env(titlebar-area-*)`), what a press is the app's answer
(`titlebarAt`: `TitleHit`'s Drag, Minimize, Maximize, Close or Content;
`TitleBars.hit` adds the window's edges, 6 points, unless maximised or full
screen). macOS: a full-size content view (`NSWindowStyleMaskFullSizeContentView`),
the bar transparent, no title; the system's buttons kept and placed where
the app asks (Electron's way: the title bar's container made as tall as
the buttons and twice the top margin, each button's origin set in it,
again after each resize); a press on the bar but the buttons is the app's,
a drag region's `performWindowDragWithEvent:` (a double click what the
user set: `AppleActionOnDoubleClick`, zoom by default). Windows:
WM_NCCALCSIZE takes the caption off (the sides and bottom kept: their
resize borders and shadow; maximised, the frame the monitor hides too),
WM_NCHITTEST answers the top edge (HTTOP), the drag regions (HTCAPTION:
Windows' own moves, snaps and double clicks) and the maximise button
(HTMAXBUTTON: Windows 11's snap layouts; its presses taken by the window,
its hover passed on as a move); `TitleBars.button` and `HEIGHT` are the
drawn buttons' sizes. Wayland: neither the compositor's decorations nor
helder's bar; a drag region's press `xdg_toplevel.move` (a double press
maximises, the right button the window menu), an edge's `resize`. X11:
undecorated (`_MOTIF_WM_HINTS`), `_NET_WM_MOVERESIZE` for a drag region
or an edge (the pointer's grab let go first), maximised through
`_NET_WM_STATE`. A headless run of a macOS build has the buttons where
macOS puts them (7, 6 points, 54 by 16): `<WindowControls/>` draws
stand-ins. Tests: `TitleBar.test.hx` (the edges, each system's codes;
natively, as wasm32-wasi and on Eval) and the window lane's
`tests/os/TitleBarTest.hx` (macOS: the window's style, the buttons
measured, placed and kept through a resize, the bar's presses the app's
and the buttons' AppKit's; Windows: no caption, WM_NCHITTEST's answers;
X11: Motif's hints). Not yet: the edges' cursors on Wayland and X11 (the
compositor's or the window manager's), the maximised state followed on X11
(the window's own requests only).

### Dialogs, file types, the files the system opens

```haxe
var path = FileDialog.open(window, "Open an image", [{name: "Images", extensions: ["jpg", "png"]}]); // null: cancelled
FileTypes.register("helder-viewer", "Viewer", exe, [{mime: "image/jpeg", extensions: ["jpg"]}]);   // "Open with", this user's
App.onOpen = paths -> open(paths[0]);       // macOS: Finder's Open With, the Dock's icon (application:openURLs:)
window.raise();                              // to the front (a second launch handing its file over)
```

`FileDialog`: Windows' IFileOpenDialog (COM's vtables: filters, title,
the result's IShellItem path), macOS's NSOpenPanel (runModal), Linux's
xdg-desktop-portal FileChooser (OpenFile over the session bus with
`helder.os.linux.DBus`, a small blocking client of its own: SASL
EXTERNAL, the marshalling of the portals' types, calls, replies, signals,
a match rule; the request's Response signal, its URI as the path);
`available()` says whether there is one (no portal: the caller's own
picker). `FileTypes.register`: Windows' HKCU\Software\Classes (a ProgID
and its open command, each extension's OpenWithProgids, the
application's SupportedTypes; SHChangeNotify), Linux's
~/.local/share/applications/<id>.desktop (MimeType, Exec with %F); a
macOS bundle's are its Info.plist's (`helder build --target macos`, from
helder.webmanifest's `file_handlers`). Tests: the window lane
(IFileOpenDialog and NSOpenPanel made; FileTypes' registry values and
.desktop file read back; application:openURLs: reaching App.onOpen), the
dbus lane (tests/os/DBusTest.hx: a real dbus-daemon, the portal's
OpenFile against a stand-in portal).

### The system's image decoders

`SystemImages.decode(path, side)`: what helder.image does not read,
through the system: Windows' WIC (COM: the factory's decoder from the
file, its first frame converted to 32bppRGBA, its EXIF orientation from
the metadata query reader applied), macOS's ImageIO (an image
source, its size from its properties, then a thumbnail of at most `side`
with its EXIF orientation applied, drawn into an sRGB bitmap,
unpremultiplied). TIFF, HEIC and HEIF, AVIF and the cameras' RAW files
where the system has their codecs (Windows: its HEIF, AV1 and Raw Image
extensions). ImageLimits is checked on the size the system reports,
before any pixel; errors are ImageErrors (Unsupported: no codec for it).
Linux (`linux/LinuxImages`): libtiff, libheif (HEIC, HEIF, and AVIF with
its AV1 decoder), libavif and libraw where installed, each loaded at run
time (none: `supports` false for its formats; `available()` whether any
is); the limits first on each one's size (HEIF's and AVIF's from their
ispe boxes). Tests: `bun run test system-images`
(tests/os/SystemImagesTest.hx: a TIFF of a known gradient, plain and LZW,
its pixels and straight alpha; one with EXIF's orientation 6, upright; an
AVIF where the system reads it; macOS: a HEIC made by sips, whole and at
a side; the limits first; Linux natively, Windows under Wine with
GFX_TARGET=windows-x86_64).

### A phone's screen and the display's frames

```haxe
var w = new Window("Game", 0, 0);          // a phone's: the whole screen, its size the system's
w.safeTop; w.safeBottom;                    // the safe area, pixels from each edge (a Resize when it changes)
w.scale;                                    // pixels per point: Android's density / 160, iOS's nativeScale
w.immersive = true;                         // the system's bars hidden (a game's)
App.run(() -> {
	var dt = App.frame.delta;               // since the last frame: the display's vsyncs on a phone
}, e -> {});
```

`Window.safeTop`, `safeLeft`, `safeBottom` and `safeRight` are the
insets, in pixels, that the system's bars, a notch, the island, a
display cutout or the home indicator leave clear, as CSS's
`env(safe-area-inset-*)`: iOS's view's `safeAreaInsets` (measured in
`layoutSubviews` and `safeAreaInsetsDidChange`), Android's window insets
(`helder.os.android.Insets`, JNI on the main thread: the decor view's
root `WindowInsets`, on API 30 `getInsets(systemBars | displayCutout)`,
on 29 the system window insets and the cutout's safe insets), measured
again when the window, its size, its content rect or the configuration
changes; 0 elsewhere. A change is a `Resize` (a rotation is one anyway: a
new size). helder.ui takes them as `Ui.safeArea` and markup's
`env(safe-area-inset-*)` (src/helder/ui/README.md). `Window.scale` is
Android's density over 160 (`AConfiguration`, a `ScaleChange` when the
configuration changes it) and iOS's screen's `nativeScale` (the view's
`contentScaleFactor` and the layer's `contentsScale` set to it).
`Window.immersive` hides the system's bars: Android's immersive mode
(API 30: `WindowInsetsController.hide(systemBars)`, a swipe shows them for
a while; API 29: the immersive sticky flags; the window into a cutout's
edges), iOS's status bar and home indicator (the controller's
`prefersStatusBarHidden`, `prefersHomeIndicatorAutoHidden`); nothing
elsewhere. The app's options in package.json (`"helder": {"orientation":
"portrait" | "landscape" | "any", "fullscreen": true}`: the manifest's
`screenOrientation` and the plist's `UISupportedInterfaceOrientations`,
`-D helder.fullscreen` making every window immersive from the start;
src/helder/cli/README.md).

On Android and iOS the frames are the display's: a turn of `App.run` that
may draw asks for the next vsync and sleeps until it comes (or an event
does), and the next turn draws it. Android: Choreographer
(`AChoreographer_postFrameCallback64`, the NDK's, on the program's own
thread and looper: `helder.os.android.Vsync`); iOS: a `CADisplayLink` on
the main run loop, whose callback stops the run loop's wait. `App.frame`
(a `FrameClock`) is the frame's time: on a phone the vsync's timestamp
(Choreographer's `CLOCK_MONOTONIC` time, the link's `timestamp`) moved
into `haxe.Timer.stamp()`'s seconds, elsewhere when the turn began;
`delta`, the time since the last frame, and `period`, the display's
refresh interval learnt from the deltas. A frame that sleeps (`App.wait`:
nothing to draw) asks for no vsync until it has slept, so an idle app
sleeps; the background, a lost window (Android's `onPause`, the window
destroyed) and an inactive app (iOS's `willResignActive`,
`didEnterBackground`) ask for none, and the first frame after them has a
delta of one period, not the time away. Nothing is allocated a frame.

Tests: `src/helder/os/FrameClock.test.hx` (the deltas, the period at 60
and 120 Hz, a missed frame, a pause, no allocation; natively and as
wasm32-wasi); on CI's emulator and simulator `tests/pack/Screen.hx`
(`tests/pack/android.sh`, `ios.sh`, checked by `tests/pack/screen.mjs`):
the window's size, scale and safe area, the display's frames (vsyncs at a
display's pace, nothing allocated over 120), the bars hidden, a rotation
(Android), the background and back.

A touch is its pointer's events alone, in the browser, on Android and on
iOS (`Pointers`, below): no mouse events or scrolls are made of it, so one
touch drives one thing; a program taps, drags, flings and pinches from the
pointers (helder.ui does: a tap clicks, the first finger's drag scrolls and
glides; the examples drag with any pointer, the mouse's left button too;
`helder.os.Glide` is a fling's glide). In the browser `browser.mjs`'s option
`touchAction` is the canvas's CSS `touch-action`: `'none'` by default
(every drag the program's); with `'pan-y'` a drag that starts vertical asks
the program first, once, at its first move: `Window.scrollsAt(x, y, dx,
dy)`, whether something where it started scrolls that way (helder.ui
answers from its scrollers, innermost first; the cube takes only sideways
drags). Yes: the drag is the program's, the page held still (its
touchmoves cancelled); no, or no answer: the page scrolls instead, as at a
scroller's end (a canvas as wide as a phone's screen that the page must
scroll past), and the pointer is cancelled (`PointerCancel`). A tap
focuses the canvas. A mouse's press is captured by the canvas: a drag that
leaves it still moves, and its release still comes. On Android and iOS
the window sees the touches itself: no page to pan, every drag the
program's.

## Wayland

`helder.os.wayland`: libwayland-client, libwayland-egl, libxkbcommon and
libwayland-cursor loaded at run time (`Dl`: a machine without them runs
X11's). The protocols' bindings are generated by helder's own scanner from
their XML (`Scanner.hx`, run on Eval: `haxe -cp src --run
helder.os.wayland.Scanner src/helder/os/wayland/protocol <xml>...`; checked
in, `bun run test wayland` makes them again from the system's XML and
compares): core, xdg-shell, xdg-decoration, viewporter, fractional-scale
and cursor-shape, each interface an abstract over its proxy with a method
per request (`wl_proxy_marshal_array_flags`, the arguments as wl_argument
slots) and an events class of handlers (one C dispatcher,
`wl_proxy_add_dispatcher`), the wl_interface and wl_message structs made
at run time (`Interfaces`). `WaylandWindow`: an xdg_toplevel on a
wl_surface, GL's EGL on a wl_egl_window (`SurfaceKind.Wayland`; its swap
interval 0, the loop pacing itself), the buffer at the compositor's scale
(fractional-scale and the viewport's destination, else wl_surface's
preferred_buffer_scale or the outputs' integer scale), the compositor's
decorations where xdg-decoration agrees, else helder's own bar above the
content (a wl_shm subsurface: minimise, maximise, close; a press moves the
window, a double press maximises; no title text in it yet), fullscreen
and back to the windowed size; the seat's keyboard (xkbcommon's keymap,
KeySyms as X11's, its text, repeat), pointer (value120 wheel notches, a
touchpad's pixels; cursor-shape's shapes, else the theme's images) and
touch (Pointers); wl_data_device's clipboard text and file drops
(text/uri-list). Not yet: an input method (text-input-v3), xdg_popup
(helder's menus are drawn in the window), edge resizing of helder's
decorations. Tests: `src/helder/os/wayland/Wayland.test.hx` (the structs,
requests and events against a recorder: no compositor), and the wayland
lane under a headless weston at scale 1 and 2 (tests/os/WaylandTest.hx, the
viewer, a screenshot).

## Pointers: the mouse, fingers and pens

One stream for every pointer, as the DOM's Pointer Events: `PointerDown`,
`PointerMove`, `PointerUp` and `PointerCancel` events carry `e.pointer`, a
`Pointer` (one per slot of `Pointers`, preallocated: nothing is allocated
per event or per frame), already updated: its `id` (the slot: 0 the
mouse, fingers and pens the lowest free one from 1, stable while it is
down), `type` (`Mouse`, `Touch`, `Pen`), `window` (and its `scale`), `phase`, `down`,
`primary` (the first finger down while no other was, or the mouse), `x`,
`y` (window pixels, sub-pixel where the system has them), `startX`,
`startY`, `dx`, `dy` (its motion this frame), `pressure`, `tiltX`, `tiltY`,
`buttons`, `time`, `press` (its press's number: a press and its release
within one step still count), `owner` (who took it: nobody, ui, a game
control), and the samples the system batched before the event
(`samples`, `sampleX(i)`, `sampleY(i)`: Android's
history, iOS's coalesced touches, the browser's coalesced events and the
moves between two frames).

```haxe
App.run(() -> {
	for (i in 0...Pointers.count) {         // in a frame: the pointers down, in down order
		var p = Pointers.at(i);
		if (Pointers.justDown(p)) grab(p.id);
		look(p.dx, p.dy);
	}
}, e -> switch e.kind {
	case PointerDown if (e.pointer.type == Touch): ...;
	case PointerCancel: release(e.pointer.id);  // the system took it: no tap, let go
	case _:
});
```

`App.run`'s turns begin a frame of `Pointers` (`Pointers.step`: `dx`,
`dy`, `justDown`, `justUp` start again) before their events. A cancel is a
real ending: the system took the pointer (a call, a system gesture, the
browser panning the page), it must not tap and what it held lets go.

The back ends: Android's `MotionEvent`s (every pointer, its tool: a
finger, a stylus or a mouse; `ACTION_CANCEL` and a palm's
`FLAG_CANCELED` cancel), iOS's `UITouch`es (`multipleTouchEnabled`; a
pencil is a pen; the background cancels), the browser's Pointer Events
for touches and pens (captured by the canvas, without the browser's
mouse events: a pen is no longer the mouse there), the mouse everywhere
as slot 0 after its own `Mouse*` events (a move without a button too).
Touch screens on Windows and X11 (`WM_POINTER`, XInput2) come later.

A finger or a pen has its pointer's events alone: no `MouseMove`,
`MouseDown`, `MouseUp` or `Scroll` is made of it (the mouse emulation and
`TouchDrag` before pointers are gone). helder.ui's arena taps, scrolls and
pinches from the pointers; helder.scene's `InputMap` makes the first finger
or pen down that no control took the left button while it is down
(`Mouse(1)`, `Region`).

Tests: `src/helder/os/Pointers.test.hx` (slots, frames, samples, cancels,
no allocation: natively and as wasm32-wasi, the test lane),
`bun run test touch-web` (`tests/os/PointersWeb.hx` in headless
Chromium: two fingers, a pen and the mouse through the DevTools
protocol, samples, a cancel, a tap and a drag without mouse events or
scrolls, a wheel with Control prevented and a plain one not, Safari's
gesture events made by hand), `src/helder/os/Glide.test.hx` (a fling's glide). Android's and
iOS's on CI's emulator and simulator: `tests/gfx/android.sh` and `ios.sh`
(the cube's Spin on a finger's pointer: a tap's PointerDown and PointerUp,
a drag held turning the cube and holding it still while it rests, a
fling's flick, never a mouse event or a scroll from a touch) and
`tests/os/android-touch.sh` (a drawn ui's fling: the box following the
finger, gliding on).

## Fast refresh: `helder.dev.Hot`

Under `helder dev` (`-D hxmc.dev`) a
reload is a fresh start of the new build with the old one's state carried
over by key. `helder.dev.Hot` is the public layer state libraries use for it
(helder.view's signals included): `onSnapshot` and `onDispose`, `save` and
`load` by key with the type's hash (`typeOf((_ : T))`), `here()` and
`scope(name, f)` for keys, `keep(key, init)`, `reloading`. The app loop
reads the dev server's messages (`App.run`'s turns; an idle loop wakes
every 50 ms) and reports the first frame. Without `-D hxmc.dev` every call
compiles to nothing.

## Store

`Store.open(name)`: a small key-value store of strings kept between runs
(settings, a save), read when opened and written through at each `set`,
`remove` or `clear` (a temporary file renamed over the old one): a JSON
file in the app's data directory (Linux `$XDG_DATA_HOME/<name>/store.json`,
macOS `~/Library/Application Support/<name>/`, Windows `%APPDATA%\<name>\`,
Android the app's files directory, iOS its `Library/Application Support`),
localStorage on the web (the item `helder.store/<name>`). A damaged or
missing file opens empty; `written` says whether the last change was
kept. `Store.test.hx` (natively and as wasm32-wasi).

## Audio

A pull model: the system asks for samples and a callback fills them.

```haxe
var out = Audio.open({sampleRate: 48000, channels: 2, frames: 512}, (buffer:Ptr<Float32>, frames:Int) -> {
	for (i in 0...frames) {                   // interleaved, zeroed before the call
		var v = 0.25 * Math.sin(phase);
		buffer[i * 2] = v;
		buffer[i * 2 + 1] = v;
		phase += step;
	}
});
out.start();          // the callback runs on the audio thread from now on
out.stop();           // what the system queued is dropped; start plays again
out.close();
out.sampleRate; out.channels; out.frames; out.latency; // as the system gave them
```

`examples/tone/Tone.hx` plays a 440 Hz sine for two seconds. Effects and
music: `Sfx.open()` mixes sounds made up front (`add(samples)`, mono at
`Sfx.RATE`; a file decoded whole by `Sound.decode`: WAV or Ogg Vorbis) on
a few voices, `play(id, gain, rate, pan)` once or `loop(...)` until
`stop(handle)` (`gain(handle, g)`, `pan(handle, p)` meanwhile), and music:
`music(bytes, fade, gain, loop)` streams an Ogg Vorbis file, decoded a
packet at a time on the audio thread from its compressed bytes, resampled
to the output's rate, crossfading from what played over `fade` seconds
(`stopMusic(fade)`; `volume` the effects', `musicVolume` the music's).
Nothing is allocated on the audio thread (`Sfx.test.hx`, `Vorbis.test.hx`;
examples/golf's sounds).

Vorbis (`Vorbis.hx`, the Vorbis I specification, some 900 lines): floor 1,
residues 0 to 2, any channels; floor 0, unused by encoders since 2002, is
refused. `open` parses the headers and allocates every buffer; `next()`
decodes a packet (the IMDCT through an n/4-point FFT) into `out`,
`rewind()` loops. Ogg Vorbis rather than a simpler codec: music is
distributed in it, at a quarter of the bytes of ADPCM or QOA for the same
quality. Its samples match ffmpeg's decoder within a float's rounding
(about 1e-7; the tests' files are ffmpeg's libvorbis), some 300 times
faster than real time natively. `frames` is a hint:
`out.frames` is the most frames a callback is asked for (the system's
period or buffer), `out.latency` the seconds from a callback's samples to
the output, as the system reports them.

| Target | Back end | The audio thread |
| --- | --- | --- |
| Linux | ALSA (`libasound.so.2`, loaded with `dlopen` when an output opens: the glibc mode), the `default` PCM (PipeWire's or PulseAudio's plugin on most desktops), floats through ALSA's plug layer | ours: pulls a period, `snd_pcm_writei` (blocks while ALSA's buffer is full) |
| macOS | CoreAudio's default output unit (AudioToolbox) | ours: fills a ring in native memory; CoreAudio's I/O thread runs a `@:hxmc.noGc` render callback that copies from it |
| iOS | RemoteIO (an AudioUnit of AudioToolbox), after AVAudioSession's category (`session`: `"ambient"` by default, which the silent switch silences; `"playback"`), its preferred buffer a period | as macOS's: the ring, RemoteIO's render callback copying from it |
| Android | AAudio (`libaaudio.so`, loaded with `dlopen` when an output opens; API 26+), low-latency, shared, usage game, two bursts of buffer | as macOS's: the ring, AAudio's `@:hxmc.noGc` data callback copying from it and posting a semaphore |
| Windows | WASAPI, shared mode, event driven (COM through vtables), floats converted by the audio engine | ours: waits for WASAPI's event, fills what the buffer has free |
| Browser | WebAudio: an AudioWorklet node fed chunks the page posts it | none: the main thread, when the worklet has played a chunk |

Phones: the app's lifecycle holds the outputs (`helder.os.AppAudio`):
Android's activity paused, or iOS's app in the background, stops the running
ones, and coming back starts them again (`Audio.held`). On Android a stream
disconnected (headphones unplugged, a Bluetooth device gone: AAudio's error
callback) is closed by the audio thread and another opened where the system
routes now. On iOS an interruption (a call, an alarm:
AVAudioSessionInterruptionNotification) holds them the same way, and its
end makes the session active and starts them again. In the browser a hidden
page suspends its contexts until it shows again.

The callback is ordinary Haxe on one of the runtime's threads, but it runs
against a deadline: preallocate, do not allocate (that can start a
collection, and any thread's collection pauses this one), lock, block or
print there, and never stop or close the output from it (both wait for
the audio thread). CoreAudio calls back on a thread the runtime does not
know, where only `@:hxmc.noGc` code may run (hxmc's docs/plans/lowlevel.md,
"Callbacks"): that is why it only copies from the ring. In the browser the
module's memory is not shared with the worklet's thread, so each chunk is
copied and posted, keeping about 50 ms queued; the callback may close the
output there. AudioWorklet rather than ScriptProcessorNode: the latter is
deprecated and runs its callback on the main thread with the output
waiting on it, where a busy main thread is a glitch either way, but the
worklet keeps playing what it has. Browsers start audio after a user
gesture: a context made before resumes on the page's next click or key.

The device: `null` is the system's default; `"file:PATH"` (Linux and
macOS) plays to no device, what the system's API renders written to PATH
as raw interleaved floats (ALSA's file plugin over its null device;
CoreAudio's generic output unit rendered at the clock's pace); on Linux
any other name is ALSA's (`"null"`, `"hw:0"`). In the browser,
`browser.mjs`'s option `audioContext` gives the context (an
`OfflineAudioContext` in tests). An output that has no device throws
`helder.os.audio: no output device (...)`.

Tests (`tests/os/AudioTest.hx`): a known signal through each back end's real
API, the samples that reach it compared with the signal, the callbacks'
count and rate. `bun run test audio` (`tests/os/audio.sh`): ALSA's null and file
devices; CoreAudio's file device, then the default output where there is
one; WASAPI on the default endpoint where there is one, or under Wine
(`AUDIO_TARGET=windows-x86_64`) through winealsa to an ALSA file.
`bun run test audio-web` (`tests/os/web.mjs`): headless Chromium, realtime (the
rate) and an `OfflineAudioContext` (the rendered samples, exact).
Phones (`tests/pack/AudioCheck.hx`, in CI's emulator and simulator jobs:
tests/pack/android.sh, ios.sh): an output on AAudio or RemoteIO for two
seconds, its line counting the callbacks, "audio: started" once the
device pulled half a second's worth.
