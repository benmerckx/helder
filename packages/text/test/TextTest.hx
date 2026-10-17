import haxe.io.Bytes;
import hxmc.text.*;

// hxmc.text's tests, on Eval (make text-check; needs DejaVu Sans, as the
// Linux CI machines have, else the font-dependent checks are skipped):
//
//   <tool> -cp packages/text/src -cp packages/text/test -cp packages/gfx/test --run TextTest [--bless]
//
// - the rasterizer on shapes with known coverage (a half-covered square,
//   a triangle's area)
// - the bidi algorithm: levels and visual order of mixed text, numbers in
//   right-to-left text, mirrored brackets; Hebrew laid out, its caret and hits
// - Arabic: joining forms and the lam-alef ligature from GSUB, widths as
//   Chromium (HarfBuzz) measures them, the caret inside the ligature
// - DejaVu Sans: discovery, metrics, cmap, advances, kerning, outlines;
//   Inter: CFF outlines, GPOS kerning
// - layout: widths, wrapping, hard breaks, caret and hit
// - a sample of text rendered through the atlas against sample.png; with
//   Inter (CFF outlines), against sample-cff.png
//   (our own rasterizer: the same pixels on every machine with that font)
class TextTest {
	static var checks = 0;
	static var failed = 0;

	static function main() {
		var bless = Sys.args().contains("--bless");
		var here = "packages/text/test";
		rasterizer();
		bidi();
		var fonts = SystemFonts.get();
		var sans = fonts.match("DejaVu Sans");
		if (sans == null || sans.family != "DejaVu Sans") Sys.println("TextTest: no DejaVu Sans: font checks skipped (families: " + fonts.families().join(", ") + ")") else {
			font(sans, fonts);
			layout(sans, fonts);
			sample(sans, fonts, here + "/sample.png", bless);
		}
		// CFF outlines: Inter (fonts-inter), an OpenType font with cubic curves
		var inter = fonts.match("Inter");
		if (inter == null || inter.family != "Inter") Sys.println("TextTest: no Inter: CFF checks skipped") else {
			cff(inter);
			sample(inter, fonts, here + "/sample-cff.png", bless);
		}
		Sys.println('TextTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	// a string's visual order by the bidi algorithm (base: -1 from its first strong character)
	static function visual(s:String, base = -1):String {
		var cps = [for (c in new haxe.iterators.StringIteratorUnicode(s)) c];
		var r = Bidi.levels(cps, base);
		var order = Bidi.reorder(cps, r.levels, r.base, 0, cps.length);
		var b = new StringBuf();
		for (i in order)
			b.addChar(r.levels[i] & 1 == 1 ? Bidi.mirror(cps[i]) : cps[i]);
		return b.toString();
	}

	static function bidi() {
		var cps = [for (c in new haxe.iterators.StringIteratorUnicode("abc אבג def")) c];
		var r = Bidi.levels(cps, -1);
		check("bidi: levels of mixed text", r.base == 0 && r.levels.join("") == "00001110000", r.levels.join(""));
		check("bidi: visual order", visual("abc אבג def") == "abc גבא def", visual("abc אבג def"));
		check("bidi: a right-to-left paragraph, numbers left to right in it", visual("אבג 123 דהו") == "והד 123 גבא", visual("אבג 123 דהו"));
		check("bidi: mirrored brackets", visual("א(ב)") == "(ב)א", visual("א(ב)"));
		check("bidi: Arabic digits and letters", visual("مرحبا ١٢٣") == "١٢٣ ابحرم", visual("مرحبا ١٢٣"));
		check("bidi: left to right untouched", visual("plain (text) 12") == "plain (text) 12");
		check("bidi: a given base level", visual("abc", 1) == "abc" && visual("א b", 0) == "א b", visual("א b", 0));
		check("bidi: trailing spaces at the base level", visual("abc אבג  ") == "abc גבא  ", "[" + visual("abc אבג  ") + "]");
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
		// a cubic curve: a quarter circle's (control points at 0.5523 of the radius), its area pi r^2 / 4 with the corner's square
		var r = new Rasterizer(16, 16);
		r.moveTo(0, 0);
		r.lineTo(16, 0);
		r.cubicTo(16, 16 * 0.5523, 16 * 0.5523, 16, 0, 16);
		r.close();
		var b = Bytes.alloc(256);
		r.writeTo(b, 0, 16);
		var sum = 0.0;
		for (i in 0...256)
			sum += b.get(i) / 255;
		check("raster: a cubic curve's area (its chords within a fifth of a pixel)", Math.abs(sum - Math.PI * 64) < 3, '$sum');
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

	// an OpenType font with CFF outlines: Type 2 charstrings (subroutines,
	// hints skipped) into cubic curves
	static function cff(f:FontFile) {
		var h = f.glyph("H".code), o = new CountOutline();
		f.outline(h, o);
		check("cff: H, one contour of 12 sides", o.contours == 1 && o.segments == 11, '${o.contours} ${o.segments}');
		check("cff: H's bounds and advance", f.bounds(h).join(",") == "179,0,1342,1490" && f.advance(h) == 1522, f.bounds(h).join(",") + " " + f.advance(h));
		var o = new CountOutline();
		f.outline(f.glyph("o".code), o);
		check("cff: o, two contours", o.contours == 2 && o.cubics >= 8, '${o.contours} ${o.cubics}');
		// kerning in GPOS only (pair adjustments, by glyph classes)
		var av = f.kerning(f.glyph("A".code), f.glyph("V".code)), wa = f.kerning(f.glyph("W".code), f.glyph("a".code));
		check("cff: GPOS kerning (A V, W a)", av < 0 && wa < 0 && f.kerning(f.glyph("H".code), f.glyph("H".code)) == 0, '$av $wa');
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
		// Hebrew: placed right to left, the caret at each character's leading (right) edge
		var he = new TextLayout("שלום", set, 1.25, Math.NaN);
		var hw = he.width;
		check("bidi: Hebrew, its direction", he.direction == 1 && hw > 20, '${he.direction} $hw');
		check("bidi: its first character at the right", Math.abs(he.caret(0).x - hw) < 0.01 && he.caret(4).x == 0, '${he.caret(0).x} ${he.caret(4).x}');
		check("bidi: hits by direction", he.hit(-5, 5) == 4 && he.hit(hw + 5, 5) == 0 && he.hit(hw - 1, 5) == 0, '${he.hit(-5, 5)} ${he.hit(hw + 5, 5)} ${he.hit(hw - 1, 5)}');
		var mixed = new TextLayout("ab שלום cd", set, 1.25, Math.NaN);
		var order = [for (g in mixed.lines[0].glyphs) String.fromCharCode(g.cp)].join("");
		check("bidi: a mixed line in visual order", order == "ab םולש cd", order);
		// Arabic: joining forms and the lam-alef ligature from DejaVu Sans's GSUB; the widths at 100px are Chromium's
		// (HarfBuzz: measureText with the font "100px DejaVu Sans")
		var big = new FontSet(sans, fonts.fallbacks(), 100);
		for (c in [{s: "سلام", w: 205.37109375}, {s: "ببب", w: 156.201171875}, {s: "مرحبا", w: 231.201171875}, {s: "العربية", w: 273.291015625}, {s: "كتاب", w: 202.392578125}]) {
			var s = c.s, w = c.w;
			var t = new TextLayout(s, big, 1.25, Math.NaN);
			check("arabic: " + s + ", its width as Chromium's", Math.abs(t.width - w) < 0.01, '${t.width} $w');
		}
		var beh = new TextLayout("ببب", big, 1.25, Math.NaN).lines[0].glyphs, b1 = sans.glyph(0x628);
		check("arabic: initial, medial and final forms", beh.length == 3 && beh[0].id != b1 && beh[1].id != b1 && beh[2].id != b1
			&& beh[0].id != beh[1].id && beh[1].id != beh[2].id, [for (g in beh) g.id].join(","));
		var la = new TextLayout("لا", big, 1.25, Math.NaN);
		var lg = la.lines[0].glyphs;
		check("arabic: lam and alef, one glyph for two characters", lg.length == 1 && lg[0].length == 2 && Math.abs(la.width - 57.03125) < 0.01,
			'${lg.length} ${la.width}');
		check("arabic: the caret between lam and alef, at the ligature's middle", Math.abs(la.caret(1).x - la.width / 2) < 0.01 && la.hit(la.width * 0.5 + 1, 5) == 1
			&& la.hit(la.width - 2, 5) == 0 && la.hit(2, 5) == 2, '${la.caret(1).x} ${la.hit(la.width * 0.5 + 1, 5)}');
		// (the ligature glyph carries the lam)
		var mixedAr = new TextLayout("ab سلام", set, 1.25, Math.NaN);
		var arOrder = [for (g in mixedAr.lines[0].glyphs) String.fromCharCode(g.cp)].join("");
		check("arabic: a mixed line in visual order", arOrder == "ab ملس", arOrder);
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
		var mine = "bin/text-" + haxe.io.Path.withoutDirectory(golden);
		sys.io.File.saveBytes(mine, png);
		var g = Png.decode(sys.io.File.getBytes(golden));
		var diff = 0;
		for (i in 0...W * H)
			if (g.rgba.get(4 * i) != img.get(4 * i)) diff++;
		check("sample: the same pixels as " + haxe.io.Path.withoutDirectory(golden), g.width == W && diff == 0, '$diff pixels differ ($mine)');
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

	public var cubics = 0;

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float) {
		segments++;
		cubics++;
	}

	public function close() {}
}
