package helder.text;

import haxe.io.Bytes;

// Rasterized glyphs packed into one coverage bitmap (R8, width x height),
// for a GPU texture: each glyph of a face at a size and a pen phase once,
// placed on shelves (rows as tall as their tallest glyph, a pixel apart).
// helder's own engine draws them through CoreGraphics' glyph pipeline
// (GlyphPipeline: what macOS's CoreText draws), its font smoothing as a
// mode (smoothing: FontSmoothing, the app's Shaping.smoothing unless set:
// a window's): with it on a glyph's outline is dilated by its ink's
// luminance (get's ink), so a light and a dark ink are glyphs of their own;
// each mode keeps its own entries. Pens are floored to CoreGraphics'
// subpixel steps (pixel, phase: fifths of a pixel to wholes by the ppem).
// dirty is the region changed since the last upload (clean() after
// uploading it). Drawn in frames (begin before each): what a frame drew
// may be read from the bitmap until it is uploaded and drawn, so the bitmap
// never changes under it. A glyph that does not fit is none (get: null, the
// atlas full); the next begin makes room, between frames: the glyphs the
// last frame drew packed again, the others evicted (least recently drawn,
// by frame), the bitmap grown first (to max a side) where those take more
// than half of it (generation counts the repacks: what was drawn before
// must be asked for again). A glyph blurred (a text shadow's) is a glyph of
// its own: its coverage spread by a Gaussian, the bitmap grown by three of
// its standard deviations each side. One too large for an atlas is drawn
// alone (bitmap). A glyph is drawn by a GlyphPipeline and Rasterizer kept
// for the next, a blur in buffers kept too: a miss allocates its
// AtlasGlyph, nothing else.
class GlyphAtlas {
	// a synthetic oblique's slant: x moves by a quarter of y (Skia's)
	static inline var SKEW = 0.25;

	public var width(default, null):Int;
	public var height(default, null):Int;
	public var pixels(default, null):Bytes;
	// the largest side it grows to (a GPU's largest texture: Renderer's device's)
	public var max:Int;
	public var generation(default, null) = 0;
	// whether a glyph did not fit this frame (get gave none)
	public var full(default, null) = false;
	// the region to upload: x0, y0 (inclusive) to x1, y1 (exclusive); empty when x1 <= x0
	public var dirtyX0(default, null) = 0;
	public var dirtyY0(default, null) = 0;
	public var dirtyX1(default, null) = 0;
	public var dirtyY1(default, null) = 0;

	// font smoothing for helder's own engine's glyphs (null: the app's, Shaping.smoothing)
	public var smoothing:Null<FontSmoothing> = null;

	// the phases a pixel holds (get's sub): sixtieths, every step CoreGraphics quantises pens to
	public static inline var SUBPIXELS = GlyphPipeline.PHASES;

	// the pixel and phase (sixtieths: get's sub) a glyph whose pen is at x
	// device pixels draws at, size its ppem: floored to CoreGraphics' step
	public static inline function pixel(x:Float, size:Float):Int
		return GlyphPipeline.penPixel(x, size);

	public static inline function phase(x:Float, size:Float):Int
		return GlyphPipeline.penPhase(x, size);

	// per face (font, size, oblique, blur, dilation): its glyphs by glyph * SUBPIXELS + sub
	final faces = new Map<String, Face>();
	// (the faces asked for lately, the last first: a frame's text takes a few
	// in turn, found again without making their key)
	final recent:Array<Face> = [];
	final shelves:Array<Shelf> = [];
	// (every glyph kept, the empty ones too: what a repack goes through)
	var glyphs:Array<AtlasGlyph> = [];
	var spare:Array<AtlasGlyph> = [];
	var back = Bytes.alloc(0);
	var frame = 0;
	// (what draws a glyph, kept for the next: the pipeline and rasterizer; a
	// blur's sharp coverage, its pass across and its weights; the bitmap
	// drawn, its size and place from the origin)
	final raster = new Rasterizer(0, 0);
	final pipeline = new GlyphPipeline();
	var sharp = Bytes.alloc(0);
	var across = new haxe.ds.Vector<Float>(0);
	var weights = new haxe.ds.Vector<Float>(0);
	var drawn = 0;
	var bw = 0;
	var bh = 0;
	var bleft = 0;
	var btop = 0;
	final alone = new Shaping.GlyphBitmap();

