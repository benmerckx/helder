# helder.os

Windows, input, the app loop and audio output for hxmc in pure Haxe
(`helder.os`): raw OS bindings (X11, the Objective-C runtime, AppKit and
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

X11 on Linux (the glibc mode, `-D hxmc.libc=glibc`), Cocoa on macOS,
Win32 on Windows, a canvas in the browser (wasm32-wasi: `App.run` returns
and `requestAnimationFrame` runs the loop). `Event` is one object, refilled
for each event: keys as X11 KeySyms, `TextInput` characters (and an input
method's `TextEditing`), the mouse in
pixels from the top left, `Scroll` in pixels, `Resize`, `ScaleChange`,
and every pointer's events (below).

On Android (`-D hxmc.target=android-arm64` with an output ending in `.apk`)
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
there) and `Glue` (Java's listeners calling Haxe: hxmc then writes a
`classes.dex` into the APK).

On iOS (`-D hxmc.target=ios-arm64` or `ios-sim-arm64` with an output ending
in `.app`) the window is a `UIWindow` on the whole screen (one per app),
backed by a `CAMetalLayer`: the program's main runs inside UIKit's loop
(`UIApplicationMain` comes first: `helder.os.uikit.UIKitApp`), `App.run`
draws while the app is in the foreground, a touch is as in the browser
and on Android, `Window.safeTop` (`safeLeft`, `safeBottom`,
`safeRight`) is the safe area in pixels, `Suspend` and `Resume` come when
the app goes to the background and back. No keys or text input there yet.

In the browser a touch drag on the canvas is `Scroll` (the content following
the finger, gliding when let go) and a tap a click. `browser.mjs`'s option
`touchAction` is the canvas's CSS `touch-action`: `'none'` by default (every
drag the program's); with `'pan-y'` a drag that starts vertical asks the
program first, once, at its first move: `Window.scrollsAt(x, y, dx, dy)`,
whether something where it started scrolls that way (helder.ui answers from
its scrollers, innermost first; the cube takes only sideways drags). Yes:
the drag is the program's, the page held still (its touchmoves cancelled);
no, or no answer: the page scrolls instead, as at a scroller's end (a
canvas as wide as a phone's screen that the page must scroll past). The
other drags reach the program. While the finger drags, its
`Scroll`s have `Mods.TOUCH`; when it is let go (or the browser takes the
gesture over) a `Scroll` of nothing without it comes, then the glide's: a
program that holds still what the finger holds (the cube) knows when it is
released, even after the finger rested. A mouse's press is captured by the
canvas: a drag that leaves it still moves, and its release still comes.
On Android and iOS the window sees the touches itself and they mean the
same (`helder.os.TouchDrag`, the gesture both share: no page to pan, every
drag the program's): a tap clicks where it came down once it lifts, a drag
past 8 points scrolls what is under where it started, `Mods.TOUCH` while
the finger is down, then a `Scroll` of nothing without it and the glide's
(the loop wakes each frame while it glides).

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
(`samples`, `sampleX(i)`, `sampleY(i)`, `sampleTime(i)`: Android's
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

`Pointers.emulate` (on by default) keeps what a touch did before: the
first finger's tap a click and its drag `Scroll`s (`TouchDrag`, below),
their `MouseMove`, `MouseDown` and `MouseUp` with `Mods.TOUCH` (so that
the mouse's pointer is not made of them). A program that follows the
pointers itself turns it off (helder.ui's windows do: ui's arena taps and
scrolls itself).

Tests: `src/helder/os/Pointers.test.hx` (slots, frames, samples, cancels,
no allocation: natively and as wasm32-wasi, the test lane),
`bun run test touch-web` (`tests/os/PointersWeb.hx` in headless
Chromium: two fingers, a pen and the mouse through the DevTools
protocol, samples, a cancel, `emulate` off). Android's and iOS's back
ends are written and compile (every back end is typed on each target)
but are not run yet: packaging is moving into helder.

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

`examples/tone/Tone.hx` plays a 440 Hz sine for two seconds. `frames` is a hint:
`out.frames` is the most frames a callback is asked for (the system's
period or buffer), `out.latency` the seconds from a callback's samples to
the output, as the system reports them.

| Target | Back end | The audio thread |
| --- | --- | --- |
| Linux | ALSA (`libasound.so.2`, loaded with `dlopen` when an output opens: the glibc mode), the `default` PCM (PipeWire's or PulseAudio's plugin on most desktops), floats through ALSA's plug layer | ours: pulls a period, `snd_pcm_writei` (blocks while ALSA's buffer is full) |
| macOS | CoreAudio's default output unit (AudioToolbox) | ours: fills a ring in native memory; CoreAudio's I/O thread runs a `@:hxmc.noGc` render callback that copies from it |
| Windows | WASAPI, shared mode, event driven (COM through vtables), floats converted by the audio engine | ours: waits for WASAPI's event, fills what the buffer has free |
| Browser | WebAudio: an AudioWorklet node fed chunks the page posts it | none: the main thread, when the worklet has played a chunk |

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
