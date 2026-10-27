import haxe.io.Bytes;

// How far two RGBA images of one size differ: per pixel the largest
// difference of its red, green and blue (alpha left out), and over the
// image, or rows top to bottom (exclusive), their mean, how many pixels
// differ at all, how many by more than a tolerance (far), the largest. The
// image tests (UiDrawTest, BoxTest, EmojiTest) compare with their
// references through it.
class ImageDiff {
	public final count:Int;
	public final differ:Int;
	public final far:Int;
	public final max:Int;
	public final mean:Float;
	public final tolerance:Int;

	function new(count, differ, far, max, mean, tolerance) {
		this.count = count;
		this.differ = differ;
		this.far = far;
		this.max = max;
		this.mean = mean;
		this.tolerance = tolerance;
	}

	public static function of(got:Bytes, want:Bytes, width:Int, height:Int, tolerance:Int, top = 0, bottom = -1):ImageDiff {
		if (bottom < 0) bottom = height;
		if (got.length < width * height * 4 || want.length < width * height * 4) throw "ImageDiff: not " + width + "x" + height;
		var differ = 0, far = 0, max = 0, total = 0.0;
		for (p in top * width...bottom * width) {
			var o = 4 * p, d = 0;
			for (k in 0...3) {
				var v = got.get(o + k) - want.get(o + k);
				if (v < 0) v = -v;
				if (v > d) d = v;
			}
			total += d;
			if (d > 0) differ++;
			if (d > tolerance) far++;
			if (d > max) max = d;
		}
		var count = (bottom - top) * width;
		return new ImageDiff(count, differ, far, max, count == 0 ? 0 : total / count, tolerance);
	}

	// whether at most share of the pixels are far (and, when given, the mean under mean)
	public function within(share:Float, ?mean:Float):Bool
		return far <= share * count && (mean == null || this.mean < mean);

	public function toString():String
		return differ == 0 ? "exact" : '$differ pixels differ, $far by more than $tolerance, at most $max, mean ${Math.round(mean * 100) / 100}';
}
