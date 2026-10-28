package helder.image;

import haxe.io.Bytes;

// PNG files decoded to RGBA8 (Image.decode): every colour type (grey, RGB,
// palette, grey with alpha, RGBA), bit depths 1 to 16 (16 kept to their
// high byte), tRNS transparency (a palette's alphas, a grey or RGB colour
// key), the five scanline filters, Adam7 interlacing (PngCore's, the one
// decoder, which ImageJobs runs as a GC-free job); animated PNGs' frames
// (frames: APNG's regions, blends and disposals, as Chromium composes
// them). Ancillary chunks other than tRNS (gamma, colour profiles) are
// not applied. Errors are thrown as strings ("PngDecoder: ...").
class PngDecoder {
	// the pixels: width * height * 4 bytes, rows top to bottom, straight alpha
	// (an animated PNG's: its default image)
	public static function decode(png:Bytes):{width:Int, height:Int, rgba:Bytes} {
		var info = header(png);
		var w = info.i32(PngCore.WIDTH), h = info.i32(PngCore.HEIGHT);
		var px = w * h * 4, len = PngCore.bufferLength(info, w, h), out = Bytes.alloc(px);
		// (decoded in the result when it is the room needed, else beside it, the pixels copied in)
		var e = if (len == px) PngCore.decode(Raw.of(png), png.length, info, Raw.of(out)) else {
			var b = Raw.malloc(len);
			var e = b.isNull() ? PngCore.ERR_MEMORY : PngCore.decode(Raw.of(png), png.length, info, b);
			if (e == 0) b.copyTo(out, px);
			if (!b.isNull()) b.free();
			e;
		}
		check(e, info);
		info.free();
		return {width: w, height: h, rgba: out};
	}

	// (the header read: its info, the caller's to free; an error thrown)
	static function header(png:Bytes):Raw {
		var info = Raw.malloc(PngCore.INFO);
		if (info.isNull()) throw "PngDecoder: out of memory";
		check(PngCore.info(Raw.of(png), png.length, info), info);
		return info;
	}

	static function check(e:Int, info:Raw)
		if (e != 0) {
			var m = PngCore.message(e, info);
			info.free();
			throw m;
		}

	// a frame's region: its zlib stream, w x h pixels of the header's format
	static function region(png:Bytes, info:Raw, data:Bytes, w:Int, h:Int):Bytes {
		var px = w * h * 4, len = PngCore.bufferLength(info, w, h), out = Bytes.alloc(px);
		var b = Raw.malloc(len);
		var e = b.isNull() ? PngCore.ERR_MEMORY : PngCore.decodeStream(Raw.of(png), info, Raw.of(data), data.length, w, h, b);
		if (e == 0) b.copyTo(out, px);
		if (!b.isNull()) b.free();
		check(e, info);
		return out;
	}

	// an animated PNG's frames (APNG: acTL, fcTL, fdAT), each composed over
	// the ones before as browsers compose them (its region drawn as it
	// says: replacing what was there or over it; then left, cleared or put
	// back as it was), with its delay (seconds) and the repetitions after
	// the first play (-1: forever); a PNG without animation, its image as
	// the one frame. A frame drawn over another blends with straight alpha.
	public static function frames(png:Bytes):{width:Int, height:Int, repetitions:Int, frames:Array<{rgba:Bytes, delay:Float}>} {
		var info = header(png);
		var w = info.i32(PngCore.WIDTH), height = info.i32(PngCore.HEIGHT);
		var f = animation(png);
		if (f.frames.length == 0) {
			info.free();
			return {width: w, height: height, repetitions: 0, frames: [{rgba: decode(png).rgba, delay: 0.0}]};
		}
		var canvas = Bytes.alloc(w * height * 4), out = [];
		for (k in 0...f.frames.length) {
			var a = f.frames[k];
			if (a.x < 0 || a.y < 0 || a.width <= 0 || a.height <= 0 || a.x + a.width > w || a.y + a.height > height) {
				info.free();
				throw "PngDecoder: a frame outside the image";
			}
			var sub = region(png, info, a.inIdat ? f.idat : a.parts.getBytes(), a.width, a.height);
			// (put back after it: the canvas before it; the first frame's "previous" is a clear)
			var before = a.dispose == 2 && k > 0 ? canvas.sub(0, canvas.length) : null;
			for (y in 0...a.height) {
				var o = 4 * ((a.y + y) * w + a.x), s = 4 * y * a.width;
				if (a.blend == 0) canvas.blit(o, sub, s, 4 * a.width) else
					for (i in 0...a.width)
						over(canvas, o + 4 * i, sub, s + 4 * i);
			}
			out.push({rgba: canvas.sub(0, canvas.length), delay: a.delay});
			if (a.dispose == 1 || (a.dispose == 2 && before == null))
				for (y in 0...a.height)
					canvas.fill(4 * ((a.y + y) * w + a.x), 4 * a.width, 0);
			else if (before != null) canvas = before;
		}
		info.free();
		return {width: w, height: height, repetitions: f.plays == 0 ? -1 : f.plays - 1, frames: out};
	}

