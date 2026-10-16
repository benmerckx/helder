package hxmc.text;

import haxe.io.Bytes;

// Rasterized glyphs packed into one coverage bitmap (R8, width x height),
// for a GPU texture: each glyph of a face at a size and a quarter-pixel
// horizontal offset once, placed on shelves (rows as tall as their tallest
// glyph, a pixel apart). dirty is the region changed since the last
// upload (clean() after uploading it); when the bitmap is full it is
// cleared (generation counts the clears: the glyphs drawn before must be
// asked for again).
class GlyphAtlas {
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

	final glyphs = new Map<String, AtlasGlyph>();
	final shelves:Array<Shelf> = [];

	public function new(width = 1024, height = 1024) {
		this.width = width;
		this.height = height;
		pixels = Bytes.alloc(width * height);
		pixels.fill(0, pixels.length, 0);
	}

	// the glyph's bitmap in the atlas (rasterized now if needed): sub is the
	// quarter-pixel offset of its origin (0 to 3)
	public function get(font:FontFile, glyph:Int, size:Float, sub:Int):AtlasGlyph {
		var key = font.id + ":" + glyph + ":" + size + ":" + sub;
		var g = glyphs.get(key);
		if (g != null) return g;
		g = rasterize(font, glyph, size, sub);
		if (g == null) {
			// full: start again
			clear();
			g = rasterize(font, glyph, size, sub);
			if (g == null) g = new AtlasGlyph(0, 0, 0, 0, 0, 0);
		}
		glyphs.set(key, g);
		return g;
	}

	function rasterize(font:FontFile, glyph:Int, size:Float, sub:Int):Null<AtlasGlyph> {
		var scale = size / font.unitsPerEm, dx = sub / SUBPIXELS;
		var b = font.bounds(glyph);
		if (b[2] <= b[0] || b[3] <= b[1]) return new AtlasGlyph(0, 0, 0, 0, 0, 0);
		var x0 = Math.floor(b[0] * scale + dx), x1 = Math.ceil(b[2] * scale + dx);
		var y0 = Math.floor(-b[3] * scale), y1 = Math.ceil(-b[1] * scale);
		var w = x1 - x0 + 1, h = y1 - y0 + 1;
		var spot = place(w, h);
		if (spot == null) return null;
		var r = new Rasterizer(w, h);
		r.scaleX = scale;
		r.scaleY = -scale;
		r.offsetX = dx - x0;
		r.offsetY = -y0;
		font.outline(glyph, r);
		r.writeTo(pixels, spot.y * width + spot.x, width);
		touch(spot.x, spot.y, w, h);
		return new AtlasGlyph(spot.x, spot.y, w, h, x0, y0);
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
		glyphs.clear();
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
