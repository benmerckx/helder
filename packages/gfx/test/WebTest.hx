import hxmc.gfx.*;
import hxmc.os.*;

// The triangle example's frame in a browser, on WebGPU (webgpu.mjs runs it in
// headless Chromium and compares the pixels with triangle.png, as GfxTest
// does natively):
//
//   WebTest headless   an offscreen texture, drawn once by main
//   WebTest window     a canvas of 256x192 pixels, drawn by App.run's frames
//                      from the browser's loop after main returned; a Resize
//                      when the page resizes it, Escape closes it (the loop ends)
//
// WebGPU reads pixels back asynchronously only: the harness does, through
// packages/gfx/imports.mjs (readPixels).
class WebTest {
	static function main() {
		if (Sys.args()[0] == "headless") {
			var device = Device.create(Surface.headless(256, 192));
			new Triangle(device).frame();
			Sys.println('WebTest: headless: ${device.width}x${device.height}');
			return;
		}
		var w = new Window("WebTest", 256, 192);
		var triangle = new Triangle(Device.create(w.surface));
		var frames = 0;
		App.run(() -> {
			triangle.frame();
			frames++;
		}, e -> switch e.kind {
			case Resize: Sys.println('WebTest: resized to ${e.x}x${e.y} (${w.width}x${w.height})');
			case KeyDown if (e.key == 0xFF1B):
				Sys.println('WebTest: Escape after $frames frames');
				w.close();
			case _:
		});
		Sys.println('WebTest: window: ${w.width}x${w.height}, App.run returned');
	}
}