	public function new(width = 1024, height = 1024, ?max:Int) {
		this.width = width;
		this.height = height;
		this.max = max == null ? (width > height ? width : height) : max;
		pixels = Bytes.alloc(width * height);
		pixels.fill(0, pixels.length, 0);
	}

	// the glyph's bitmap in the atlas (rasterized now if needed; null: it
	// does not fit this frame, full): sub is the phase of its origin right
	// of a pixel's edge, in sixtieths (0 to 59: phase()); oblique: slanted a
	// quarter of its height, as browsers make an italic the font lacks;
	// blur: the standard deviation of a Gaussian blurring it, in pixels (0:
	// none); ink: the colour it is drawn in (0xRRGGBB, sRGB), which sets font
	// smoothing's dilation
	public function get(font:FontFile, glyph:Int, size:Float, sub:Int, oblique = false, blur = 0.0, ink = 0):Null<AtlasGlyph> {
		var d = dilation(font, size, oblique, ink);
		var f = face(font, size, oblique, blur, d), key = glyph * SUBPIXELS + sub;
		var g = f.glyphs.get(key, null);
		if (g == null) {
			g = rasterize(font, glyph, size, sub, oblique, blur, d);
			if (g == null) {
				full = true;
				return null;
			}
			g.face = f;
			g.key = key;
			f.glyphs.set(key, g);
			glyphs.push(g);
		}
		g.used = frame;
		return g;
	}

	// the glyph drawn alone, not into the atlas (one too large for it), as
	// get draws it: its coverage (width x height, kept for the next: copy
	// it) and its top left from its origin; null: nothing to draw
	public function bitmap(font:FontFile, glyph:Int, size:Float, sub:Int, oblique = false, blur = 0.0, ink = 0):Null<Shaping.GlyphBitmap> {
		var d = dilation(font, size, oblique, ink);
		if (!draw(font, glyph, size, sub / SUBPIXELS, oblique, d)) return null;
		var pad = blur > 0 ? Math.ceil(3 * blur) : 0, b = alone;
		b.size(bw + 2 * pad, bh + 2 * pad);
		b.left = bleft - pad;
		b.top = btop - pad;
		write(pad, blur, b.pixels, 0, b.width);
		return b;
	}

	// a frame begins: a full atlas makes room, the last frame's glyphs kept
	public function begin() {
		var last = frame++;
		if (!full) return;
		full = false;
		generation++;
		var kept = spare, area = 0;
		kept.resize(0);
		for (g in glyphs)
			if (g.used == last) {
				kept.push(g);
				area += (g.w + 1) * (g.h + 1);
			}
		// (grown where those take more than half, a side at a time: room for the next frame's)
		var w = width, h = height;
		while (area * 2 > w * h && (w < max || h < max))
			if (h < w) h = h * 2 > max ? max : h * 2 else w = w * 2 > max ? max : w * 2;
		// (the tallest first, so shelves are filled evenly)
		kept.sort((a, b) -> b.h - a.h);
		// (into the bitmap kept from the last repack, where it is the size: the old kept for the next)
		var old = pixels, ow = width;
		pixels = back.length == w * h ? back : Bytes.alloc(w * h);
		pixels.fill(0, pixels.length, 0);
		back = old;
		width = w;
		height = h;
		shelves.resize(0);
		recent.resize(0);
		for (f in faces)
			f.glyphs = new IntTable();
		spare = glyphs;
		glyphs = kept;
		var n = 0;
		for (g in kept) {
			if (g.w > 0) {
				var spot = place(g.w, g.h);
				// (no room even so: dropped, drawn again when asked)
				if (spot < 0) continue;
				var sx = spot & 0xFFFF, sy = spot >>> 16;
				for (y in 0...g.h)
					pixels.blit((sy + y) * w + sx, old, (g.y + y) * ow + g.x, g.w);
				g.x = sx;
				g.y = sy;
			}
			g.face.glyphs.set(g.key, g);
			kept[n++] = g;
		}
		kept.resize(n);
		for (k in [for (k => f in faces) if (f.glyphs.count == 0) k])
			faces.remove(k);
		dirtyX0 = dirtyY0 = 0;
		dirtyX1 = w;
		dirtyY1 = h;
	}

	// (font smoothing's radius for a glyph of helder's engine: 0 with it
	// off, or where the platform's engine draws; -1: the plain pipeline, off)
	inline function dilation(font:FontFile, size:Float, oblique:Bool, ink:Int):Float {
		var mode = smoothing == null ? Shaping.smoothing : smoothing;
		if (!oblique && !font.bitmapsOnly && Shaping.backendFor(font) != null) return 0;
		return mode == Off ? -1 : GlyphPipeline.radius(size, GlyphPipeline.bucket(ink));
	}

