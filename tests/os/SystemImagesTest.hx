import helder.image.ImageError;
import helder.image.ImageLimits;
import helder.os.SystemImages;

// helder.os's system decoders (the system-images lane: Windows' WIC,
// macOS's ImageIO; under Wine too): a TIFF of a known gradient, plain and
// LZW (its size, its pixels within a level, its straight alpha), HEIC where
// the lane made one (macOS: sips), at a side asked for (ImageIO scales),
// ImageLimits before any pixel (TooLarge), a file that is no image.
//
//   SystemImagesTest dir [heic]
class SystemImagesTest {
	static var failed = 0;

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println('SystemImagesTest: ${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	static function kind(f:Void->Void):String
		return try {
			f();
			"ok";
		} catch (e:ImageError) Std.string(e.kind);

	static function main() {
		var dir = Sys.args()[0];
		check("available", SystemImages.available() && SystemImages.supports("a/b.TIFF") && !SystemImages.supports("a.txt"));
		for (f in ["gradient.tif", "gradient-lzw.tif"]) {
			var d = SystemImages.decode('$dir/$f');
			check('$f: its size', d.width == 64 && d.height == 48 && d.pixelsWidth == 64, '${d.width}x${d.height}');
			// (x * 4, y * 5, 200; alpha 255 left, 128 right in the plain one)
			var worst = 0;
			for (y in 0...48)
				for (x in 0...64) {
					var p = 4 * (y * 64 + x);
					worst = Std.int(Math.max(worst, Math.max(Math.abs(d.rgba.get(p) - x * 4), Math.max(Math.abs(d.rgba.get(p + 1) - y * 5), Math.abs(d.rgba.get(p + 2) - 200)))));
				}
			check('$f: its pixels within two levels', worst <= 2, 'worst $worst');
			if (f == "gradient.tif") check('$f: its alpha straight', d.rgba.get(3) == 255 && Math.abs(d.rgba.get(4 * 40 + 3) - 128) <= 1, '${d.rgba.get(4 * 40 + 3)}');
		}
		if (Sys.args().length > 1) {
			var heic = Sys.args()[1];
			var d = SystemImages.decode(heic);
			check("HEIC: its size", d.width == 64 && d.height == 48, '${d.width}x${d.height}');
			var small = SystemImages.decode(heic, 32);
			check("HEIC at a side of 32: scaled as decoded", small.pixelsWidth == 32 && small.width == 64, '${small.pixelsWidth}x${small.pixelsHeight}');
		}
		var keep = ImageLimits.maxPixels;
		ImageLimits.maxPixels = 100;
		check("ImageLimits first: TooLarge", kind(() -> SystemImages.decode('$dir/gradient.tif')) == "too large");
		ImageLimits.maxPixels = keep;
		var notImage = sys.FileSystem.fullPath('$dir/../SystemImagesTest.hx');
		var k = kind(() -> SystemImages.decode(notImage));
		check("not an image: Unsupported or Corrupt", k == "unsupported" || k == "corrupt", k);
		Sys.exit(failed > 0 ? 1 : 0);
	}
}
