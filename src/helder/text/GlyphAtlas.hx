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
// uploading it); when the bitmap is full it is cleared (generation counts
// the clears: the glyphs drawn before must be asked for again). A glyph
// blurred (a text shadow's) is a glyph of its own: its coverage spread by a
// Gaussian, the bitmap grown by three of its standard deviations each side.
// A glyph is drawn by a GlyphPipeline and Rasterizer kept for the next, a
// blur in buffers kept too: a miss allocates its AtlasGlyph, nothing else.
class GlyphAtlas {
	// a synthetic oblique's slant: x moves by a quarter of y (Skia's)
	static inline var SKEW = 0.25;

	public final width:Int;
	public final height:Int;
	public final pixels:Bytes;
	public var generation(default, null) = 0;
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
	final faces = new Map<String, IntTable<AtlasGlyph>>();
	// (the faces asked for lately, the last first: a frame's text takes a few
	// in turn, found again without making their key)
	final recent:Array<Face> = [];
	final shelves:Array<Shelf> = [];
	// (what draws a glyph, kept for the next: the pipeline and rasterizer; a
	// blur's sharp coverage, its pass across and its weights)
	final raster = new Rasterizer(0, 0);
	final pipeline = new GlyphPipeline();
	var sharp = Bytes.alloc(0);
	var across = new haxe.ds.Vector<Float>(0);
	var weights = new haxe.ds.Vector<Float>(0);

	public function new(width = 1024, height = 1024) {
		this.width = width;
		this.height = height;
		pixels = Bytes.alloc(width * height);
		pixels.fill(0, pixels.length, 0);
	}

	// the glyph's bitmap in the atlas (rasterized now if needed): sub is the
	// phase of its origin right of a pixel's edge, in sixtieths (0 to 59:
	// phase()); oblique: slanted a quarter of its height, as browsers make an
	// italic the font lacks; blur: the standard deviation of a Gaussian
	// blurring it, in pixels (0: none); ink: the colour it is drawn in
	// (0xRRGGBB, sRGB), which sets font smoothing's dilation
	public function get(font:FontFile, glyph:Int, size:Float, sub:Int, oblique = false, blur = 0.0, ink = 0):AtlasGlyph {
		var d = dilation(font, size, oblique, ink);
		var glyphs = face(font, size, oblique, blur, d), key = glyph * SUBPIXELS + sub;
		var g = glyphs.get(key, null);
		if (g != null) return g;
		g = rasterize(font, glyph, size, sub, oblique, blur, d);
		if (g == null) {
			// full: start again
			clear();
			glyphs = face(font, size, oblique, blur, d);
			g = rasterize(font, glyph, size, sub, oblique, blur, d);
			if (g == null) g = new AtlasGlyph(0, 0, 0, 0, 0, 0);
		}
		glyphs.set(key, g);
		return g;
	}

	// (font smoothing's radius for a glyph of helder's engine: 0 with it
	// off, or where the platform's engine draws; -1: the plain pipeline, off)
	inline function dilation(font:FontFile, size:Float, oblique:Bool, ink:Int):Float {
		var mode = smoothing == null ? Shaping.smoothing : smoothing;
		if (!oblique && !font.bitmapsOnly && Shaping.backendFor(font) != null) return 0;
		return mode == Off ? -1 : GlyphPipeline.radius(size, GlyphPipeline.bucket(ink));
	}

	static inline var RECENT = 8;

	function face(font:FontFile, size:Float, oblique:Bool, blur:Float, d:Float):IntTable<AtlasGlyph> {
		for (i in 0...recent.length) {
			var f = recent[i];
			if (f.font == font && f.size == size && f.oblique == oblique && f.blur == blur && f.d == d) {
				// (moved to the front)
				for (j in 0...i)
					recent[i - j] = recent[i - j - 1];
				recent[0] = f;
				return f.glyphs;
			}
		}
		var key = font.id + ":" + size + (oblique ? ":o" : "") + (blur > 0 ? ":b" + blur : "") + ":d" + d;
		var m = faces.get(key);
		if (m == null) faces.set(key, m = new IntTable());
		if (recent.length < RECENT) recent.push(null);
		for (j in 0...recent.length - 1)
			recent[recent.length - 1 - j] = recent[recent.length - 2 - j];
		recent[0] = new Face(font, size, oblique, blur, d, m);
		return m;
	}

