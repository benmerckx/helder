import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.*;

// The cube on iOS (CI's ios-simulator job: an iPhone simulator on a macOS
// runner; ios.sh reads the results from the app's stdout, which simctl
// launch writes to a file):
//   haxe -cp src -cp examples
//     -cp tests/gfx -main IosTest --custom-target hxmc=IosTest.app
//     -D hxmc.target=ios-sim-arm64 -D hxmc.ios-bundle-id=org.hxmc.gfxtest
// - headless: Scene's cube on an offscreen Metal texture, read back and
//   compared with cube.png (built into the app) by GfxTest's rule;
// - in the app's window: its size, scale and safe area, frames drawn (the
//   cube turning), the window's pixels read back after a few (lit: the
//   cube is there), a line per 60 frames; touches, resizes and the app's
//   lifecycle (Suspend, Resume) logged as their events. The app runs until
//   the system ends it (simctl terminate).
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
		var start = Sys.time(), frames = 0, lit = false;
		App.run(() -> {
			var enc = device.beginFrame();
			if (enc == null) return;
			cube.draw(enc, Scene.ANGLE + (Sys.time() - start) * 0.5);
			frames++;
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
			// (a drag's scrolls: at where it started, Mods.TOUCH while the finger is down)
			if (e.kind == Scroll) Sys.println('IosTest: event Scroll ${e.x},${e.y} by ${e.deltaX},${e.deltaY} mods ${e.mods}');
			if (e.kind == Resize) Sys.println('IosTest: safe area ${w.safeTop},${w.safeLeft},${w.safeBottom},${w.safeRight}');
		});
		Sys.println("IosTest: done");
	}
}