	static inline var RECENT = 8;

	function face(font:FontFile, size:Float, oblique:Bool, blur:Float, d:Float):Face {
		for (i in 0...recent.length) {
			var f = recent[i];
			if (f.font == font && f.size == size && f.oblique == oblique && f.blur == blur && f.d == d) {
				// (moved to the front)
				for (j in 0...i)
					recent[i - j] = recent[i - j - 1];
				recent[0] = f;
				return f;
			}
		}
		var key = font.id + ":" + size + (oblique ? ":o" : "") + (blur > 0 ? ":b" + blur : "") + ":d" + d;
		var f = faces.get(key);
		if (f == null) faces.set(key, f = new Face(font, size, oblique, blur, d));
		if (recent.length < RECENT) recent.push(null);
		for (j in 0...recent.length - 1)
			recent[recent.length - 1 - j] = recent[recent.length - 2 - j];
		recent[0] = f;
		return f;
	}

	function rasterize(font:FontFile, glyph:Int, size:Float, sub:Int, oblique:Bool, blur:Float, d:Float):Null<AtlasGlyph> {
		if (!draw(font, glyph, size, sub / SUBPIXELS, oblique, d)) return new AtlasGlyph(0, 0, 0, 0, 0, 0);
		// (blurred: grown on each side by what the blur reaches)
		var pad = blur > 0 ? Math.ceil(3 * blur) : 0, w = bw + 2 * pad, h = bh + 2 * pad;
		var spot = place(w, h);
		if (spot < 0) return null;
		var sx = spot & 0xFFFF, sy = spot >>> 16;
		write(pad, blur, pixels, sy * width + sx, width);
		touch(sx, sy, w, h);
		var g = new AtlasGlyph(sx, sy, w, h, bleft - pad, btop - pad);
		// (the platform's raster, sharp: blended as the platform blends it, Shaping.GlyphBlend)
		if (drawn == 2 && pad == 0) g.blend = Shaping.backendFor(font)?.blend();
		return g;
	}

	// (the glyph drawn: its coverage in raster's bitmap (drawn 1) or native's
	// (2), bw x bh, its top left bleft, btop; false: nothing to draw)
	function draw(font:FontFile, glyph:Int, size:Float, dx:Float, oblique:Bool, d:Float):Bool {
		// (the platform's raster, where the face's engine is the platform's: FreeType, DirectWrite, Core Text)
		var be = oblique || font.bitmapsOnly ? null : Shaping.backendFor(font);
		if (be != null && be.rasterize(font, glyph, size, dx, native)) {
			var b = native;
			drawn = 2;
			bw = b.width;
			bh = b.height;
			bleft = b.left;
			btop = b.top;
			return bw > 0 && bh > 0;
		}
		// (helder's own: CoreGraphics' pipeline, dilated by d where font smoothing is on)
		var r = raster, p = pipeline;
		if (!p.draw(font, glyph, size, dx, d > 0 ? d : 0, oblique ? SKEW : 0, r)) return false;
		drawn = 1;
		bw = r.width;
		bh = r.height;
		bleft = p.left;
		btop = p.top;
		return true;
	}

	final native = new Shaping.GlyphBitmap();

	// (what draw drew into dst at offset, rows stride apart, blurred or not)
	function write(pad:Int, blur:Float, dst:Bytes, offset:Int, stride:Int) {
		var w = bw, h = bh;
		if (pad == 0) {
			if (drawn == 1) raster.writeTo(dst, offset, stride);
			else
				for (y in 0...h)
					dst.blit(offset + y * stride, native.pixels, y * w, w);
			return;
		}
		var src = native.pixels;
		if (drawn == 1) {
			if (sharp.length < w * h) sharp = Bytes.alloc(w * h * 2);
			raster.writeTo(sharp, 0, w);
			src = sharp;
		}
		blurInto(src, w, h, pad, blur, dst, offset, stride);
	}

