import helder.gfx.*;
import helder.os.*;

// The examples' frames in a browser, on WebGPU or WebGL2 (web.mjs runs it
// in headless Chromium, forcing WebGL2 with browser.mjs's option gfx:
// 'webgl2', and compares the pixels with triangle.png, cube.png and
// instances.png, as GfxTest does natively; the scene, triangle, cube or
// instances, the second argument):
//
//   WebTest headless   an offscreen target, drawn once by main; on WebGL2
//                      also read back by Device.readPixels (its checksum)
//   WebTest window     a canvas of 256x192 pixels, drawn by App.run's frames
//                      from the browser's loop after main returned; a Resize
//                      when the page resizes it, characters typed and the wheel
//                      printed, Escape closes it (the loop ends)
//
// WebGPU reads pixels back asynchronously only: the harness does, through
// src/helder/gfx/imports.mjs (readPixels), on both.
class WebTest {
	static function main() {
		var scene = Sys.args()[1];
		if (Sys.args()[0] == "headless") {
			var device = Device.create(Surface.headless(256, 192));
			var draw = Scene.make(scene, device);
			// (the shader macro's other test shaders, with uniform blocks, textures and every builtin: this back end compiles them)
			device.createPipeline(LitShader.pipeline());
			device.createPipeline(BuiltinShader.pipeline());
			device.createPipeline(TexturedShader.pipeline());
			if (device.backend == WebGL2) {
				var pixels = haxe.io.Bytes.alloc(256 * 192 * 4);
				draw(device.beginFrame());
				device.readPixels(pixels);
				device.endFrame();
				Sys.println('WebTest: readPixels: ${fnv(pixels)}');
			} else {
				draw(device.beginFrame());
				device.endFrame();
			}
			Sys.println('WebTest: headless: ${device.width}x${device.height} (${name(device.backend)})');
			return;
		}
		var w = new Window("WebTest", 256, 192);
		var device = Device.create(w.surface);
		var draw = Scene.make(scene, device);
		var frames = 0;
		App.run(() -> {
			var enc = device.beginFrame();
			if (enc != null) {
				draw(enc);
				device.endFrame();
			}
			frames++;
		}, e -> switch e.kind {
			case Resize: Sys.println('WebTest: resized to ${e.x}x${e.y} (${w.width}x${w.height})');
			case TextInput: Sys.println('WebTest: text ' + StringTools.hex(e.text.charCodeAt(0)));
			// (in the page's pixels)
			case Scroll: Sys.println('WebTest: scroll ${e.deltaX / w.scale} ${e.deltaY / w.scale}');
			case KeyDown if (e.key == 0xFF1B):
				Sys.println('WebTest: Escape after $frames frames');
				w.close();
			case _:
		});
		Sys.println('WebTest: window: ${w.width}x${w.height}, App.run returned (${name(device.backend)})');
	}

	static function name(b:Backend):String
		return switch b {
			case WebGPU: "WebGPU";
			case WebGL2: "WebGL2";
			case _: "?";
		}

	// FNV-1a of the bytes, as web.mjs computes it
	static function fnv(b:haxe.io.Bytes):String {
		var h = 0x811c9dc5;
		for (i in 0...b.length)
			h = (h ^ b.get(i)) * 0x01000193;
		return StringTools.hex(h, 8);
	}
}
