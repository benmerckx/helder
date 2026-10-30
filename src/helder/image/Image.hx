package helder.image;

import haxe.io.Bytes;

// An image's pixels: RGBA8, rows top to bottom, straight (not
// premultiplied) alpha. decode reads a PNG file (PngDecoder), a JPEG
// (JpegDecoder), a GIF (GifDecoder) or a WebP (WebpDecoder); renderers
// (helder.ui's ImageNode, a texture) upload it once (id: their key) and
// again after changed(); replace(other) puts another image's pixels in
// this one (helder.asset's reload: what shows it shows the new one).
class Image {
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var pixels(default, null):Bytes;
	// unique per image (a renderer's texture cache key)
	public final id:Int = nextId++;
	// bumped by changed(): the pixels were written to
	public var version(default, null) = 0;
	// the file it was decoded from (decode; type "png", "jpeg", "gif" or
	// "webp"), kept for a writer to embed as it is (a PDF's JPEG); null once
	// its pixels change, or when it was made from pixels
	public var source(default, null):Null<{bytes:Bytes, type:String}> = null;
	// what it was rendered from, for a writer to draw as vectors (helder.ui's
	// Svg.render: {svg:Drawing, color:Color}, an icon in its colour); null
	// once its pixels change
	@:allow(helder.ui.Svg) public var drawing(default, null):Null<Any> = null;

	static var nextId = 1;

	public function new(width:Int, height:Int, ?pixels:Bytes) {
		if (width <= 0 || height <= 0) throw "Image: an empty size";
		if (pixels != null && pixels.length != width * height * 4) throw "Image: " + pixels.length + " bytes for " + width + "x" + height;
		this.width = width;
		this.height = height;
		this.pixels = pixels == null ? Bytes.alloc(width * height * 4) : pixels;
	}

	// a PNG, JPEG, GIF or WebP file's image (by its signature)
	public static function decode(bytes:Bytes):Image {
		var type = bytes.length >= 2 && bytes.get(0) == 0xFF && bytes.get(1) == 0xD8 ? "jpeg" : bytes.length >= 4
			&& bytes.getString(0, 4) == "GIF8" ? "gif" : bytes.length >= 12 && bytes.getString(0, 4) == "RIFF" && bytes.getString(8, 4) == "WEBP" ? "webp" : "png";
		var d = switch type {
			case "jpeg": JpegDecoder.decode(bytes);
			case "gif": GifDecoder.decode(bytes);
			case "webp": WebpDecoder.decode(bytes);
			case _: PngDecoder.decode(bytes);
		}
		var img = new Image(d.width, d.height, d.rgba);
		img.source = {bytes: bytes, type: type};
		return img;
	}

	// other's pixels and size in this image (its source too): renderers
	// upload them again, at the new size
	public function replace(other:Image) {
		width = other.width;
		height = other.height;
		pixels = other.pixels;
		version++;
		source = other.source;
		drawing = other.drawing;
	}

	// its pixels premultiplied by their alpha, for `use` only (an upload:
	// a texture's data, copied there and then): with hxmc in a buffer off
	// the collected heap, freed after, so that a large image's upload leaves
	// no garbage of its size (on WebAssembly the heap's memory, grown for
	// it, is never given back)
	public function premultiplied(use:Bytes->Void) {
		var px = pixels, n = width * height;
		#if (target.name == "hxmc")
		var buf = hxmc.unsafe.IoBuffer.alloc(n * 4), pre = buf.view();
		#else
		var pre = Bytes.alloc(n * 4);
		#end
		for (k in 0...n) {
			var a = px.get(4 * k + 3);
			pre.set(4 * k, Std.int((px.get(4 * k) * a + 127) / 255));
			pre.set(4 * k + 1, Std.int((px.get(4 * k + 1) * a + 127) / 255));
			pre.set(4 * k + 2, Std.int((px.get(4 * k + 2) * a + 127) / 255));
			pre.set(4 * k + 3, a);
		}
		#if (target.name == "hxmc")
		try use(pre) catch (e:Dynamic) {
			buf.free();
			throw e;
		}
		buf.free();
		#else
		use(pre);
		#end
	}

	// the pixels changed: renderers upload them again
	public function changed() {
		version++;
		source = null;
		drawing = null;
	}
}