	// a w x h coverage bitmap blurred into the atlas at offset, pad more on
	// each side: a Gaussian of standard deviation sigma across, then down
	// (its weights each pixel's share of the curve, summing to one)
	function blurInto(src:Bytes, w:Int, h:Int, pad:Int, sigma:Float, dst:Bytes, offset:Int, stride:Int) {
		var taps = 2 * pad + 1, sum = 0.0;
		if (weights.length < taps) weights = new haxe.ds.Vector(taps * 2);
		for (i in 0...taps) {
			var d = i - pad;
			weights[i] = Math.exp(-d * d / (2 * sigma * sigma));
			sum += weights[i];
		}
		for (i in 0...taps)
			weights[i] /= sum;
		var bw = w + 2 * pad, bh = h + 2 * pad;
		// (across: each source row into the wider one)
		if (across.length < bw * h) across = new haxe.ds.Vector(bw * h * 2);
		for (y in 0...h)
			for (x in 0...bw) {
				var v = 0.0;
				for (i in 0...taps) {
					var sx = x - pad + i - pad;
					if (sx >= 0 && sx < w) v += weights[i] * src.get(y * w + sx);
				}
				across[y * bw + x] = v;
			}
		// (down: into the atlas, taller by pad each side)
		for (y in 0...bh)
			for (x in 0...bw) {
				var v = 0.0;
				for (i in 0...taps) {
					var sy = y - pad + i - pad;
					if (sy >= 0 && sy < h) v += weights[i] * across[sy * bw + x];
				}
				var c = Std.int(v + 0.5);
				dst.set(offset + y * stride + x, c > 255 ? 255 : c);
			}
	}

	// a place for w x h: x | y << 16 (-1: full)
	function place(w:Int, h:Int):Int {
		if (w + 1 > width || h + 1 > height) return -1;
		for (s in shelves)
			if (h <= s.height && s.x + w + 1 <= width) {
				var p = s.x | s.y << 16;
				s.x += w + 1;
				return p;
			}
		var y = shelves.length == 0 ? 0 : shelves[shelves.length - 1].y + shelves[shelves.length - 1].height + 1;
		if (y + h > height) return -1;
		var s = new Shelf(y, h);
		shelves.push(s);
		s.x = w + 1;
		return y << 16;
	}

	function touch(x:Int, y:Int, w:Int, h:Int) {
		if (dirtyX1 <= dirtyX0) {
			dirtyX0 = x;
			dirtyY0 = y;
			dirtyX1 = x + w;
			dirtyY1 = y + h;
		} else {
			if (x < dirtyX0) dirtyX0 = x;
			if (y < dirtyY0) dirtyY0 = y;
			if (x + w > dirtyX1) dirtyX1 = x + w;
			if (y + h > dirtyY1) dirtyY1 = y + h;
		}
	}

	// the dirty region was uploaded
	public function clean() {
		dirtyX0 = dirtyY0 = dirtyX1 = dirtyY1 = 0;
	}

	// everything dropped (between frames)
	public function clear() {
		faces.clear();
		recent.resize(0);
		shelves.resize(0);
		glyphs.resize(0);
		full = false;
		pixels.fill(0, pixels.length, 0);
		generation++;
		dirtyX0 = 0;
		dirtyY0 = 0;
		dirtyX1 = width;
		dirtyY1 = height;
	}
}

// where a glyph's bitmap is in the atlas, and its top left relative to the
// glyph's origin (on the baseline, y down)
@:allow(helder.text.GlyphAtlas)
class AtlasGlyph {
	public var x(default, null):Int;
	public var y(default, null):Int;
	public final w:Int;
	public final h:Int;
	public final left:Int;
	public final top:Int;
	// how it is blended, drawn by the platform (Windows' DirectWrite: its
	// contrast and gamma); null: its coverage as it is
	public var blend:Null<Shaping.GlyphBlend> = null;
	// (its face and key there, the last frame that drew it: a repack's)
	var face:Null<Face> = null;
	var key = 0;
	var used = 0;

	public function new(x, y, w, h, left, top) {
		this.x = x;
		this.y = y;
		this.w = w;
		this.h = h;
		this.left = left;
		this.top = top;
	}
}

private class Shelf {
	public final y:Int;
	public final height:Int;
	public var x = 0;

	public function new(y, height) {
		this.y = y;
		this.height = height;
	}
}

@:allow(helder.text.GlyphAtlas)
private class Face {
	public final font:FontFile;
	public final size:Float;
	public final oblique:Bool;
	public final blur:Float;
	public final d:Float;
	public var glyphs = new IntTable<AtlasGlyph>();

	public function new(font, size, oblique, blur, d) {
		this.font = font;
		this.size = size;
		this.oblique = oblique;
		this.blur = blur;
		this.d = d;
	}
}
