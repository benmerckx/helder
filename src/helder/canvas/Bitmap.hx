package helder.canvas;

import haxe.io.Bytes;

// Pixels as the canvas keeps them: RGBA8, premultiplied, rows of width.
// A canvas draws into one (Canvas.bitmap), images drawn and patterns are
// one; helder.image's Image (straight alpha) converts both ways.
final class Bitmap {
	public final width:Int;
	public final height:Int;
	public final pixels:Bytes;

	public function new(width:Int, height:Int, ?pixels:Bytes) {
		this.width = width;
		this.height = height;
		this.pixels = pixels ?? Bytes.alloc(width * height * 4);
		if (pixels == null) this.pixels.fill(0, width * height * 4, 0);
	}

	// straight RGBA (an Image's, ImageData's) premultiplied into a new bitmap
	public static function fromStraight(width:Int, height:Int, rgba:Bytes):Bitmap {
		var b = new Bitmap(width, height);
		b.writeStraight(rgba, 0, 0, width, height);
		return b;
	}

	public static inline function fromImage(image:helder.image.Image):Bitmap
		return fromStraight(image.width, image.height, image.pixels);

	// straight RGBA rows of w (the source's whole width) at (x, y): premultiplied in
	public function writeStraight(rgba:Bytes, x:Int, y:Int, w:Int, h:Int, srcStride = -1) {
		if (srcStride < 0) srcStride = w * 4;
		for (j in 0...h) {
			var ty = y + j;
			if (ty < 0 || ty >= height) continue;
			for (i in 0...w) {
				var tx = x + i;
				if (tx < 0 || tx >= width) continue;
				var s = j * srcStride + i * 4, o = (ty * width + tx) * 4, a = rgba.get(s + 3);
				if (a == 255) {
					pixels.set(o, rgba.get(s));
					pixels.set(o + 1, rgba.get(s + 1));
					pixels.set(o + 2, rgba.get(s + 2));
				} else {
					pixels.set(o, div255(rgba.get(s) * a));
					pixels.set(o + 1, div255(rgba.get(s + 1) * a));
					pixels.set(o + 2, div255(rgba.get(s + 2) * a));
				}
				pixels.set(o + 3, a);
			}
		}
	}

	// the region's pixels unpremultiplied into straight RGBA (rows of w)
	public function readStraight(out:Bytes, x:Int, y:Int, w:Int, h:Int) {
		for (j in 0...h) {
			var sy = y + j;
			for (i in 0...w) {
				var sx = x + i, o = (j * w + i) * 4;
				if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
					out.setInt32(o, 0);
					continue;
				}
				var s = (sy * width + sx) * 4, a = pixels.get(s + 3);
				if (a == 0) out.setInt32(o, 0) else if (a == 255) {
					out.set(o, pixels.get(s));
					out.set(o + 1, pixels.get(s + 1));
					out.set(o + 2, pixels.get(s + 2));
					out.set(o + 3, 255);
				} else {
					inline function un(c:Int):Int {
						var v = Std.int((c * 255 + (a >> 1)) / a);
						return v > 255 ? 255 : v;
					}
					out.set(o, un(pixels.get(s)));
					out.set(o + 1, un(pixels.get(s + 1)));
					out.set(o + 2, un(pixels.get(s + 2)));
					out.set(o + 3, a);
				}
			}
		}
	}

	// the whole bitmap as straight RGBA
	public function straight():Bytes {
		var out = Bytes.alloc(width * height * 4);
		readStraight(out, 0, 0, width, height);
		return out;
	}

	public function toImage():helder.image.Image
		return new helder.image.Image(width, height, straight());

	static inline function div255(v:Int):Int
		return Std.int((v + 128 + ((v + 128) >> 8)) >> 8);
}
