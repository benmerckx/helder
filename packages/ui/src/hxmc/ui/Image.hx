package hxmc.ui;

import haxe.io.Bytes;

// An image's pixels for the UI (an ImageNode, the markup's image element):
// RGBA8, rows top to bottom, straight (not premultiplied) alpha. decode
// reads a PNG file (PngDecoder), a JPEG (JpegDecoder), a GIF (GifDecoder) or a WebP (WebpDecoder); renderers
// upload it once (id: their key) and again after changed().
class Image {
	public final width:Int;
	public final height:Int;
	public final pixels:Bytes;
	// unique per image (a renderer's texture cache key)
	public final id:Int = nextId++;
	// bumped by changed(): the pixels were written to
	public var version(default, null) = 0;

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
		var d = bytes.length >= 2 && bytes.get(0) == 0xFF && bytes.get(1) == 0xD8 ? JpegDecoder.decode(bytes) : bytes.length >= 4
			&& bytes.getString(0, 4) == "GIF8" ? GifDecoder.decode(bytes) : bytes.length >= 12 && bytes.getString(0, 4) == "RIFF"
			&& bytes.getString(8, 4) == "WEBP" ? WebpDecoder.decode(bytes) : PngDecoder.decode(bytes);
		return new Image(d.width, d.height, d.rgba);
	}

	// the pixels changed: renderers upload them again
	public function changed()
		version++;
}
