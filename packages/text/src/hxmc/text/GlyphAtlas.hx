package hxmc.text;

import haxe.io.Bytes;

// Rasterized glyphs packed into one coverage bitmap (R8, width x height),
// for a GPU texture: each glyph of a face at a size and a quarter-pixel
// horizontal offset once, placed on shelves (rows as tall as their tallest
// glyph, a pixel apart). dirty is the region changed since the last
// upload (clean() after uploading it); when the bitmap is full it is
// cleared (generation counts the clears: the glyphs drawn before must be
// asked for again). A glyph blurred (a text shadow's) is a glyph of its
// own: its coverage spread by a Gaussian, the bitmap grown by three of its
// standard deviations each side.
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
	final faces = new Map<String, haxe.ds.IntMap<AtlasGlyph>>();
	// (the face asked for last: a paragraph's glyphs share one)
	var lastFont:Null<FontFile> = null;
	var lastSize = 0.0;
	var lastOblique = false;
	var lastBlur = 0.0;
	var lastFace:Null<haxe.ds.IntMap<AtlasGlyph>> = null;
	final shelves:Array<Shelf> = [];

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
		var g = glyphs.get(key);
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

	function face(font:FontFile, size:Float, oblique:Bool, blur:Float):haxe.ds.IntMap<AtlasGlyph> {
		if (lastFace != null && font == lastFont && size == lastSize && oblique == lastOblique && blur == lastBlur) return lastFace;
		var key = font.id + ":" + size + (oblique ? ":o" : "") + (blur > 0 ? ":b" + blur : "");
		var m = faces.get(key);
		if (m == null) faces.set(key, m = new haxe.ds.IntMap());
		lastFont = font;
		lastSize = size;
		lastOblique = oblique;
		lastBlur = blur;
		return lastFace = m;
	}

	function rasterize(font:FontFile, glyph:Int, size:Float, sub:Int, oblique:Bool, blur:Float):Null<AtlasGlyph> {
		var scale = size / font.unitsPerEm, dx = sub / SUBPIXELS;
		var b = font.bounds(glyph);
		if (b[2] <= b[0] || b[3] <= b[1]) return new AtlasGlyph(0, 0, 0, 0, 0, 0);
		var k = oblique ? SKEW : 0.0;
		var x0 = Math.floor(Math.min(b[0] + k * b[1], b[0] + k * b[3]) * scale + dx), x1 = Math.ceil(Math.max(b[2] + k * b[1], b[2] + k * b[3]) * scale + dx);
		var y0 = Math.floor(-b[3] * scale), y1 = Math.ceil(-b[1] * scale);
		var w = x1 - x0 + 1, h = y1 - y0 + 1;
		// (blurred: grown on each side by what the blur reaches)
		var pad = blur > 0 ? Math.ceil(3 * blur) : 0;
		var spot = place(w + 2 * pad, h + 2 * pad);
		if (spot == null) return null;
		var r = new Rasterizer(w, h);
		r.scaleX = scale;
		r.scaleY = -scale;
		r.offsetX = dx - x0;
		r.offsetY = -y0;
		if (oblique) font.outline(glyph, new Skewed(r, k)) else font.outline(glyph, r);
		if (pad == 0) {
			r.writeTo(pixels, spot.y * width + spot.x, width);
			touch(spot.x, spot.y, w, h);
			return new AtlasGlyph(spot.x, spot.y, w, h, x0, y0);
		}
		var sharp = Bytes.alloc(w * h);
		r.writeTo(sharp, 0, w);
		blurInto(sharp, w, h, pad, blur, spot.y * width + spot.x);
		touch(spot.x, spot.y, w + 2 * pad, h + 2 * pad);
		return new AtlasGlyph(spot.x, spot.y, w + 2 * pad, h + 2 * pad, x0 - pad, y0 - pad);
	}

	// a w x h coverage bitmap blurred into the atlas at offset, pad more on
	// each side: a Gaussian of standard deviation sigma across, then down
	// (its weights each pixel's share of the curve, summing to one)
	function blurInto(src:Bytes, w:Int, h:Int, pad:Int, sigma:Float, offset:Int) {
		var weights = new haxe.ds.Vector<Float>(2 * pad + 1), sum = 0.0;
		for (i in 0...2 * pad + 1) {
			var d = i - pad;
			weights[i] = Math.exp(-d * d / (2 * sigma * sigma));
			sum += weights[i];
		}
		for (i in 0...2 * pad + 1)
			weights[i] /= sum;
		var bw = w + 2 * pad, bh = h + 2 * pad;
		// (across: each source row into the wider one)
		var across = new haxe.ds.Vector<Float>(bw * h);
		for (y in 0...h)
			for (x in 0...bw) {
				var v = 0.0;
				for (i in 0...2 * pad + 1) {
					var sx = x - pad + i - pad;
					if (sx >= 0 && sx < w) v += weights[i] * src.get(y * w + sx);
				}
				across[y * bw + x] = v;
			}
		// (down: into the atlas, taller by pad each side)
		for (y in 0...bh)
			for (x in 0...bw) {
				var v = 0.0;
				for (i in 0...2 * pad + 1) {
					var sy = y - pad + i - pad;
					if (sy >= 0 && sy < h) v += weights[i] * across[sy * bw + x];
				}
				var c = Std.int(v + 0.5);
				pixels.set(offset + y * width + x, c > 255 ? 255 : c);
			}
	}

	function place(w:Int, h:Int):Null<{x:Int, y:Int}> {
		if (w + 1 > width || h + 1 > height) return null;
		for (s in shelves)
			if (h <= s.height && s.x + w + 1 <= width) {
				var p = {x: s.x, y: s.y};
				s.x += w + 1;
				return p;
			}
		var y = shelves.length == 0 ? 0 : shelves[shelves.length - 1].y + shelves[shelves.length - 1].height + 1;
		if (y + h > height) return null;
		var s = new Shelf(y, h);
		shelves.push(s);
		s.x = w + 1;
		return {x: 0, y: y};
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
		lastFace = null;
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

// an outline slanted: each point's x moved by k times its y (font units, y up)
private class Skewed implements Outline {
	final to:Outline;
	final k:Float;

	public function new(to:Outline, k:Float) {
		this.to = to;
		this.k = k;
	}

	public function moveTo(x:Float, y:Float)
		to.moveTo(x + k * y, y);

	public function lineTo(x:Float, y:Float)
		to.lineTo(x + k * y, y);

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float)
		to.quadTo(cx + k * cy, cy, x + k * y, y);

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float)
		to.cubicTo(c1x + k * c1y, c1y, c2x + k * c2y, c2y, x + k * y, y);

	public function close()
		to.close();
}
