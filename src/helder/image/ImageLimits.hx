package helder.image;

// What a decode may take, checked by every decoder right after its header
// (and an animation's frames as they come), before anything of the
// header's size is allocated: an image's pixels, its sides, and the bytes
// its decode needs (the pixels, the decoder's working buffers, an
// animation's frames). Over any of them: an ImageError of kind TooLarge.
// Set them before decoding (a viewer of huge scans raises them, a
// thumbnailer of untrusted uploads lowers them); a Bytes' length (2 GB)
// stays the ceiling whatever they say.
class ImageLimits {
	// pixels (width * height): 2^28, some 268 MP
	public static var maxPixels = 268435456.0;
	// either side, in pixels
	public static var maxSide = 65536;
	// the bytes one decode may allocate: 2 GiB
	public static var maxMemory = 2147483648.0;

	// (the ceiling: a Bytes' length, an Int)
	static inline var CEILING = 2147483647.0;

	// w x h pixels of format (its decoder's name) checked: a positive size,
	// within the sides and pixels, its decode (bytesPerPixel for each pixel
	// plus extra bytes) within the memory; the bytes it needs
	public static function check(format:String, width:Int, height:Int, bytesPerPixel = 4.0, extra = 0.0):Float {
		if (width <= 0 || height <= 0) throw ImageError.corrupt('$format: an empty size (${width}x$height)');
		var px = (width : Float) * height;
		if (width > maxSide || height > maxSide)
			throw ImageError.tooLarge('$format: ${width}x$height is over ImageLimits.maxSide ($maxSide)');
		if (px > maxPixels || px * 4 > CEILING)
			throw ImageError.tooLarge('$format: ${width}x$height (${mp(px)} MP) is over ImageLimits.maxPixels (${mp(maxPixels)} MP)');
		var bytes = px * bytesPerPixel + extra;
		memory(format, bytes);
		return bytes;
	}

	// bytes of a decode checked against the memory budget
	public static function memory(format:String, bytes:Float) {
		if (bytes > maxMemory || !(bytes == bytes))
			throw ImageError.tooLarge('$format: its decode needs ${mb(bytes)} MB, over ImageLimits.maxMemory (${mb(maxMemory)} MB)');
	}

	// a product of sizes read from a file (a frame's w * h * 4, a row's
	// bytes), an Int when it is one (within a Bytes' length), else TooLarge
	public static function size(format:String, a:Int, b:Int, c = 1):Int {
		var n = (a : Float) * b * c;
		if (a < 0 || b < 0 || c < 0) throw ImageError.corrupt('$format: a negative size');
		if (n > CEILING) throw ImageError.tooLarge('$format: a size of ${mb(n)} MB');
		return Std.int(n);
	}

	// f run as format's decode: what it throws an ImageError (an index out
	// of a hostile file's range, a string of its own: Corrupt)
	public static function guard<T>(format:String, f:() -> T):T {
		return try f() catch (e:ImageError) {
			// (the reader's refusals name no decoder: this one's)
			throw StringTools.startsWith(e.message, format) ? e : new ImageError(e.kind, '$format: ${e.message}');
		} catch (e:String) {
			throw ImageError.corrupt(StringTools.startsWith(e, format) ? e : '$format: $e');
		} catch (e:haxe.Exception) {
			throw ImageError.corrupt('$format: ${e.message}');
		} catch (e:Dynamic) {
			throw ImageError.corrupt('$format: $e');
		}
	}

	static function mp(px:Float):String
		return Std.string(Math.round(px / 1e5) / 10);

	static function mb(b:Float):String
		return Std.string(Math.round(b / 1048576));
}
