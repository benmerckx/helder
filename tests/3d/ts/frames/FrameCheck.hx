package frames;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.os.*;

// helder/scene's frames drawn by TypeScript (tests/3d/ts/frames.ts), as
// RenderTest draws Haxe's: headless, 256 x 192, against a golden image by
// packages/gfx's rule (GfxTest.compareBytes; HXMC_3D_TOLERANCE as
// RenderTest's). Declared to the program by FramesTypeScript.
//
//   frames <scene> <golden.png> <out.png> [--bless]
class FrameCheck {
	static inline var WIDTH = 256;
	static inline var HEIGHT = 192;

	// the program's arguments
	public static function args():Array<String>
		return Sys.args();

	// a headless device given to make, the frame make's function draws read
	// back and compared (the process ends with the result: 0 alike, 1 not,
	// 3 skipped: no Metal device)
	public static function run(make:Device->(Encoder->Void)):Void {
		var args = Sys.args();
		if (args.length < 3) {
			Sys.println("usage: frames <scene> <golden.png> <out.png> [--bless]");
			Sys.exit(2);
		}
		var name = args[0], golden = args[1], out = args[2];
		var device = try Device.create(Surface.headless(WIDTH, HEIGHT)) catch (e:String) {
			if (e != "helder.gfx: no Metal device") throw e;
			Sys.println("FrameCheck: skipped: no Metal device");
			Sys.exit(3);
			null;
		}
		var draw = make(device);
		var pixels = Bytes.alloc(WIDTH * HEIGHT * 4);
		var enc = device.beginFrame();
		draw(enc);
		device.readPixels(pixels);
		device.endFrame();
		device.dispose();
		sys.io.File.saveBytes(out, Png.encode(pixels, WIDTH, HEIGHT));
		if (args[3] == "--bless") {
			sys.io.File.saveBytes(golden, Png.encode(pixels, WIDTH, HEIGHT));
			Sys.println('FrameCheck: blessed $golden');
			Sys.exit(0);
		}
		var png = sys.io.File.getBytes(golden);
		var tolerance = Std.parseInt(Sys.getEnv("HXMC_3D_TOLERANCE") ?? "");
		if (tolerance != null && tolerance > 0) {
			var g = Png.decode(png);
			if (g.width == WIDTH && g.height == HEIGHT)
				for (k in 0...WIDTH * HEIGHT * 4)
					if (Math.abs(pixels.get(k) - g.rgba.get(k)) <= tolerance) pixels.set(k, g.rgba.get(k));
		}
		Sys.exit(GfxTest.compareBytes('$name (TypeScript), headless', pixels, png) ? 0 : 1);
	}
}
