import haxe.io.Bytes;
import hxmc.text.*;

// hxmc.text's tests, on Eval (make text-check; needs DejaVu Sans, as the
// Linux CI machines have, else the font-dependent checks are skipped):
//
//   <tool> -cp packages/text/src -cp packages/text/test -cp packages/gfx/test --run TextTest [--bless]
//
// - the rasterizer on shapes with known coverage (a half-covered square,
//   a triangle's area)
// - DejaVu Sans: discovery, metrics, cmap, advances, kerning, outlines
// - layout: widths, wrapping, hard breaks, caret and hit
// - a sample of text rendered through the atlas against sample.png
//   (our own rasterizer: the same pixels on every machine with that font)
class TextTest {
	static var checks = 0;
	static var failed = 0;

	static function main() {
		var bless = Sys.args().contains("--bless");
		var here = "packages/text/test";
		rasterizer();
		var fonts = SystemFonts.get();
		var sans = fonts.match("DejaVu Sans");
		if (sans == null || sans.family != "DejaVu Sans") Sys.println("TextTest: no DejaVu Sans: font checks skipped (families: " + fonts.families().join(", ") + ")") else {
			font(sans, fonts);
			layout(sans, fonts);
			sample(sans, fonts, here + "/sample.png", bless);
		}
		Sys.println('TextTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('TextTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function rasterizer() {
		// a 4x4 square from (1, 1) to (3, 3), then one from x 0.5: half-covered edge columns
		var r = new Rasterizer(4, 4);
		square(r, 1, 1, 3, 3);
		var b = Bytes.alloc(16);
		r.writeTo(b, 0, 4);
		check("raster: a square", [for (i in 0...16) b.get(i)].join(",") == "0,0,0,0,0,255,255,0,0,255,255,0,0,0,0,0", [for (i in 0...16) b.get(i)].join(","));
		var r = new Rasterizer(4, 1);
		square(r, 0.5, 0, 2.5, 1);
		var b = Bytes.alloc(4);
		r.writeTo(b, 0, 4);
		check("raster: half pixels", [for (i in 0...4) b.get(i)].join(",") == "128,255,128,0", [for (i in 0...4) b.get(i)].join(","));
		// a right triangle over 8x8: its area is 32 pixels
		var r = new Rasterizer(8, 8);
		r.moveTo(0, 0);
		r.lineTo(8, 8);
		r.lineTo(0, 8);
		r.close();
		var b = Bytes.alloc(64);
		r.writeTo(b, 0, 8);
		var sum = 0.0;
		for (i in 0...64)
			sum += b.get(i) / 255;
		check("raster: a triangle's area", Math.abs(sum - 32) < 0.1, '$sum');
		// winding: a square drawn twice (overlap clamped), and the other way round
		var r = new Rasterizer(4, 4);
		square(r, 0, 0, 4, 4);
		square(r, 1, 1, 3, 3);
		var b = Bytes.alloc(16);
		r.writeTo(b, 0, 4);
		check("raster: overlap clamps", b.get(5) == 255 && b.get(0) == 255);
	}

	static function square(r:Rasterizer, x0:Float, y0:Float, x1:Float, y1:Float) {
		r.moveTo(x0, y0);
		r.lineTo(x1, y0);
		r.lineTo(x1, y1);
		r.lineTo(x0, y1);
		r.close();
	}

	static function font(f:FontFile, fonts:SystemFonts) {
		check("font: DejaVu Sans metrics", f.unitsPerEm == 2048 && f.ascender == 1901 && f.descender == -483 && f.weight == 400 && !f.italic,
			'${f.unitsPerEm} ${f.ascender} ${f.descender} ${f.weight}');
		var a = f.glyph("A".code);
		check("font: cmap", a != 0 && f.glyph(0x10FFFF) == 0 && f.glyph("é".code) != 0);
		check("font: advance", f.advance(a) == 1401, '${f.advance(a)}');
		var v = f.glyph("V".code);
		check("font: kerning A V", f.kerning(a, v) < 0, '${f.kerning(a, v)}');
		var bold = fonts.match("DejaVu Sans", 700);
		check("font: bold match", bold != null && bold.weight == 700, '$bold');
		var mono = fonts.match("monospace");
		check("font: monospace", mono != null && mono.advance(mono.glyph("i".code)) == mono.advance(mono.glyph("W".code)), '$mono');
		var count = 0;
		var o = new CountOutline();
		f.outline(f.glyph("O".code), o);
		check("font: outline of O", o.contours == 2 && o.segments > 8, '${o.contours} ${o.segments}');
		// a composite glyph (é: e and an accent)
		var o = new CountOutline();
		f.outline(f.glyph("é".code), o);
		check("font: composite é", o.contours >= 2, '${o.contours}');
	}

	static function layout(sans:FontFile, fonts:SystemFonts) {
		var set = new FontSet(sans, fonts.fallbacks(), 16);
		var t = new TextLayout("Hello world", set, 1.25, Math.NaN);
		check("layout: one line", t.lines.length == 1 && t.height == 20 && t.width > 80 && t.width < 100, '${t.width}');
		var w = t.width;
		var t2 = new TextLayout("Hello world", set, 1.25, w - 1);
		check("layout: wraps at the space", t2.lines.length == 2 && t2.lines[0].end == 6 && t2.lines[1].start == 6, [for (l in t2.lines) l.start + "-" + l.end].join(" "));
		var t3 = new TextLayout("one\ntwo\n", set, 1.25, Math.NaN);
		check("layout: hard breaks", t3.lines.length == 3 && t3.lines[1].start == 4 && t3.lines[2].start == 8, [for (l in t3.lines) l.start + "-" + l.end].join(" "));
		var t4 = new TextLayout("abcdefghijkl", set, 1.25, 30);
		check("layout: a long word is cut", t4.lines.length > 2 && t4.width <= 30, '${t4.lines.length} ${t4.width}');
		var c = t.caret(5);
		check("layout: caret", c.line == 0 && c.x > 30 && c.x < 50, '${c.x}');
		check("layout: hit", t.hit(c.x + 1, 5) == 5 && t.hit(-10, 5) == 0 && t.hit(1000, 5) == 11);
		var t5 = new TextLayout("日本語のテキスト", set, 1.25, 40);
		check("layout: CJK breaks anywhere", t5.lines.length >= 2, '${t5.lines.length}');
		var empty = new TextLayout("", set, 1.25, 100);
		check("layout: empty text is one line", empty.lines.length == 1 && empty.height == 20 && empty.width == 0);
	}

	// "The quick brown fox" and more at three sizes, drawn through the atlas
	static function sample(sans:FontFile, fonts:SystemFonts, golden:String, bless:Bool) {
		var W = 320, H = 180;
		var img = Bytes.alloc(W * H * 4);
		for (i in 0...W * H) {
			img.set(4 * i, 255);
			img.set(4 * i + 1, 255);
			img.set(4 * i + 2, 255);
			img.set(4 * i + 3, 255);
		}
		var atlas = new GlyphAtlas(512, 512);
		var y = 4.0;
		for (size in [11.0, 16.0, 28.0]) {
			var set = new FontSet(sans, fonts.fallbacks(), size);
			var t = new TextLayout("The quick brown fox jumps over the lazy dog. AV Wa é ß 0123", set, 1.2, W - 8);
			for (l in t.lines) {
				var by = Math.round(y + l.top + t.baseline);
				for (g in l.glyphs) {
					var gx = 4 + g.x, ix = Math.floor(gx), sub = Std.int((gx - ix) * GlyphAtlas.SUBPIXELS);
					var a = atlas.get(g.font, g.id, size, sub);
					for (py in 0...a.h)
						for (px in 0...a.w) {
							var X = ix + a.left + px, Y = by + a.top + py;
							if (X < 0 || Y < 0 || X >= W || Y >= H) continue;
							var cov = atlas.pixels.get((a.y + py) * atlas.width + a.x + px);
							var o = 4 * (Y * W + X);
							var v = Std.int(img.get(o) * (255 - cov) / 255);
							img.set(o, v);
							img.set(o + 1, v);
							img.set(o + 2, v);
						}
				}
			}
			y += t.height;
		}
		check("sample: fits", y < H, '$y');
		var png = Png.encode(img, W, H);
		if (bless) {
			sys.io.File.saveBytes(golden, png);
			Sys.println("TextTest: blessed " + golden);
			return;
		}
		sys.io.File.saveBytes("bin/text-sample.png", png);
		var g = Png.decode(sys.io.File.getBytes(golden));
		var diff = 0;
		for (i in 0...W * H)
			if (g.rgba.get(4 * i) != img.get(4 * i)) diff++;
		check("sample: the same pixels as sample.png", g.width == W && diff == 0, '$diff pixels differ (bin/text-sample.png)');
	}
}

class CountOutline implements Outline {
	public var contours = 0;
	public var segments = 0;

	public function new() {}

	public function moveTo(x:Float, y:Float)
		contours++;

	public function lineTo(x:Float, y:Float)
		segments++;

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float)
		segments++;

	public function close() {}
}
