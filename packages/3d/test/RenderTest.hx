import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.os.*;

// packages/3d's frames natively against golden images (make 3d-check), by
// packages/gfx's rule (GfxTest.compareBytes: a pixel matches within 2 of
// each channel, at most 0.5% of them off), headless (Linux: an EGL pbuffer
// on llvmpipe; macOS: Metal; Windows: D3D11):
//
//   RenderTest <scene> <golden.png> <out.png> [--bless]
class RenderTest {
	static inline var WIDTH = 256;
	static inline var HEIGHT = 192;

	static function main() {
		var args = Sys.args();
		if (args.length < 3 || !Scenes.NAMES.contains(args[0])) {
			Sys.println("usage: RenderTest " + Scenes.NAMES.join("|") + " <golden.png> <out.png> [--bless]");
			Sys.exit(2);
		}
		var name = args[0], golden = args[1], out = args[2];
		var device = Device.create(Surface.headless(WIDTH, HEIGHT));
		var draw = Scenes.make(name, device);
		var pixels = Bytes.alloc(WIDTH * HEIGHT * 4);
		var enc = device.beginFrame();
		draw(enc);
		device.readPixels(pixels);
		device.endFrame();
		var stats = Scenes.renderer;
		var drawsOk = true;
		if (stats != null) {
			Sys.println('RenderTest: $name: ${stats.draws} draws, ${stats.instanced} instances in instanced draws, ${stats.culled} culled');
			// (169 nodes of two meshes: two instanced draws, unless culled)
			if (name == "instances" && (stats.draws > 2 || stats.instanced + stats.culled != 169)) drawsOk = false;
		}
		device.dispose();
		sys.io.File.saveBytes(out, Png.encode(pixels, WIDTH, HEIGHT));
		if (args[3] == "--bless") {
			sys.io.File.saveBytes(golden, Png.encode(pixels, WIDTH, HEIGHT));
			Sys.println('RenderTest: blessed $golden');
			return;
		}
		Sys.exit(GfxTest.compareBytes('$name, headless', pixels, sys.io.File.getBytes(golden)) && drawsOk ? 0 : 1);
	}
}
