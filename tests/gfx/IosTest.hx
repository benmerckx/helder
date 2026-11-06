import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.*;
import Cube.Spin;

// The cube on iOS (CI's ios-simulator job: an iPhone simulator on a macOS
// runner; ios.sh reads the results from the app's stdout, which simctl
// launch writes to a file):
//   helder build tests/gfx/ios --target ios-sim -o IosTest.app
//   (tests/gfx/ios/package.json: tests/gfx and the gfx examples' class
//   paths; the app org.helder.IosTest)
// - headless: Scene's cube on an offscreen Metal texture, read back and
//   compared with cube.png (built into the app) by GfxTest's rule;
// - in the app's window: its size, scale and safe area, frames drawn (the
//   cube turning), the window's pixels read back after a few (lit: the
//   cube is there), a line per 60 frames; touches (their pointer events),
//   the mouse's events and the scrolls (a touch makes none), resizes and
//   the app's lifecycle (Suspend, Resume) logged as their events; the cube
//   turned as Cube.hx turns it (Spin: held while a finger drags it,
//   flicked on at the drag's speed once let go), its state logged every 20
//   frames. The app runs until the system ends it (simctl terminate).
class IosTest {
	static inline var WIDTH = 256;
	static inline var HEIGHT = 192;

	static function main() {
		Sys.println("IosTest: start");
		var device = Device.create(Surface.headless(WIDTH, HEIGHT));
		var draw = Scene.make("cube", device);
		var pixels = Bytes.alloc(WIDTH * HEIGHT * 4);
		var enc = device.beginFrame();
		draw(enc);
		device.readPixels(pixels);
		device.endFrame();
		device.dispose();
		GfxTest.compareBytes("cube, ios headless", pixels, Embed.file("tests/gfx/cube.png"));
		var w = new Window("IosTest", 0, 0);
		Sys.println('IosTest: window ${w.width}x${w.height}, scale ${w.scale}, safe area ${w.safeTop},${w.safeLeft},${w.safeBottom},${w.safeRight}');
		var device = Device.create(w.surface);
		var cube = new Cube(device);
		var spin = new Spin(Spin.SPEED), last = Sys.time(), frames = 0, lit = false;
		App.run(() -> {
			var now = Sys.time();
			spin.advance(Math.min(now - last, 0.1));
			last = now;
			var enc = device.beginFrame();
			if (enc == null) return;
			cube.draw(enc, Scene.ANGLE + spin.angle);
			frames++;
			if (frames % 20 == 0) Sys.println('IosTest: spin ' + (spin.held ? "held" : "free") + ' angle ${Math.round(spin.angle * 1000)} speed ${Math.round(spin.speed * 1000)}');
			if (frames == 30) {
				var px = Bytes.alloc(device.width * device.height * 4);
				device.readPixels(px);
				var c = 4 * ((device.height >> 1) * device.width + (device.width >> 1));
				lit = Math.abs(px.get(c) - px.get(0)) + Math.abs(px.get(c + 1) - px.get(1)) + Math.abs(px.get(c + 2) - px.get(2)) > 30;
				Sys.println('IosTest: window frame ${device.width}x${device.height}: ' + (lit ? "lit" : "nothing drawn"));
			}
			device.endFrame();
			if (frames % 60 == 0) Sys.println('IosTest: frames $frames');
		}, e -> {
			var name = switch e.kind {
				case MouseDown: "MouseDown";
				case MouseUp: "MouseUp";
				case KeyDown: "KeyDown";
				case Resize: "Resize";
				case ScaleChange: "ScaleChange";
				case Suspend: "Suspend";
				case Resume: "Resume";
				case Close: "Close";
				case _: null;
			}
			if (name != null) Sys.println('IosTest: event $name ${e.x},${e.y} button ${e.button}');
			// (a finger's pointer events; the scrolls: none from a touch)
			switch e.kind {
				case PointerDown | PointerMove | PointerUp | PointerCancel:
					var p = e.pointer;
					var kind = e.kind == PointerDown ? "PointerDown" : e.kind == PointerMove ? "PointerMove" : e.kind == PointerUp ? "PointerUp" : "PointerCancel";
					var type = p.type == Mouse ? "mouse" : p.type == Touch ? "touch" : "pen";
					Sys.println('IosTest: event $kind ${p.id} $type ${Math.round(p.x)},${Math.round(p.y)}' + (p.primary ? " primary" : ""));
				case Scroll:
					Sys.println('IosTest: event Scroll ${e.x},${e.y} by ${e.deltaX},${e.deltaY} mods ${e.mods}');
				case _:
			}
			spin.input(e, w);
			if (e.kind == Resize) Sys.println('IosTest: safe area ${w.safeTop},${w.safeLeft},${w.safeBottom},${w.safeRight}');
		});
		Sys.println("IosTest: done");
	}
}
