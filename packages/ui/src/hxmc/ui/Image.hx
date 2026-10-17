package hxmc.ui;

import haxe.io.Bytes;

// An image's pixels for the UI (an ImageNode, the markup's image element):
// RGBA8, rows top to bottom, straight (not premultiplied) alpha. decode
// reads a PNG file (PngDecoder); renderers upload it once (id: their key)
// and again after changed().
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

	// a PNG file's image
	public static function decode(bytes:Bytes):Image {
		var d = PngDecoder.decode(bytes);
		return new Image(d.width, d.height, d.rgba);
	}

	// the pixels changed: renderers upload them again
	public function changed()
		version++;
}
