package helder.image;

import helder.test.Test;

// JpegDecoder at 1/2, 1/4 and 1/8 (reduced IDCTs): sizes rounded up, close
// to the full decode boxed down; scaleFor; in strips over threads: the
// same pixels as on one
function tests() {
	describe("JpegDecoder, scaled and in strips", () -> {
		var dir = "tests/image/jpeg";
		var names = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".jpg")) f];
		names.sort(Reflect.compare);
		test("in strips over three threads: the same pixels", () -> {
			for (n in names) {
				var file = sys.io.File.getBytes('$dir/$n');
				var one = JpegDecoder.decode(file).rgba.toHex();
				JpegDecoder.threads = 3;
				var three = try JpegDecoder.decode(file).rgba.toHex() catch (e:Dynamic) {
					JpegDecoder.threads = 1;
					throw e;
				}
				JpegDecoder.threads = 1;
				equals(three, one, n);
			}
		});
		test("1/2, 1/4, 1/8: their sizes, near the full decode boxed down", () -> {
			var file = sys.io.File.getBytes('$dir/large-420.jpg');
			var full = JpegDecoder.decode(file);
			for (s in [2, 4, 8]) {
				var d = JpegDecoder.decode(file, null, s);
				equals([d.width, d.height], [Math.ceil(full.width / s), Math.ceil(full.height / s)]);
				var boxed = Resize.toFit(full.rgba, full.width, full.height, d.width, d.height);
				var se = 0.0, n = 0;
				for (y in 0...d.height - 1)
					for (x in 0...d.width - 1)
						for (c in 0...3) {
							var e = d.rgba.get(4 * (y * d.width + x) + c) - boxed.rgba.get(4 * (y * boxed.width + x) + c);
							se += e * e;
							n++;
						}
				var psnr = 10 * Math.log(255 * 255 / (se / n)) / Math.log(10);
				// (a synthetic image of fine stripes: point-sampled blocks against boxes; libjpeg's own scaled decodes of a photo are 40-54 dB from these)
				assert(psnr > 20, '1/$s: $psnr dB');
			}
			equals(JpegDecoder.scaleFor(6000, 4000, 1100, 760), 4);
			equals(JpegDecoder.scaleFor(6000, 4000, 2000, 1500), 2);
			equals(JpegDecoder.scaleFor(800, 600, 1100, 760), 1);
			equals(JpegDecoder.scaleFor(6000, 4000, 100, 100), 8);
		});
	});
}
