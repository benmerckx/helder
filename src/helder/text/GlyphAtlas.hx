package helder.text;

import haxe.io.Bytes;

// Rasterized glyphs packed into one coverage bitmap (R8, width x height),
// for a GPU texture: each glyph of a face at a size and a quarter-pixel
// horizontal offset once, placed on shelves (rows as tall as their tallest
// glyph, a pixel apart). dirty is the region changed since the last
// upload (clean() after uploading it); when the bitmap is full it is
// cleared (generation counts the clears: the glyphs drawn before must be
// asked for again). A glyph blurred (a text shadow's) is a glyph of its
// own: its coverage spread by a Gaussian, the bitmap grown by three of its
// standard deviations each side. A glyph is drawn by a Rasterizer kept for
// the next, a blur in buffers kept too: a miss allocates its AtlasGlyph,
// nothing else.
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

	public static inline var SUBPIXELS = 4;

	// per face (font, size, oblique, blur): its glyphs by glyph * SUBPIXELS + sub
	final faces = new Map<String, IntTable<AtlasGlyph>>();
	// (the faces asked for lately, the last first: a frame's text takes a few
	// in turn, found again without making their key)
	final recent:Array<Face> = [];
	final shelves:Array<Shelf> = [];
	// (what draws a glyph, kept for the next: the rasterizer; a blur's sharp
	// coverage, its pass across and its weights)
	final raster = new Rasterizer(0, 0);
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
	// quarter-pixel offset of its origin (0 to 3); oblique: slanted a quarter
	// of its height, as browsers make an italic the font lacks; blur: the
	// standard deviation of a Gaussian blurring it, in pixels (0: none)
	public function get(font:FontFile, glyph:Int, size:Float, sub:Int, oblique = false, blur = 0.0):AtlasGlyph {
		var glyphs = face(font, size, oblique, blur), key = glyph * SUBPIXELS + sub;
		var g = glyphs.get(key, null);
		if (g != null) return g;
		g = rasterize(font, glyph, size, sub, oblique, blur);
		if (g == null) {
			// full: start again
			clear();
			glyphs = face(font, size, oblique, blur);
			g = rasterize(font, glyph, size, sub, oblique, blur);
			if (g == null) g = new AtlasGlyph(0, 0, 0, 0, 0, 0);
		}
		glyphs.set(key, g);
		return g;
	}

	static inline var RECENT = 8;

	function face(font:FontFile, size:Float, oblique:Bool, blur:Float):IntTable<AtlasGlyph> {
		for (i in 0...recent.length) {
			var f = recent[i];
			if (f.font == font && f.size == size && f.oblique == oblique && f.blur == blur) {
				// (moved to the front)
				for (j in 0...i)
					recent[i - j] = recent[i - j - 1];
				recent[0] = f;
				return f.glyphs;
			}
		}
		var key = font.id + ":" + size + (oblique ? ":o" : "") + (blur > 0 ? ":b" + blur : "");
		var m = faces.get(key);
		if (m == null) faces.set(key, m = new IntTable());
		if (recent.length < RECENT) recent.push(null);
		for (j in 0...recent.length - 1)
			recent[recent.length - 1 - j] = recent[recent.length - 2 - j];
		recent[0] = new Face(font, size, oblique, blur, m);
		return m;
	}

	function rasterize(font:FontFile, glyph:Int, size:Float, sub:Int, oblique:Bool, blur:Float):Null<AtlasGlyph> {
		var scale = size / font.unitsPerEm, dx = sub / SUBPIXELS;
		if (!font.box(glyph)) return new AtlasGlyph(0, 0, 0, 0, 0, 0);
		var bx0 = font.boxX0, by0 = font.boxY0, bx1 = font.boxX1, by1 = font.boxY1;
		var k = oblique ? SKEW : 0.0;
		var x0 = Math.floor(Math.min(bx0 + k * by0, bx0 + k * by1) * scale + dx), x1 = Math.ceil(Math.max(bx1 + k * by0, bx1 + k * by1) * scale + dx);
		var y0 = Math.floor(-by1 * scale), y1 = Math.ceil(-by0 * scale);
		var w = x1 - x0 + 1, h = y1 - y0 + 1;
		// (blurred: grown on each side by what the blur reaches)
		var pad = blur > 0 ? Math.ceil(3 * blur) : 0;
		var spot = place(w + 2 * pad, h + 2 * pad);
		if (spot < 0) return null;
		var sx = spot & 0xFFFF, sy = spot >>> 16;
		var r = raster;
		r.reset(w, h);
		r.scaleX = scale;
		r.scaleY = -scale;
		r.offsetX = dx - x0;
		r.offsetY = -y0;
		r.skew = k;
		font.outline(glyph, r);
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
	public final glyphs:IntTable<AtlasGlyph>;

	public function new(font, size, oblique, blur, glyphs) {
		this.font = font;
		this.size = size;
		this.oblique = oblique;
		this.blur = blur;
		this.glyphs = glyphs;
	}
}
