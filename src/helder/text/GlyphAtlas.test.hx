package helder.text;

import haxe.io.Bytes;
import helder.test.Test;

// The atlas in frames: one full in the middle of a frame gives no glyph
// rather than clearing the glyphs the frame drew (the studio's text garbled
// while zooming: the bitmap cleared and drawn over under them); the next
// frame's begin repacks the last frame's glyphs, grows the bitmap to its
// max, evicts the others; a glyph too large for it drawn alone.
function tests() {
	describe("GlyphAtlas", () -> {
		var font = FontFile.parse(sys.io.File.getBytes("apps/studio/fonts/HankenGrotesk-Regular.ttf"));
		var letters = [for (c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("")) font.glyph(c.charCodeAt(0))];
		function pixels(a:GlyphAtlas, g:GlyphAtlas.AtlasGlyph):Bytes {
			var b = Bytes.alloc(g.w * g.h);
			for (y in 0...g.h)
				b.blit(y * g.w, a.pixels, (g.y + y) * a.width + g.x, g.w);
			return b;
		}
		// (letters at size until one does not fit: those that did)
		function fill(a:GlyphAtlas, size:Float):Array<GlyphAtlas.AtlasGlyph> {
			var got = [];
			for (id in letters) {
				var g = a.get(font, id, size, 0);
				if (g == null) break;
				got.push(g);
			}
			return got;
		}
		test("full in a frame: the frame's glyphs stay as drawn", () -> {
			var a = new GlyphAtlas(64, 64);
			a.begin();
			var h = require(a.get(font, font.glyph("H".code), 20, 0));
			var before = pixels(a, h), x = h.x, y = h.y;
			var got = fill(a, 40);
			assert(a.full, "full");
			assert(got.length < letters.length, "a glyph left out");
			equals(a.get(font, letters[letters.length - 1], 40, 0), null);
			equals(a.generation, 0);
			equals(h.x, x);
			equals(h.y, y);
			equals(pixels(a, h).toHex(), before.toHex());
		});
		test("the next frame: the last frame's glyphs repacked, the rest evicted", () -> {
			var a = new GlyphAtlas(64, 64);
			a.begin();
			fill(a, 40);
			a.begin();
			// (one drawn in the last frame alone)
			var h = require(a.get(font, font.glyph("H".code), 20, 0));
			var before = pixels(a, h);
			fill(a, 40);
			a.begin();
			equals(a.generation, 2);
			assert(!a.full, "room");
			equals(a.get(font, font.glyph("H".code), 20, 0), h);
			equals(pixels(a, h).toHex(), before.toHex());
			equals(a.dirtyX1, 64);
		});
		test("grown to its max where the last frame's glyphs need it", () -> {
			var a = new GlyphAtlas(64, 64, 512);
			for (i in 0...4) {
				a.begin();
				fill(a, 40);
			}
			assert(a.width > 64 || a.height > 64, "grown");
			assert(a.width <= 512 && a.height <= 512, "to its max");
			equals(fill(a, 40).length, letters.length);
			assert(!a.full, "every letter fits");
		});
		test("a glyph drawn alone", () -> {
			var a = new GlyphAtlas(64, 64);
			var b = require(a.bitmap(font, font.glyph("H".code), 300, 0));
			assert(b.width > 150 && b.height > 200, "its size");
			assert(b.top < -200, "above the baseline");
			var ink = 0;
			for (i in 0...b.width * b.height)
				if (b.pixels.get(i) > 128) ink++;
			assert(ink > b.width * b.height / 4, "its ink");
			equals(a.dirtyX1, 0);
		});
	});
}
