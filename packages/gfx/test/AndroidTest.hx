import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.os.*;

// The cube on Android (CI's android job: an x86-64 emulator; check.sh's
// android step reads the results from logcat, where hxmc.os sends what the
// app prints):
//   haxe -cp packages/os/src -cp packages/gfx/src -cp packages/gfx/examples
//     -cp packages/gfx/test -main AndroidTest --custom-target hxmc=AndroidTest.apk
//     -D hxmc.target=android-x86_64 -D hxmc.android-package=org.hxmc.gfxtest
// - headless: Scene's cube on an EGL pbuffer of the device's GPU, read back
//   and compared with cube.png (built into the app) by GfxTest's rule;
// - in the activity's window: frames drawn (the cube turning), the window's
//   pixels read back after a few (lit: the cube is there), a line per 60
//   frames; touches and keys logged as their events. The app keeps running
//   (the screenshot comes from adb).
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
		GfxTest.compareBytes("cube, android headless", pixels, Embed.file("packages/gfx/test/cube.png"));
		var w = new Window("AndroidTest", 0, 0);
		Sys.println('AndroidTest: window ${w.width}x${w.height}, scale ${w.scale}');
		var device = Device.create(w.surface);
		var cube = new Cube(device);
		var start = Sys.time(), frames = 0;
		App.run(() -> {
			var enc = device.beginFrame();
			if (enc == null) return;
			cube.draw(enc, Scene.ANGLE + (Sys.time() - start) * 0.5);
			frames++;
			if (frames == 30) {
				var px = Bytes.alloc(device.width * device.height * 4);
				device.readPixels(px);
				var c = 4 * ((device.height >> 1) * device.width + (device.width >> 1));
				var lit = Math.abs(px.get(c) - px.get(0)) + Math.abs(px.get(c + 1) - px.get(1)) + Math.abs(px.get(c + 2) - px.get(2)) > 30;
				Sys.println('AndroidTest: window frame ${device.width}x${device.height}: ' + (lit ? "lit" : "nothing drawn"));
			}
			device.endFrame();
			if (frames % 60 == 0) Sys.println('AndroidTest: frames $frames');
		}, e -> switch e.kind {
			case MouseDown | MouseUp | KeyDown | KeyUp | TextInput | Resize | Suspend | Resume | Close:
				Sys.println('AndroidTest: event ${e.kind} ${e.x},${e.y} key ${e.key} "${e.text}"');
				if (e.kind == Close) w.close();
			case _:
		});
		Sys.println("AndroidTest: done");
	}
}
