package viewer;

import haxe.io.Bytes;
import helder.image.*;

// A file decoded for the viewer, as a job (helder.jobs: a GC job on the
// pool, its result copied back) or on the calling thread (tests): its
// frames (one for a still image; an animated GIF's, WebP's or APNG's all),
// upright (JpegDecoder applies EXIF's orientation, a WebP's is applied
// here), at most MAX_SIDE a side (larger: halved until within, for the
// GPU; width and height stay the file's), or the error that stopped it.
typedef Decoded = {
	// the image's size as shown (upright), its pixels' (maybe halved)
	width:Int,
	height:Int,
	pixelsWidth:Int,
	pixelsHeight:Int,
	frames:Array<{rgba:Bytes, delay:Float}>,
	repetitions:Int,
	format:String,
	fileSize:Int,
	// null when decoded; else what to show, and its kind ("too large",
	// "corrupt", "unsupported", "unreadable")
	error:Null<String>,
	errorKind:String,
}

class Decode {
	// (the largest texture side every desktop GPU takes)
	public static inline var MAX_SIDE = 8192;

	// the job: a path in, a Decoded out
	public static function file(path:String):Decoded {
		var bytes = try sys.io.File.getBytes(path) catch (e:Dynamic) null;
		if (bytes == null) return failed("unreadable", "The file cannot be read", 0, "");
		return decode(bytes);
	}

	public static function decode(bytes:Bytes):Decoded {
		var format = formatOf(bytes);
		if (format == "") return failed("unsupported", "Not an image this viewer reads (PNG, JPEG, GIF, WebP)", bytes.length, "");
		try {
			var frames:Array<{rgba:Bytes, delay:Float}>, w:Int, h:Int, reps = 0;
			var animated = format == "GIF" || format == "WebP" || format == "PNG";
			if (animated) {
				var a = switch format {
					case "GIF": GifDecoder.frames(bytes);
					case "WebP": WebpDecoder.frames(bytes);
					case _: PngDecoder.frames(bytes);
				}
				w = a.width;
				h = a.height;
				frames = a.frames;
				reps = a.repetitions;
				if (format == "PNG" && frames.length > 1) format = "APNG";
			} else {
				var d = JpegDecoder.decode(bytes);
				w = d.width;
				h = d.height;
				frames = [{rgba: d.rgba, delay: 0.0}];
			}
			// (a WebP's EXIF orientation: libwebp leaves it to the viewer)
			if (format == "WebP" && frames.length == 1) {
				var o = Exif.orientation(bytes);
				if (o != 1) {
					var r = Exif.apply(frames[0].rgba, w, h, o);
					frames[0].rgba = r.rgba;
					w = r.width;
					h = r.height;
				}
			}
			var pw = w, ph = h;
			if (w > MAX_SIDE || h > MAX_SIDE) {
				if (frames.length > 1) return failed("too large", 'An animation of ${w}×$h is larger than this viewer shows (${MAX_SIDE} a side)', bytes.length, format);
				var rgba = frames[0].rgba;
				while (pw > MAX_SIDE || ph > MAX_SIDE) {
					var half = halve(rgba, pw, ph);
					rgba = half.rgba;
					pw = half.width;
					ph = half.height;
				}
				frames = [{rgba: rgba, delay: 0.0}];
			}
			return {
				width: w,
				height: h,
				pixelsWidth: pw,
				pixelsHeight: ph,
				frames: frames,
				repetitions: reps,
				format: format,
				fileSize: bytes.length,
				error: null,
				errorKind: ""
			};
		} catch (e:ImageError) {
			return failed(Std.string(e.kind), switch e.kind {
				case TooLarge: "Too large to open: " + after(e.message);
				case Unsupported: "Not supported: " + after(e.message);
				case _: "Damaged or cut short: " + after(e.message);
			}, bytes.length, format);
		}
	}

	// the format by the file's signature ("" none of the viewer's)
	public static function formatOf(b:Bytes):String {
		if (b.length >= 3 && b.get(0) == 0xFF && b.get(1) == 0xD8 && b.get(2) == 0xFF) return "JPEG";
		if (b.length >= 8 && b.get(0) == 0x89 && b.get(1) == 0x50 && b.get(2) == 0x4E && b.get(3) == 0x47) return "PNG";
		if (b.length >= 6 && b.getString(0, 3) == "GIF") return "GIF";
		if (b.length >= 12 && b.getString(0, 4) == "RIFF" && b.getString(8, 4) == "WEBP") return "WebP";
		return "";
	}

	// (what an ImageError says after its decoder's name)
	static function after(m:String):String {
		var i = m.indexOf(": ");
		return i < 0 ? m : m.substr(i + 2);
	}

	static function failed(kind:String, message:String, size:Int, format:String):Decoded
		return {
			width: 0,
			height: 0,
			pixelsWidth: 0,
			pixelsHeight: 0,
			frames: [],
			repetitions: 0,
			format: format,
			fileSize: size,
			error: message,
			errorKind: kind
		};

	// half the size, each pixel the mean of four (straight alpha weighted by it)
	public static function halve(src:Bytes, w:Int, h:Int):{width:Int, height:Int, rgba:Bytes} {
		var nw = (w + 1) >> 1, nh = (h + 1) >> 1, out = Bytes.alloc(nw * nh * 4);
		for (y in 0...nh)
			for (x in 0...nw) {
				var r = 0, g = 0, b = 0, a = 0;
				for (dy in 0...2)
					for (dx in 0...2) {
						var sx = Std.int(Math.min(2 * x + dx, w - 1)), sy = Std.int(Math.min(2 * y + dy, h - 1)), p = 4 * (sy * w + sx);
						var pa = src.get(p + 3);
						r += src.get(p) * pa;
						g += src.get(p + 1) * pa;
						b += src.get(p + 2) * pa;
						a += pa;
					}
				var o = 4 * (y * nw + x);
				if (a > 0) {
					out.set(o, Std.int(r / a + 0.5));
					out.set(o + 1, Std.int(g / a + 0.5));
					out.set(o + 2, Std.int(b / a + 0.5));
				}
				out.set(o + 3, (a + 2) >> 2);
			}
		return {width: nw, height: nh, rgba: out};
	}

	// the bytes a decoded image holds
	public static function bytesOf(d:Decoded):Float {
		var n = 0.0;
		for (f in d.frames)
			n += f.rgba.length;
		return n;
	}
}