	// (a pixel over another, straight alpha: the source's colour weighted by
	// its alpha, the destination's by what of its alpha shows through)
	static function over(dst:Bytes, d:Int, src:Bytes, s:Int) {
		var sa = src.get(s + 3);
		if (sa == 0) return;
		var da = dst.get(d + 3);
		if (sa == 255 || da == 0) {
			dst.blit(d, src, s, 4);
			return;
		}
		var keep = da * (255 - sa), a = sa * 255 + keep;
		for (c in 0...3)
			dst.set(d + c, Std.int((src.get(s + c) * sa * 255 + dst.get(d + c) * keep + (a >> 1)) / a));
		dst.set(d + 3, Std.int((a + 127) / 255));
	}

	// (APNG's chunks: acTL's plays, each fcTL's frame and its fdAT data,
	// the default image's IDAT data when a frame is it; the file's other
	// chunks are PngCore's)
	static function animation(png:Bytes):{plays:Int, frames:Array<ApngFrame>, idat:Bytes} {
		var frames = [], plays = 0, idat = new haxe.io.BytesBuffer(), frame:Null<ApngFrame> = null, seenIdat = false;
		var p = 8;
		while (p + 8 <= png.length) {
			var n = u32(png, p), name = png.getString(p + 4, 4), at = p + 8;
			switch name {
				case "acTL" if (n >= 8):
					plays = u32(png, at + 4);
				case "fcTL" if (n >= 26):
					frame = new ApngFrame();
					frame.width = u32(png, at + 4);
					frame.height = u32(png, at + 8);
					frame.x = u32(png, at + 12);
					frame.y = u32(png, at + 16);
					var num = (png.get(at + 20) << 8) | png.get(at + 21), den = (png.get(at + 22) << 8) | png.get(at + 23);
					frame.delay = num / (den == 0 ? 100 : den);
					frame.dispose = png.get(at + 24);
					frame.blend = png.get(at + 25);
					// (before the image data: the default image is the first frame)
					frame.inIdat = !seenIdat;
					frames.push(frame);
				case "IDAT":
					seenIdat = true;
					idat.addBytes(png, at, n);
				case "fdAT" if (frame != null && n >= 4):
					frame.parts.addBytes(png, at + 4, n - 4);
				case "IEND":
					break;
				case _:
			}
			p += 12 + n;
		}
		return {plays: plays, frames: frames, idat: idat.getBytes()};
	}

	static inline function u32(b:Bytes, p:Int):Int
		return (b.get(p) << 24) | (b.get(p + 1) << 16) | (b.get(p + 2) << 8) | b.get(p + 3);

}

// (an fcTL's frame: its region, delay, how it is drawn (blend: 0 source,
// 1 over) and left (dispose: 0 none, 1 background, 2 previous), its data)
private class ApngFrame {
	public var width = 0;
	public var height = 0;
	public var x = 0;
	public var y = 0;
	public var delay = 0.0;
	public var dispose = 0;
	public var blend = 0;
	public var inIdat = false;
	public final parts = new haxe.io.BytesBuffer();

	public function new() {}
}
