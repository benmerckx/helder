package viewer;

import haxe.io.Bytes;
import helder.image.*;
import hxmc.unsafe.IoBuffer;

// A file decoded for the viewer, as a job (helder.jobs: a GC job on the
// pool, its pixels off the GC heap, moved back: ImageMemory, not copied;
// a still PNG a GC-free job, ImageJobs) or on the calling thread (tests): its
// frames (one for a still image; an animated GIF's, WebP's or APNG's all),
// upright (JpegDecoder applies EXIF's orientation, a WebP's is applied
// here), a JPEG at the size it is shown (a side asked for: decoded at
// 1/2, 1/4 or 1/8 while still at least that), at most MAX_PIXELS (larger:
// halved until within, the GPU's budget; ImageView tiles what is past a
// texture's side), or the error that stopped it. width and height stay the
// image's; pixelsWidth and pixelsHeight are what was decoded.
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
	// a PDF's page shown (from 0) and how many it has (1 for an image; 0 unknown: failed)
	page:Int,
	pages:Int,
	// null when decoded; else what to show, and its kind ("too large",
	// "corrupt", "unsupported", "unreadable")
	error:Null<String>,
	errorKind:String,
}

class Decode {
	// (the pixels a still image may have on the GPU: 128 MP, 512 MB and its mips)
	public static inline var MAX_PIXELS = 134217728;
	// (an animation's side: its frames one texture each)
	public static inline var MAX_SIDE = 8192;

	// what the cache and the jobs know a decode by: the file's path, and a
	// PDF's page past the first after a newline (no file's name has one: the
	// recent files are kept a line each)
	public static function key(path:String, page = 0):String
		return page <= 0 ? path : path + "\n" + page;

	public static function parseKey(key:String):{path:String, page:Int} {
		var nl = key.lastIndexOf("\n");
		return nl < 0 ? {path: key, page: 0} : {path: key.substr(0, nl), page: Std.parseInt(key.substr(nl + 1)) ?? 0};
	}

	// the job: a key in (a path, maybe a PDF's page: key; and the side it is shown at: 0, all of it), a Decoded out
	public static function file(req:{path:String, side:Int}):Decoded {
		var k = parseKey(req.path);
		// (a PDF already open: its page drawn, the file not read again)
		if (PdfPages.isOpen(k.path)) return pdf(k.path, null, k.page, req.side, 0);
		var bytes = try sys.io.File.getBytes(k.path) catch (e:Dynamic) null;
		if (bytes == null) return failed("unreadable", "The file cannot be read", 0, "");
		// (none of helder.image's: the system's decoders, TIFF, HEIC, AVIF, RAW, where there are some)
		if (formatOf(bytes) == "" && helder.os.SystemImages.supports(k.path)) return system(k.path, req.side, bytes.length);
		if (formatOf(bytes) == "PDF") return pdf(k.path, bytes, k.page, req.side, bytes.length);
		return decode(bytes, req.side);
	}

	// a PDF's page (helder.pdf, PdfPages: the document kept open for its next pages)
	@:hxmc.unsafe(gc) static function pdf(path:Null<String>, bytes:Null<Bytes>, page:Int, side:Int, size:Int):Decoded {
		return try {
			var p = PdfPages.render(path, bytes, page, side);
			var mem = ImageMemory.offHeapMemory();
			var px = mem.take(p.rgba);
			mem.free();
			{
				width: p.width,
				height: p.height,
				pixelsWidth: p.pixelsWidth,
				pixelsHeight: p.pixelsHeight,
				frames: [{pixels: px, delay: 0.0}],
				repetitions: 0,
				format: "PDF",
				fileSize: p.fileSize,
				page: page,
				pages: p.pages,
				error: null,
				errorKind: ""
			};
		} catch (e:helder.pdf.PdfError) {
			var d = failedPdf(e, size);
			d.page = page;
			// (the others may be fine: their count, when the document opened)
			d.pages = path == null ? 0 : Std.int(Math.max(0, PdfPages.pagesOf(path)));
			d;
		} catch (e:ImageError) {
			var d = failedBy(e, size, "PDF");
			d.page = page;
			d.pages = path == null ? 0 : Std.int(Math.max(0, PdfPages.pagesOf(path)));
			d;
		}
	}

	// (helder.os's SystemImages: WIC, ImageIO; ImageLimits before any pixel; upright, scaled where the system scales)
	@:hxmc.unsafe(gc) static function system(path:String, side:Int, size:Int):Decoded {
		var ext = path.substr(path.lastIndexOf(".") + 1).toUpperCase();
		var format = ext == "TIF" ? "TIFF" : ext == "HEIF" ? "HEIC" : ext;
		return try {
			var d = helder.os.SystemImages.decode(path, side);
			var rgba = d.rgba, pw = d.pixelsWidth, ph = d.pixelsHeight;
			if ((pw : Float) * ph > MAX_PIXELS) {
				var r = Resize.toFit(rgba, pw, ph, Std.int(Math.sqrt(MAX_PIXELS * pw / ph)), Std.int(Math.sqrt(MAX_PIXELS * ph / pw)));
				rgba = r.rgba;
				pw = r.width;
				ph = r.height;
			}
			{
				width: d.width,
				height: d.height,
				pixelsWidth: pw,
				pixelsHeight: ph,
				frames: [{pixels: IoBuffer.ofBytes(rgba), delay: 0.0}],
				repetitions: 0,
				format: format,
				fileSize: size,
				page: 0,
				pages: 1,
				error: null,
				errorKind: ""
			};
		} catch (e:ImageError) failedBy(e, size, format);
	}

