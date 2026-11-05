package helder.canvas.dom;

// An image as skia-canvas's and @napi-rs/canvas's Image: set src to a
// file's path (or a data: URL), and it is decoded (helder.image: PNG,
// JPEG, GIF, WebP) at once; width, height and complete then say so.
// loadImage(src) gives one decoded.
class Image {
	public var width(default, null) = 0;
	public var height(default, null) = 0;
	public var complete(default, null) = false;
	public var src(default, set):String = "";
	public var onload:Null<() -> Void> = null;
	public var onerror:Null<(error:String) -> Void> = null;
	@:noCompletion public var bitmap(default, null):Null<helder.canvas.Bitmap> = null;

	public function new() {}

	// an image decoded from a file's path or a data: URL (throws when it is not one)
	public static function load(src:String):Image {
		var img = new Image();
		img.decode(src);
		return img;
	}

	function set_src(v:String):String {
		src = v;
		try {
			decode(v);
			if (onload != null) onload();
		} catch (e:Dynamic) {
			if (onerror != null) onerror(Std.string(e));
		}
		return v;
	}

	function decode(v:String) {
		@:bypassAccessor src = v;
		var bytes:haxe.io.Bytes;
		if (StringTools.startsWith(v, "data:")) {
			var comma = v.indexOf(",");
			if (comma < 0) throw "a data: URL without data";
			var head = v.substring(5, comma), body = v.substr(comma + 1);
			bytes = StringTools.endsWith(head, ";base64") ? haxe.crypto.Base64.decode(body) : haxe.io.Bytes.ofString(StringTools.urlDecode(body));
		} else
			bytes = sys.io.File.getBytes(v);
		var img = helder.image.Image.decode(bytes);
		bitmap = helder.canvas.Bitmap.fromImage(img);
		width = img.width;
		height = img.height;
		complete = true;
	}

	@:noCompletion public static function ofBitmap(b:helder.canvas.Bitmap):Image {
		var img = new Image();
		img.bitmap = b;
		img.width = b.width;
		img.height = b.height;
		img.complete = true;
		return img;
	}
}
