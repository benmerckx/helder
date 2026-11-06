import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.*;
import Cube.Spin;

// The cube on Android (CI's android job: an x86-64 emulator; android.sh
// reads the results from logcat, where helder.os sends what the app prints):
//   helder build tests/gfx/android --target android-x86_64 -o AndroidTest.apk
//   (tests/gfx/android/package.json: tests/gfx and the gfx examples' class
//   paths; the app org.helder.androidtest)
// - headless: Scene's cube on an EGL pbuffer of the device's GPU, read back
//   and compared with cube.png (built into the app) by GfxTest's rule;
// - in the activity's window: frames drawn (the cube turning), the window's
//   pixels read back after a few (lit: the cube is there), a line per 60
//   frames; touches (their pointer events) and keys logged as their
//   events, the mouse's and the scrolls too (a touch makes none), the cube
//   turned as Cube.hx turns it (Spin: held while a finger drags it, flicked
//   on at the drag's speed once let go: its speed then logged), its state
//   logged every 20 frames. The app keeps running
//   (the screenshot comes from adb) until Back (Escape) closes the window.
class AndroidTest {
	static inline var WIDTH = 256;
	static inline var HEIGHT = 192;

	static function main() {
		Sys.println("AndroidTest: start");
		var device = Device.create(Surface.headless(WIDTH, HEIGHT));
		var draw = Scene.make("cube", device);
		var pixels = Bytes.alloc(WIDTH * HEIGHT * 4);
		var enc = device.beginFrame();
		draw(enc);
		device.readPixels(pixels);
		device.endFrame();
		device.dispose();
		GfxTest.compareBytes("cube, android headless", pixels, Embed.file("tests/gfx/cube.png"));
		var w = new Window("AndroidTest", 0, 0);
		Sys.println('AndroidTest: window ${w.width}x${w.height}, scale ${w.scale}');
		var device = Device.create(w.surface);
		var cube = new Cube(device);
		var spin = new Spin(Spin.SPEED), last = Sys.time(), frames = 0;
		App.run(() -> {
			var now = Sys.time();
			spin.advance(Math.min(now - last, 0.1));
			last = now;
			var enc = device.beginFrame();
			if (enc == null) return;
			cube.draw(enc, Scene.ANGLE + spin.angle);
			frames++;
			if (frames % 20 == 0) Sys.println('AndroidTest: spin ' + (spin.held ? "held" : "free") + ' angle ${Math.round(spin.angle * 1000)} speed ${Math.round(spin.speed * 1000)}');
			if (frames == 30) {
				var px = Bytes.alloc(device.width * device.height * 4);
				device.readPixels(px);
				var c = 4 * ((device.height >> 1) * device.width + (device.width >> 1));
				var lit = Math.abs(px.get(c) - px.get(0)) + Math.abs(px.get(c + 1) - px.get(1)) + Math.abs(px.get(c + 2) - px.get(2)) > 30;
				Sys.println('AndroidTest: window frame ${device.width}x${device.height}: ' + (lit ? "lit" : "nothing drawn"));
			}
			device.endFrame();
			if (frames % 60 == 0) Sys.println('AndroidTest: frames $frames');
		}, e -> {
			var name = switch e.kind {
				case MouseDown: "MouseDown";
				case MouseUp: "MouseUp";
				case KeyDown: "KeyDown";
				case KeyUp: "KeyUp";
				case TextInput: "TextInput";
				case Resize: "Resize";
				case Suspend: "Suspend";
				case Resume: "Resume";
				case Close: "Close";
				case _: null;
			}
			if (name != null) Sys.println('AndroidTest: event $name ${e.x},${e.y} key ${e.key} "${e.text}"');
			// (a finger's pointer events; the scrolls: none from a touch)
			switch e.kind {
				case PointerDown | PointerMove | PointerUp | PointerCancel:
					var p = e.pointer;
					var kind = e.kind == PointerDown ? "PointerDown" : e.kind == PointerMove ? "PointerMove" : e.kind == PointerUp ? "PointerUp" : "PointerCancel";
					var type = p.type == Mouse ? "mouse" : p.type == Touch ? "touch" : "pen";
					Sys.println('AndroidTest: event $kind ${p.id} $type ${Math.round(p.x)},${Math.round(p.y)}' + (p.primary ? " primary" : ""));
				case Scroll:
					Sys.println('AndroidTest: event Scroll ${e.x},${e.y} by ${e.deltaX},${e.deltaY} mods ${e.mods}');
				case _:
			}
			spin.input(e, w);
			// (let go: the speed the release gave it, before its frames ease it back)
			if (e.kind == PointerUp && e.pointer.type == Touch) Sys.println('AndroidTest: let go, spin speed ${Math.round(spin.speed * 1000)}');
			// (Back is Escape: closed as the examples do; Android 12+ keeps a launcher's activity on Back)
			if (e.kind == Close || (e.kind == KeyDown && e.key == 0xFF1B)) w.close();
		});
		Sys.println("AndroidTest: done");
	}
}