	// a file decoded on the pool, from a coroutine: a still PNG as a GC-free
	// job (ImageJobs: PngCore over off-heap memory), the rest as a GC job
	// (file); never throws
	@:coroutine public static function job(path:String, side = 0):Decoded {
		// (a PDF's page: the GC job, its document kept there)
		if (path.indexOf("\n") >= 0 || PdfPages.isOpen(path))
			return try helder.jobs.Jobs.job(file).run({path: path, side: side}) catch (e:Dynamic) failed("corrupt", "The decode failed: " + Std.string(e), 0, "PDF");
		var bytes = try sys.io.File.getBytes(path) catch (e:Dynamic) null;
		if (bytes == null) return failed("unreadable", "The file cannot be read", 0, "");
		var size = Image.size(bytes);
		if (formatOf(bytes) == "PNG" && !apng(bytes) && size != null && (size.width : Float) * size.height <= MAX_PIXELS) {
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
				page: 0,
				pages: 1,
				error: null,
				errorKind: ""
			};
		}
		return try helder.jobs.Jobs.job(file).run({path: path, side: side}) catch (e:Dynamic) failed("corrupt", "The decode failed: " + Std.string(e), bytes.length, formatOf(bytes));
	}

	@:hxmc.unsafe(gc) public static function decode(bytes:Bytes, side = 0):Decoded {
		var format = formatOf(bytes);
		if (bytes.length == 0) return failed("corrupt", "The file is empty", 0, "");
		if (format == "") return failed("unsupported", "Not an image this viewer reads (PNG, JPEG, GIF, WebP, PDF" + (helder.os.SystemImages.available() ? "; the system's: TIFF, HEIC, AVIF, RAW" : "") + ")", bytes.length, "");
		try {
			var frames:Array<{rgba:Bytes, delay:Float}>, w:Int, h:Int, reps = 0;
			// (the image's own size, when it was decoded smaller)
			var full:Null<{width:Int, height:Int}> = null;
			// (a still image's planes and pixels off the heap; an animation's frames on it, copied out)
			var mem = ImageMemory.offHeapMemory();
			var animated = format == "GIF" || (format == "WebP" && animatedWebp(bytes)) || (format == "PNG" && apng(bytes));
			if (!animated) {
				var d = switch format {
					case "JPEG":
						// (at the size shown: the largest reduction still covering the side, either way round: EXIF may turn it)
						var sz = Image.size(bytes);
						var scale = side <= 0 || sz == null ? 1 : JpegDecoder.scaleFor(Std.int(Math.max(sz.width, sz.height)), Std.int(Math.max(sz.width, sz.height)), side, side);
						var d = JpegDecoder.decode(bytes, mem, scale);
						// (Image.size: the size shown, EXIF's turn applied)
						if (scale > 1) full = sz;
						d;
					case "WebP": WebpDecoder.decode(bytes, mem);
					case "PDF":
						// (its first page, the document not kept: PdfPages; a file's pages are file's)
						mem.free();
						return pdf(null, bytes, 0, side, bytes.length);
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
			if (full != null) {
				w = full.width;
				h = full.height;
			}
			if (frames.length > 1 && (w > MAX_SIDE || h > MAX_SIDE)) return failed("too large", 'An animation of ${w}×$h is larger than this viewer shows (${MAX_SIDE} a side)', bytes.length, format);
			if ((pw : Float) * ph > MAX_PIXELS) {
				var rgba = frames[0].rgba;
				while ((pw : Float) * ph > MAX_PIXELS) {
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
				page: 0,
				pages: 1,
				error: null,
				errorKind: ""
			};
		} catch (e:ImageError) {
			return failedBy(e, bytes.length, format);
		} catch (e:helder.pdf.PdfError) {
			return failedPdf(e, bytes.length);
		}
	}

	// (a PdfError said as an ImageError is: what is wrong first, helder.pdf's reason after)
	static function failedPdf(e:helder.pdf.PdfError, size:Int):Decoded
		return switch e.kind {
			case Encrypted: failed("encrypted", "This PDF is protected by a password", size, "PDF");
			case TooLarge: failed("too large", "Too large to open: " + e.message, size, "PDF");
			case Unsupported: failed("unsupported", "Not supported: " + e.message, size, "PDF");
			case _: failed("corrupt", "A damaged PDF: " + e.message, size, "PDF");
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
		if (b.length >= 5 && b.getString(0, 5) == "%PDF-") return "PDF";
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
			page: 0,
			pages: 0,
			error: message,
			errorKind: kind
		};

	// half the size, each pixel the mean of four (helder.image's Resize)
	public static function halve(src:Bytes, w:Int, h:Int, ?mem:ImageMemory):{width:Int, height:Int, rgba:Bytes}
		return Resize.half(src, w, h, mem);

	// the bytes a decoded image holds
	@:hxmc.unsafe(gc) public static function bytesOf(d:Decoded):Float {
		var n = 0.0;
		for (f in d.frames)
			n += f.pixels.length;
		return n;
	}

	// its pixels freed (the cache let it go)
	@:hxmc.unsafe(gc) public static function release(d:Decoded) {
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
