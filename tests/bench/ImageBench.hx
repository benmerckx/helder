import haxe.io.Bytes;
import helder.image.*;

// helder.image's speed on a photo (the image-bench lane, natively; against
// vips and Bun.Image by tests/bench/image.mjs): a JPEG decoded (one
// thread, four), at 1/8, its 256-pixel thumbnail (1/8, then halved and
// boxed), a 50% resize (decoded at 1/2), a large PNG decoded; each the
// median of five runs, as JSON lines.
//
//   ImageBench photo.jpg large.png
class ImageBench {
	static function main() {
		var a = Sys.args(), jpg = sys.io.File.getBytes(a[0]), png = sys.io.File.getBytes(a[1]);
		function time(name:String, f:Void->Void) {
			var ts = [];
			for (i in 0...5) {
				var t = haxe.Timer.stamp();
				f();
				ts.push(haxe.Timer.stamp() - t);
			}
			ts.sort(Reflect.compare);
			Sys.println(haxe.Json.stringify({task: name, ms: Math.round(ts[2] * 10000) / 10}));
		}
		function off(f:ImageMemory->Void) {
			var m = ImageMemory.offHeapMemory();
			f(m);
			m.free();
		}
		time("jpeg decode, 1 thread", () -> off(m -> JpegDecoder.decode(jpg, m)));
		JpegDecoder.threads = 4;
		time("jpeg decode, 4 threads", () -> off(m -> JpegDecoder.decode(jpg, m)));
		time("jpeg at 1/8", () -> off(m -> JpegDecoder.decode(jpg, m, 8)));
		time("jpeg to a 256 px thumbnail", () -> off(m -> {
			var d = JpegDecoder.decode(jpg, m, 8);
			Resize.toFit(d.rgba, d.width, d.height, 256, 256, m);
		}));
		time("jpeg to 50% (decoded at 1/2)", () -> off(m -> JpegDecoder.decode(jpg, m, 2)));
		time("jpeg to 50% (decoded whole, halved)", () -> off(m -> {
			var d = JpegDecoder.decode(jpg, m);
			Resize.half(d.rgba, d.width, d.height, m);
		}));
		time("png decode", () -> off(m -> PngDecoder.decode(png, m)));
	}
}
