package helder.canvas.dom;

import haxe.io.Bytes;

// The browser's ImageData: straight RGBA pixels, rows of width. `data`
// is its bytes (a TypeScript program's Uint8ClampedArray, sharing them:
// what it writes there putImageData draws); Haxe reads and writes `bytes`.
class ImageData {
	public var width(default, null):Int;
	public var height(default, null):Int;
	public final colorSpace = "srgb";
	@:noCompletion public var bytes(default, null):Bytes;

	@:typescript.type("Uint8ClampedArray") public var data(get, never):Bytes;

	// (width, height): transparent; (array, width, height?): its bytes (a
	// typed array's shared, an array's copied)
	public function new(a:Dynamic, b:Int, ?c:Int) {
		if (Std.isOfType(a, Bytes)) {
			var data:Bytes = a;
			if (b <= 0) throw new Path2D.DOMException("IndexSizeError", "The source width is zero or not a number.");
			if (data.length % (4 * b) != 0 || data.length == 0)
				throw new Path2D.DOMException("IndexSizeError", "The input data length is not a multiple of (4 * width).");
			width = b;
			height = Std.int(data.length / (4 * b));
			if (c != null && c != height) throw new Path2D.DOMException("IndexSizeError", "The input data length is not equal to (4 * width * height).");
			bytes = data;
		} else if (Std.isOfType(a, Array)) {
			var list:Array<Dynamic> = a;
			if (b <= 0) throw new Path2D.DOMException("IndexSizeError", "The source width is zero or not a number.");
			if (list.length % (4 * b) != 0 || list.length == 0)
				throw new Path2D.DOMException("IndexSizeError", "The input data length is not a multiple of (4 * width).");
			width = b;
			height = Std.int(list.length / (4 * b));
			if (c != null && c != height) throw new Path2D.DOMException("IndexSizeError", "The input data length is not equal to (4 * width * height).");
			bytes = Bytes.alloc(list.length);
			for (i in 0...list.length) {
				var v:Float = list[i];
				bytes.set(i, v <= 0 || Math.isNaN(v) ? 0 : v >= 255 ? 255 : Std.int(Math.round(v)));
			}
		} else {
			var w:Int = Std.int(a);
			if (w <= 0 || b <= 0) throw new Path2D.DOMException("IndexSizeError", "The source width or height is zero.");
			width = w;
			height = b;
			bytes = Bytes.alloc(w * b * 4);
			bytes.fill(0, w * b * 4, 0);
		}
	}

	@:noCompletion public static function of(w:Int, h:Int, bytes:Bytes):ImageData {
		var d = new ImageData(1, 1);
		d.width = w;
		d.height = h;
		d.bytes = bytes;
		return d;
	}

	function get_data():Bytes
		return bytes;
}