	function rasterize(font:FontFile, glyph:Int, size:Float, sub:Int, oblique:Bool, blur:Float, d:Float):Null<AtlasGlyph> {
		var dx = sub / SUBPIXELS;
		// (the platform's raster, where the face's engine is the platform's: FreeType, DirectWrite, Core Text)
		var be = oblique || font.bitmapsOnly ? null : Shaping.backendFor(font);
		if (be != null && be.rasterize(font, glyph, size, dx, native)) return placeNative(blur);
		// (helder's own: CoreGraphics' pipeline, dilated by d where font smoothing is on)
		var r = raster, p = pipeline;
		if (!p.draw(font, glyph, size, dx, d > 0 ? d : 0, oblique ? SKEW : 0, r)) return new AtlasGlyph(0, 0, 0, 0, 0, 0);
		var w = r.width, h = r.height, x0 = p.left, y0 = p.top;
		// (blurred: grown on each side by what the blur reaches)
		var pad = blur > 0 ? Math.ceil(3 * blur) : 0;
		var spot = place(w + 2 * pad, h + 2 * pad);
		if (spot < 0) return null;
		var sx = spot & 0xFFFF, sy = spot >>> 16;
		if (pad == 0) {
			r.writeTo(pixels, sy * width + sx, width);
			touch(sx, sy, w, h);
			return new AtlasGlyph(sx, sy, w, h, x0, y0);
		}
		if (sharp.length < w * h) sharp = Bytes.alloc(w * h * 2);
		r.writeTo(sharp, 0, w);
		blurInto(sharp, w, h, pad, blur, sy * width + sx);
		touch(sx, sy, w + 2 * pad, h + 2 * pad);
		return new AtlasGlyph(sx, sy, w + 2 * pad, h + 2 * pad, x0 - pad, y0 - pad);
	}

	final native = new Shaping.GlyphBitmap();

	// (the platform's bitmap into the atlas, blurred or not)
	function placeNative(blur:Float):Null<AtlasGlyph> {
		var b = native, w = b.width, h = b.height;
		if (w == 0 || h == 0) return new AtlasGlyph(0, 0, 0, 0, 0, 0);
		var pad = blur > 0 ? Math.ceil(3 * blur) : 0;
		var spot = place(w + 2 * pad, h + 2 * pad);
		if (spot < 0) return null;
		var sx = spot & 0xFFFF, sy = spot >>> 16;
		if (pad == 0) {
			for (y in 0...h)
				pixels.blit((sy + y) * width + sx, b.pixels, y * w, w);
			touch(sx, sy, w, h);
			return new AtlasGlyph(sx, sy, w, h, b.left, b.top);
		}
		blurInto(b.pixels, w, h, pad, blur, sy * width + sx);
		touch(sx, sy, w + 2 * pad, h + 2 * pad);
		return new AtlasGlyph(sx, sy, w + 2 * pad, h + 2 * pad, b.left - pad, b.top - pad);
	}

	// a w x h coverage bitmap blurred into the atlas at offset, pad more on
	// each side: a Gaussian of standard deviation sigma across, then down
	// (its weights each pixel's share of the curve, summing to one)
	function blurInto(src:Bytes, w:Int, h:Int, pad:Int, sigma:Float, offset:Int) {
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
				pixels.set(offset + y * width + x, c > 255 ? 255 : c);
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

	public function clear() {
		faces.clear();
		recent.resize(0);
		shelves.resize(0);
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
class AtlasGlyph {
	public final x:Int;
	public final y:Int;
	public final w:Int;
	public final h:Int;
	public final left:Int;
	public final top:Int;

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

private class Face {
	public final font:FontFile;
	public final size:Float;
	public final oblique:Bool;
	public final blur:Float;
	public final d:Float;
	public final glyphs:IntTable<AtlasGlyph>;

	public function new(font, size, oblique, blur, d, glyphs) {
		this.font = font;
		this.size = size;
		this.oblique = oblique;
		this.blur = blur;
		this.d = d;
		this.glyphs = glyphs;
	}
}
