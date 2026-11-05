package viewer;

import haxe.io.Bytes;
import helder.image.*;
import hxmc.unsafe.IoBuffer;

// A file decoded for the viewer, as a job (helder.jobs: a GC job on the
// pool, its pixels off the GC heap, moved back: ImageMemory, not copied;
// a still PNG a GC-free job, ImageJobs) or on the calling thread (tests): its
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
	// (off the GC heap: freed by release, when the cache lets it go)
	frames:Array<{pixels:IoBuffer, delay:Float}>,
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

	// a file decoded on the pool, from a coroutine: a still PNG as a GC-free
	// job (ImageJobs: PngCore over off-heap memory), the rest as a GC job
	// (file); never throws
	@:coroutine public static function job(path:String):Decoded {
		var bytes = try sys.io.File.getBytes(path) catch (e:Dynamic) null;
		if (bytes == null) return failed("unreadable", "The file cannot be read", 0, "");
		var size = Image.size(bytes);
		if (formatOf(bytes) == "PNG" && !apng(bytes) && size != null && size.width <= MAX_SIDE && size.height <= MAX_SIDE) {
			var p = try ImageJobs.pixels(IoBuffer.ofBytes(bytes)) catch (e:ImageError) return failedBy(e, bytes.length, "PNG") catch (e:helder.jobs.JobError)
				return failed("corrupt", "Damaged or cut short: " + after(e.message), bytes.length, "PNG");
			return {
				width: p.width,
				height: p.height,
				pixelsWidth: p.width,
				pixelsHeight: p.height,
				frames: [{pixels: p.rgba, delay: 0.0}],
				repetitions: 0,
				format: "PNG",
				fileSize: bytes.length,
				error: null,
				errorKind: ""
			};
		}
		return try helder.jobs.Jobs.run(file, path) catch (e:Dynamic) failed("corrupt", "The decode failed: " + Std.string(e), bytes.length, formatOf(bytes));
	}

	public static function decode(bytes:Bytes):Decoded {
		var format = formatOf(bytes);
		if (format == "") return failed("unsupported", "Not an image this viewer reads (PNG, JPEG, GIF, WebP)", bytes.length, "");
		try {
			var frames:Array<{rgba:Bytes, delay:Float}>, w:Int, h:Int, reps = 0;
			// (a still image's planes and pixels off the heap; an animation's frames on it, copied out)
			var mem = ImageMemory.offHeapMemory();
			var animated = format == "GIF" || (format == "WebP" && animatedWebp(bytes)) || (format == "PNG" && apng(bytes));
			if (!animated) {
				var d = switch format {
					case "JPEG": JpegDecoder.decode(bytes, mem);
					case "WebP": WebpDecoder.decode(bytes, mem);
					case _: PngDecoder.decode(bytes, mem);
				}
				w = d.width;
				h = d.height;
				frames = [{rgba: d.rgba, delay: 0.0}];
			} else {
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
			}
			// (a WebP's EXIF orientation: libwebp leaves it to the viewer)
			if (format == "WebP" && frames.length == 1) {
				var o = Exif.orientation(bytes);
				if (o != 1) {
					var r = Exif.apply(frames[0].rgba, w, h, o, mem);
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
					var half = halve(rgba, pw, ph, mem);
					rgba = half.rgba;
					pw = half.width;
					ph = half.height;
				}
				frames = [{rgba: rgba, delay: 0.0}];
			}
			// (the frames' buffers: a still image's kept from its memory, the rest freed; an animation's copied off the heap)
			var out = [for (f in frames) {pixels: mem.take(f.rgba), delay: f.delay}];
			mem.free();
			return {
				width: w,
				height: h,
				pixelsWidth: pw,
				pixelsHeight: ph,
				frames: out,
				repetitions: reps,
				format: format,
				fileSize: bytes.length,
				error: null,
				errorKind: ""
			};
		} catch (e:ImageError) {
			return failedBy(e, bytes.length, format);
		}
	}

	static function failedBy(e:ImageError, size:Int, format:String):Decoded
		return failed(Std.string(e.kind), switch e.kind {
			case TooLarge: "Too large to open: " + after(e.message);
			case Unsupported: "Not supported: " + after(e.message);
			case _: "Damaged or cut short: " + after(e.message);
		}, size, format);

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
	public static function halve(src:Bytes, w:Int, h:Int, ?mem:ImageMemory):{width:Int, height:Int, rgba:Bytes} {
		var nw = (w + 1) >> 1, nh = (h + 1) >> 1, out = (mem ?? ImageMemory.gc).bytes(nw * nh * 4);
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
			n += f.pixels.length;
		return n;
	}

	// its pixels freed (the cache let it go)
	public static function release(d:Decoded) {
		for (f in d.frames)
			f.pixels.free();
		d.frames = [];
	}

	// (an animated WebP: VP8X's animation flag; an animated PNG: an acTL before IDAT)
	static function animatedWebp(b:Bytes):Bool {
		var r = new ByteReader(b);
		return r.length >= 21 && r.string(12, 4) == "VP8X" && r.u8(20) & 2 != 0;
	}

	static function apng(b:Bytes):Bool {
		var r = new ByteReader(b), p = 8;
		while (p + 8 <= r.length) {
			var n = r.be32(p), name = r.string(p + 4, 4);
			if (name == "acTL") return true;
			if (name == "IDAT" || n < 0) return false;
			p += 12 + n;
		}
		return false;
	}
}
