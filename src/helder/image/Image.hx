package helder.image;

import haxe.io.Bytes;

// An image's pixels: RGBA8, rows top to bottom, straight (not
// premultiplied) alpha. decode reads a PNG file (PngDecoder), a JPEG
// (JpegDecoder), a GIF (GifDecoder) or a WebP (WebpDecoder); renderers
// (helder.ui's ImageNode, a texture: helder.gfx.ImageTexture) upload it
// once (id: their key) and again after changed(); replace(other) puts
// another image's pixels in this one (helder.asset's reload: what shows it
// shows the new one).
//
// Its pixels are dropped once a renderer uploaded them (uploaded()), when
// it can have them again: from the file it was decoded from (source), or
// in a browser from the file the browser decoded (browser images:
// helder.asset's with decodeInBrowser, never in the module's memory unless
// read). Reading pixels after that decodes the file again, on the calling
// thread; retain keeps them, for an image whose pixels are read back (a
// hit test's alpha, a picker's colours).
class Image {
	public var width(default, null):Int;
	public var height(default, null):Int;
	// (decoded again from the file when they were dropped)
	public var pixels(get, never):Bytes;
	// whether its pixels are here now (not to be decoded again)
	public var hasPixels(get, never):Bool;
	// keeps its pixels after an upload (they are read back)
	public var retain = false;
	// on the web, files read by helder.asset (Asset.image) decoded by the
	// browser and uploaded from there (helder.gfx.ImageTexture): their pixels
	// never in the module's memory; set before the loads start
	public static var decodeInBrowser = false;
	// (the browser's decoded image: helder_image's handle, 0 none; and
	// whether its pixels are premultiplied)
	@:noCompletion public var browser(default, null) = 0;
	@:noCompletion public var browserPremultiplied(default, null) = false;
	var data:Null<Bytes>;
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
		this.data = pixels == null ? Bytes.alloc(width * height * 4) : pixels;
	}

	// an image the browser decoded (helder_image's handle: its file and
	// pixels there), of that size: no pixels here until they are read
	@:noCompletion public static function ofBrowser(handle:Int, width:Int, height:Int, premultiplied:Bool):Image {
		var img = new Image(1, 1, Bytes.alloc(4));
		img.width = width;
		img.height = height;
		img.data = null;
		img.browser = handle;
		img.browserPremultiplied = premultiplied;
		return img;
	}

	function get_hasPixels()
		return data != null;

	function get_pixels():Bytes {
		if (data != null) return data;
		var file = source != null ? source.bytes : browserFile();
		if (file == null) throw "Image: its pixels were dropped and it has no file to decode them from";
		var d = decode(file);
		if (d.width != width || d.height != height) throw "Image: its file is not of its size";
		return data = d.data;
	}

	// (a browser image's file, copied into the module)
	function browserFile():Null<Bytes>
		return browser != 0 && browserImages != null ? browserImages.file(browser) : null;

	// (helder_image's functions, given by what makes browser images:
	// helder.asset's ImageAsset; a program without them imports none)
	@:noCompletion public static var browserImages:Null<{file:Int->Bytes, close:Int->Void}> = null;

	// a renderer uploaded it: its pixels dropped unless retain or they could
	// not come back (no file); a browser image's decoded pixels closed (its
	// file kept)
	public function uploaded() {
		if (retain) return;
		if (data != null && (source != null || browser != 0)) data = null;
		if (browser != 0 && browserImages != null) browserImages.close(browser);
	}

	// the width and height a PNG, JPEG, GIF or WebP file says (its header),
	// null when it is none of those or its header is cut short
	public static function size(b:Bytes, offset = 0, length = -1):Null<{width:Int, height:Int}> {
		var n = length < 0 ? b.length - offset : length, o = offset;
		inline function u8(i:Int)
			return b.get(o + i);
		inline function be16(i:Int)
			return (u8(i) << 8) | u8(i + 1);
		inline function le16(i:Int)
			return u8(i) | (u8(i + 1) << 8);
		if (n >= 24 && u8(0) == 0x89 && u8(1) == 0x50 && u8(2) == 0x4E && u8(3) == 0x47)
			return {width: (be16(16) << 16) | be16(18), height: (be16(20) << 16) | be16(22)};
		if (n >= 10 && u8(0) == 0x47 && u8(1) == 0x49 && u8(2) == 0x46)
			return {width: le16(6), height: le16(8)};
		if (n >= 30 && u8(0) == 0x52 && u8(1) == 0x49 && u8(8) == 0x57 && u8(9) == 0x45) {
			var c = b.getString(o + 12, 4);
			if (c == "VP8X") return {width: 1 + (u8(24) | (u8(25) << 8) | (u8(26) << 16)), height: 1 + (u8(27) | (u8(28) << 8) | (u8(29) << 16))};
			if (c == "VP8L") {
				var v = u8(21) | (u8(22) << 8) | (u8(23) << 16) | (u8(24) << 24);
				return {width: (v & 0x3FFF) + 1, height: ((v >> 14) & 0x3FFF) + 1};
			}
			if (c == "VP8 ") return {width: le16(26) & 0x3FFF, height: le16(28) & 0x3FFF};
			return null;
		}
		if (n >= 4 && u8(0) == 0xFF && u8(1) == 0xD8) {
			// (the markers up to a frame's: SOF0 to SOF15 but DHT, JPG and DAC;
			// EXIF's orientation 5 to 8 turns it a quarter, as decode does)
			var i = 2, turned = false;
			while (i + 9 < n) {
				if (u8(i) != 0xFF) return null;
				var m = u8(i + 1);
				if (m == 0xFF) {
					i++;
					continue;
				}
				if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
					var w = be16(i + 7), h = be16(i + 5);
					return w > 0 && h > 0 ? (turned ? {width: h, height: w} : {width: w, height: h}) : null;
				}
				if (m == 0xD8 || (m >= 0xD0 && m <= 0xD7) || m == 0x01) {
					i += 2;
					continue;
				}
				if (m == 0xE1 && i + 18 < n && b.getString(o + i + 4, 4) == "Exif") {
					var t = i + 10, le = u8(t) == 0x49;
					inline function r16(k:Int)
						return le ? le16(k) : be16(k);
					inline function r32(k:Int)
						return le ? le16(k) | (le16(k + 2) << 16) : (be16(k) << 16) | be16(k + 2);
					var ifd = t + r32(t + 4);
					if (ifd + 2 <= n) {
						var count = r16(ifd);
						for (e in 0...count) {
							var at = ifd + 2 + 12 * e;
							if (at + 12 > n) break;
							if (r16(at) == 0x0112) turned = r16(at + 8) >= 5 && r16(at + 8) <= 8;
						}
					}
				}
				i += 2 + be16(i + 2);
			}
		}
		return null;
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
		data = other.data;
		version++;
		source = other.source;
		drawing = other.drawing;
		browser = other.browser;
		browserPremultiplied = other.browserPremultiplied;
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
		if (data == null) get_pixels();
		version++;
		browser = 0;
		source = null;
		drawing = null;
	}
}
