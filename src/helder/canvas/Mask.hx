package helder.canvas;

import haxe.io.Bytes;

// A coverage of the canvas's size (0 to 255 a pixel): a layer's mask
final class Mask {
	public final width:Int;
	public final height:Int;
	public final coverage:Bytes;

	public function new(width:Int, height:Int) {
		this.width = width;
		this.height = height;
		coverage = Bytes.alloc(width * height);
		coverage.fill(0, width * height, 0);
	}

	// a bitmap's alpha (luminance: its colours' luma times alpha, as SVG's mask)
	public static function ofBitmap(b:Bitmap, luminance = false):Mask {
		var m = new Mask(b.width, b.height), px = b.pixels;
		for (i in 0...b.width * b.height) {
			var o = i * 4;
			m.coverage.set(i, luminance ? Std.int((0.2125 * px.get(o) + 0.7154 * px.get(o + 1) + 0.0721 * px.get(o + 2)) + 0.5) : px.get(o + 3));
		}
		return m;
	}
}
