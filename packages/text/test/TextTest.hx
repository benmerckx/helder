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
// - marks: GPOS anchors and canonical compositions, the ink against
//   Chromium's; fallback faces looked up lazily
// - DejaVu Sans: discovery, metrics, cmap, advances, kerning, outlines;
//   Inter: CFF outlines, GPOS kerning
// - variations: a variable font's instances (var.ttf) against Chromium
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
		graphemes();
		variations(here);
		var fonts = SystemFonts.get();
		var sans = fonts.match("DejaVu Sans");
		if (sans == null || sans.family != "DejaVu Sans") Sys.println("TextTest: no DejaVu Sans: font checks skipped (families: " + fonts.families().join(", ") + ")") else {
			font(sans, fonts);
			layout(sans, fonts);
			decorations(sans, fonts);
			spacing(sans);
			ligatures(sans, fonts);
			justified(sans);
			tabs(sans);
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

	// text decorations' lines where Chromium draws them (rows of a
	// screenshot: "Hamburg", line-height 1.5, underline, line-through, overline:
	// top and thickness), DejaVu Sans at 20 and 13, DejaVu Serif at 31; at
	// scale 2, twice as fine
	static function decorations(sans:FontFile, fonts:SystemFonts) {
		var serif = fonts.match("DejaVu Serif");
		var cases:Array<{face:FontFile, size:Float, rows:Array<Int>}> = [{face: sans, size: 20, rows: [23, 2, 15, 2, 1, 2]}, {face: sans, size: 13, rows: [15, 1, 9, 1, 1, 1]}];
		if (serif != null && serif.family == "DejaVu Serif") cases.push({face: serif, size: 31, rows: [36, 3, 23, 3, 2, 3]});
		for (c in cases) {
			var l = new TextLayout("Hamburg", new FontSet(c.face, [], c.size), 1.5, Math.NaN), got = [];
			for (k in 0...3) {
				var d = l.decoration(0, 7, k)[0];
				got.push(d.y);
				got.push(d.height);
			}
			check("decorations: " + c.face.family + " " + c.size + " as Chromium draws them", got.join(",") == c.rows.join(",") && l.decoration(0, 7, 0)[0].width == l.width, got.join(","));
		}
		var l = new TextLayout("Hamburg x ", new FontSet(sans, [], 20), 1.5, Math.NaN);
		var u = l.decoration(0, 10, 0, 2)[0];
		check("decorations: snapped to the pixels of the scale; not under trailing spaces", u.height == 2 && u.y * 2 == Math.round(u.y * 2) && u.width == l.lines[0].width
			&& l.lines[0].advance > l.lines[0].width, '$u');
	}

	// letter and word spacing: widths as Chromium measures them (DejaVu Sans
	// at 20, white-space: pre)
	static function spacing(sans:FontFile) {
		var set = new FontSet(sans, [], 20);
		function w(t:String, ls:Float, ws:Float):Float
			return new TextLayout(t, set, 1.2, Math.NaN, null, 0, ls, ws).width;
		var got = [w("Hamburg", 0, 0), w("Hamburg", 2, 0), w("Hamburg", -1.5, 0), w("a b  c", 0, 0), w("a b  c", 0, 5), w("a b  c", 3, 5)];
		var chromium = [92.71875, 106.71875, 82.21875, 55.03125, 70.03125, 88.03125];
		var ok = true;
		for (i in 0...got.length)
			if (Math.abs(got[i] - chromium[i]) > 0.02) ok = false;
		check("spacing: letter and word spacing as Chromium adds them", ok, got.join(" "));
		// (a run's own: only its characters)
		var run = new TextRun(0, 3, set, 1.2, 4, 0);
		check("spacing: a run's", Math.abs(new TextLayout("Hamburg", set, 1.2, Math.NaN, [run]).width - (92.71875 + 12)) < 0.02);
	}

	// the standard ligatures: widths as Chromium measures them (DejaVu Sans
	// and Serif at 100: ff, ffi, ffl, fi, fl ligatures), none with letter
	// spacing; carets and hits inside one by its characters' equal parts
	static function ligatures(sans:FontFile, fonts:SystemFonts) {
		function w(face:FontFile, t:String, ls = 0.0):Float
			return new TextLayout(t, new FontSet(face, [], 100), 1.2, Math.NaN, null, 0, ls).width;
		var got = [w(sans, "ff"), w(sans, "ffi"), w(sans, "ffl"), w(sans, "office"), w(sans, "Affine fluffy")];
		var chromium = [68.896484375, 96.6796875, 96.6796875, 274.365234375, 576.234375];
		var serif = fonts.match("DejaVu Serif");
		if (serif != null && serif.family == "DejaVu Serif") {
			got = got.concat([w(serif, "fi"), w(serif, "ffi"), w(serif, "office"), w(serif, "file"), w(serif, "office", 2)]);
			chromium = chromium.concat([66.69921875, 103.02734375, 278.41796875, 157.861328125, 293.40625]);
		}
		var ok = true;
		for (i in 0...got.length)
			if (Math.abs(got[i] - chromium[i]) > 0.02) ok = false;
		check("ligatures: widths as Chromium's (none with letter spacing)", ok, got.join(" "));
		var l = new TextLayout("office", new FontSet(sans, [], 100), 1.2, Math.NaN);
		var glyphs = l.lines[0].glyphs;
		var o = l.caret(1).x, third = 96.6796875 / 3;
		check("ligatures: one glyph for ffi, its carets by thirds", glyphs.length == 4 && Math.abs(l.caret(2).x - (o + third)) < 0.01
			&& Math.abs(l.caret(3).x - (o + 2 * third)) < 0.01 && Math.abs(l.caret(4).x - (o + 3 * third)) < 0.01, [for (k in 0...7) l.caret(k).x].join(" "));
		check("ligatures: hit by thirds", l.hit(o + third * 0.4, 50) == 1 && l.hit(o + third * 0.6, 50) == 2 && l.hit(o + third * 1.6, 50) == 3,
			l.hit(o + third * 0.4, 50) + " " + l.hit(o + third * 0.6, 50) + " " + l.hit(o + third * 1.6, 50));
	}

	// text-align: justify: each word where Chromium puts it (DejaVu Sans at
	// 16 in 200 pixels, white-space: pre-wrap; the line before a hard break
	// and the last not justified)
	static function justified(sans:FontFile) {
		var text = "The quick brown fox jumps over the lazy dog and keeps running far away.\nShort line.";
		var l = new TextLayout(text, new FontSet(sans, [], 16), 1.25, 200);
		l.justify(200);
		var chromium = [0, 47.625, 108.313, 175.594, 0, 55.453, 97.922, 130.969, 169.891, 0, 43.188, 103.141, 177.969, 0, 0, 48.016];
		var got = [];
		var re = ~/\S+/;
		var rest = text, offset = 0;
		while (re.match(rest)) {
			var at = offset + re.matchedPos().pos;
			var x = Math.NaN;
			for (line in l.lines)
				for (g in line.glyphs)
					if (g.cluster == at) x = g.x;
			got.push(Math.round(x * 1000) / 1000);
			offset = at + re.matched(0).length;
			rest = text.substr(offset);
		}
		var ok = got.length == chromium.length;
		for (k in 0...got.length)
			if (ok && Math.abs(got[k] - chromium[k]) > 0.02) ok = false;
		check("justify: the words where Chromium puts them", ok, got.join(" "));
	}

	// tabs: to their stops, every 8 spaces from the line's start, the next
	// but one when nearer than half a space: each character where Chromium
	// puts it (DejaVu Sans at 16, white-space: pre)
	static function tabs(sans:FontFile) {
		var cases:Array<{text:String, chromium:Array<Float>}> = [
			{text: "a\tb", chromium: [0, 9.813, 40.688]},
			{text: "abcdefgh\tb", chromium: [0, 9.797, 19.953, 28.75, 38.906, 48.75, 54.391, 64.547, 74.688, 81.375]},
			{text: "\t\tx", chromium: [0, 40.688, 81.375]},
			{text: "ab\tcd\tef", chromium: [0, 9.797, 19.969, 40.688, 49.484, 59.641, 81.375, 91.219]}
		];
		var bad = [];
		for (c in cases) {
			var l = new TextLayout(c.text, new FontSet(sans, [], 16), 1.25, Math.NaN);
			var xs = [for (g in l.lines[0].glyphs) g.x];
			var ok = xs.length == c.chromium.length;
			for (k in 0...xs.length)
				if (ok && Math.abs(xs[k] - c.chromium[k]) > 0.02) ok = false;
			if (!ok) bad.push(c.text + ": " + xs.join(" "));
		}
		check("tabs: to their stops, as Chromium puts them", bad.length == 0, bad.join("; "));
	}

	// grapheme clusters: their boundaries as Intl.Segmenter finds them (node), forward and back
	static function graphemes() {
		graphemeCase("a letter and its mark", "e\u0301x", "2,3", "2,3");
		graphemeCase("two marks", "a\u0323\u0302b", "3,4", "3,4");
		graphemeCase("an emoji modifier", "\u{1f44d}\u{1f3fd}!", "4,5", "2,3");
		graphemeCase("a family (zero width joiners)", "\u{1f468}\u200d\u{1f469}\u200d\u{1f467}x", "8,9", "5,6");
		graphemeCase("flags", "\u{1f1e7}\u{1f1ea}\u{1f1eb}\u{1f1f7}\u{1f1e9}", "4,8,10", "2,4,5");
		graphemeCase("a keycap", "1\ufe0f\u20e3a", "3,4", "3,4");
		graphemeCase("Hangul jamo", "\u1100\u1161\u11a8\uac00", "3,4", "3,4");
		graphemeCase("CR LF", "a\r\nb", "1,3,4", "1,3,4");
		graphemeCase("Hebrew points", "\u05e9\u05b8\u05c1\u05dc\u05d5\u05b9\u05dd", "3,4,6,7", "3,4,6,7");
		graphemeCase("an emoji", "x\u{1f600}y", "1,3,4", "1,2,3");
		graphemeCase("a variation selector", "\u2764\ufe0fz", "2,3", "2,3");
	}

	// (expected: in UTF-16 units; in code points where strings count those, as on Eval)
	static function graphemeCase(what:String, s:String, utf16:String, codePoints:String) {
		var expected = "\u{1F600}".length == 2 ? utf16 : codePoints;
		var fwd = [], i = 0;
		while (i < s.length) {
			i = Grapheme.next(s, i);
			fwd.push(i);
		}
		var back = [], j = s.length;
		while (j > 0) {
			back.unshift(j);
			j = Grapheme.prev(s, j);
		}
		check("graphemes: " + what, fwd.join(",") == expected && back.join(",") == expected, fwd.join(",") + " / " + back.join(","));
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

	// a variable font (var.ttf, from var-font.mjs): instances by wght, gvar's
	// deltas (every point, named points and inferred ones, a composite's
	// offsets, an intermediate region) and avar's mapping, against Chromium's
	// advances (within 0.05 units: implementations round the normalized
	// coordinates in their own steps) and ink bounds (rounded out to 1/64 em)
	static function variations(here:String) {
		var path = here + "/var.ttf";
		if (!sys.FileSystem.exists(path)) return;
		var f = FontFile.parse(sys.io.File.getBytes(path));
		check("variations: the axes", f.axes.length == 1 && f.axes[0].tag == "wght" && f.axes[0].min == 100 && f.axes[0].def == 400 && f.axes[0].max == 900,
			[for (a in f.axes) a.tag + " " + a.min + " " + a.def + " " + a.max].join(";"));
		var expected:Array<{ch:String, weight:Int, advance:Float, left:Float, right:Float, top:Float}> = haxe.Json.parse(sys.io.File.getContent(here
			+ "/var-expected.json"));
		var bad = [], step = 1000 / 64;
		for (e in expected) {
			var v = f.instance(["wght" => e.weight]), g = v.glyph(e.ch.charCodeAt(0));
			var a = v.advance(g), b = v.bounds(g);
			inline function near(ours:Float, theirs:Float, out:Bool)
				return out ? theirs >= ours - 0.01 && theirs < ours + step : theirs <= ours + 0.01 && theirs > ours - step;
			if (Math.abs(a - e.advance) > 0.05 || !near(b[0], e.left, false) || !near(b[2], e.right, true) || !near(b[3], e.top, true))
				bad.push(e.ch + "@" + e.weight + ": " + a + " [" + b.join(",") + "] vs " + e.advance + " [" + e.left + ",," + e.right + "," + e.top + "]");
		}
		check("variations: advances and bounds as Chromium's (" + expected.length + ")", bad.length == 0, bad.join("; "));
		// as SystemFonts gives it: the instance at the weight asked for, within its range
		var found = new SystemFonts();
		found.add(sys.io.File.getBytes(path));
		var bold = found.match("VarTest", 700), thin = found.match("VarTest", 50);
		check("variations: SystemFonts' instance by weight", bold != null && bold.weight == 700 && bold.advance(bold.glyph("A".code)) > 619 && thin != null && thin.weight == 100
			&& thin.advance(thin.glyph("A".code)) == 400 && found.match("VarTest", 700) == bold, bold == null ? "none" : bold.weight + " " + bold.advance(bold.glyph("A".code)));
		check("variations: an instance is a face of its own", f.instance(["wght" => 700]).id != f.id && f.instance(["wght" => 700]).weight == 700);
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
		var asked = [];
		var lazy = new FontSet(sans, [], 16, cp -> {
			asked.push(cp);
			cp == 0x304B ? sans : null;
		});
		check("layout: more fallbacks asked for what the faces lack", lazy.faceFor(0x304B) == sans && lazy.faceFor("a".code) == sans && asked.join(",") == "12363",
			asked.join(","));
		// Hebrew: placed right to left, the caret at each character's leading (right) edge
		var he = new TextLayout("שלום", set, 1.25, Math.NaN);
		var hw = he.width;
		check("bidi: Hebrew, its direction", he.direction == 1 && hw > 20, '${he.direction} $hw');
		check("bidi: its first character at the right", Math.abs(he.caret(0).x - hw) < 0.01 && he.caret(4).x == 0, '${he.caret(0).x} ${he.caret(4).x}');
		check("bidi: hits by direction", he.hit(-5, 5) == 4 && he.hit(hw + 5, 5) == 0 && he.hit(hw - 1, 5) == 0, '${he.hit(-5, 5)} ${he.hit(hw + 5, 5)} ${he.hit(hw - 1, 5)}');
		var mixed = new TextLayout("ab שלום cd", set, 1.25, Math.NaN);
		var order = [for (g in mixed.lines[0].glyphs) String.fromCharCode(g.cp)].join("");
		check("bidi: a mixed line in visual order", order == "ab םולש cd", order);
		// a base direction given (CSS's direction): its neutrals placed by it
		var rtl = new TextLayout("Hello!", set, 1.25, Math.NaN, null, 0, 0, 0, 1);
		var shown = [for (g in rtl.lines[0].glyphs) String.fromCharCode(g.cp)].join("");
		check("bidi: a right-to-left base, a left-to-right word", rtl.direction == 1 && shown == "!Hello", shown);
		var ltr = new TextLayout("שלום!", set, 1.25, Math.NaN, null, 0, 0, 0, 0);
		check("bidi: a left-to-right base, a right-to-left word", ltr.direction == 0 && String.fromCharCode(ltr.lines[0].glyphs[ltr.lines[0].glyphs.length - 1].cp) == "!");
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
		// marks: GPOS's anchors (mark, mkmk), compositions the face has; the ink's
		// left, right, ascent and descent at 100px against Chromium's measureText
		for (c in [
			{s: "x́", ink: [-2.0, 56, 80, 0.0]},
			{s: "q̣́", ink: [-5, 55, 80, 39.947265625]},
			{s: "Ж́", ink: [-1, 106, 98.212890625, 0.0]},
			{s: "بَ", ink: [-6, 87, 61.234375, 18.0]},
			{s: "مُحَمَّد", ink: [-6, 220.853515625, 83.91015625, 3.0]},
			{s: "لاَ", ink: [7.67578125, 47, 85.6484375, 1.0]},
			{s: "בָּ", ink: [-4, 54, 55, 20.0]},
			{s: "שָׁ", ink: [-4, 72, 70, 20.0]},
			{s: "ố", ink: [-5, 61, 85, 2.0]},
			{s: "ậ", ink: [-6, 53, 80, 19.0]}
		]) {
			var t = new TextLayout(c.s, big, 1.25, Math.NaN);
			var x0 = 1e9, x1 = -1e9, top = -1e9, bottom = 1e9;
			for (g in t.lines[0].glyphs) {
				var b = g.font.bounds(g.id), k = big.scale(g.font);
				if (b[2] <= b[0]) continue;
				x0 = Math.min(x0, g.x + g.dx + b[0] * k);
				x1 = Math.max(x1, g.x + g.dx + b[2] * k);
				top = Math.max(top, b[3] * k - g.dy);
				bottom = Math.min(bottom, b[1] * k - g.dy);
			}
			var ours = [-x0, x1, top, -bottom];
			var ok = true;
			for (i in 0...4)
				if (Math.abs(ours[i] - c.ink[i]) > 1.2) ok = false;
			check("marks: " + c.s + ", its ink as Chromium's", ok, [for (v in ours) Math.round(v * 10) / 10].join(" ") + " / " + c.ink.join(" "));
		}
		var xm = new TextLayout("x\u0301y", big, 1.25, Math.NaN), xw = xm.lines[0].glyphs[0].advance;
		check("marks: a hit is not between a letter and its mark", xm.hit(xw * 0.4, 5) == 0 && xm.hit(xw * 0.6, 5) == 2 && xm.hit(xw * 1.1, 5) == 2,
			'${xm.hit(xw * 0.6, 5)}');
		var composed = new TextLayout("é", big, 1.25, Math.NaN).lines[0].glyphs;
		check("marks: e and an acute as é", composed.length == 1 && composed[0].id == sans.glyph(0xE9) && composed[0].length == 2, '${composed.length}');
		// selections: one run on a line of one direction, two across a direction change
		var plain = new TextLayout("Hello world", set, 1.25, Math.NaN);
		var ps = plain.selection(2, 8);
		check("selection: one run", ps.length == 1 && Math.abs(ps[0].x - plain.caret(2).x) < 1e-6 && Math.abs(ps[0].x + ps[0].width - plain.caret(8).x) < 1e-6,
			[for (r in ps) r.x + "+" + r.width].join(" "));
		var mixedSel = new TextLayout("ab שלום cd", set, 1.25, Math.NaN);
		var ms = mixedSel.selection(1, 5);
		var hebrewAt = [for (g in mixedSel.lines[0].glyphs) if (g.cluster == 3) g][0];
		check("selection: across a direction change, two runs", ms.length == 2 && ms[0].x < ms[1].x && Math.abs(ms[1].x + ms[1].width - (hebrewAt.x + hebrewAt.advance)) < 1e-6,
			[for (r in ms) Math.round(r.x) + "+" + Math.round(r.width)].join(" "));
		var lamAlef = new TextLayout("لا", big, 1.25, Math.NaN);
		var half = lamAlef.selection(0, 1);
		check("selection: half a ligature, from its right", half.length == 1 && Math.abs(half[0].x - lamAlef.width / 2) < 0.01 && Math.abs(half[0].width - lamAlef.width / 2) < 0.01,
			[for (r in half) r.x + "+" + r.width].join(" "));
		// colour emoji (Noto Color Emoji, where it is): widths as Chromium measures them at 100px
		var emojiSet = new FontSet(sans, fonts.fallbacks(), 100, fonts.fallbackFor, fonts.emojiFor);
		if (fonts.emojiFor(0x1F44D) != null && fonts.emojiFor(0x1F44D).family == "Noto Color Emoji") {
			for (c in [
				{s: "\u{1F600}", w: 104.248046875, what: "an emoji the face has: its own glyph"},
				{s: "\u2764\uFE0F", w: 124.7706298828125, what: "VS16: the colour face"},
				{s: "\u{1F44D}\u{1F3FD}", w: 124.7706298828125, what: "a skin tone: one glyph"},
				{s: "\u{1F1E7}\u{1F1EA}", w: 124.7706298828125, what: "a flag"},
				{s: "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}", w: 124.7706298828125, what: "a family joined"},
				{s: "1\uFE0F\u20E3", w: 124.7706298828125, what: "a keycap"},
				{s: "\u{1F3F3}\uFE0F\u200D\u{1F308}", w: 124.7706298828125, what: "VS16 inside a sequence"},
				{s: "\u263A\uFE0Fx", w: 183.9503173828125, what: "then text"}
			]) {
				var t = new TextLayout(c.s, emojiSet, 1.25, Math.NaN);
				check("emoji: " + c.what, Math.abs(t.width - c.w) < 0.01, '${t.width} ${c.w}');
			}
		} else Sys.println("TextTest: no Noto Color Emoji: emoji checks skipped");
		// runs in other fonts: widths and line boxes as Chromium lays out spans (16px DejaVu Sans, line height 1.25)
		var bold = fonts.match("DejaVu Sans", 700), fb = fonts.fallbacks();
		var at = (size:Float) -> new FontSet(sans, fb, size);
		for (c in [
			{s: "Hello bold world", runs: [new TextRun(6, 10, new FontSet(bold, fb, 16), 1.25)], max: Math.NaN, w: 134.171875, h: 20.0, what: "a bold run"},
			{s: "small BIG small", runs: [new TextRun(6, 9, at(32), 1.25)], max: Math.NaN, w: 151.59375, h: 40.0, what: "a larger run: its line box"},
			{s: "tiny tiny tiny", runs: [new TextRun(5, 9, at(10), 1.25)], max: Math.NaN, w: 89.8125, h: 20.0, what: "a smaller run: the paragraph's strut"},
			{s: "a tall b", runs: [new TextRun(2, 6, at(24), 2)], max: Math.NaN, w: 67.59375, h: 48.0, what: "a run's own line height"},
			{s: "one two three four five six seven eight", runs: [new TextRun(14, 18, at(32), 1.25)], max: 150.0, w: Math.NaN, h: 80.0, what: "wrapped: each line its own height"}
		]) {
			var t = new TextLayout(c.s, set, 1.25, c.max, c.runs);
			check("runs: " + c.what, (Math.isNaN(c.w) || Math.abs(t.width - c.w) < 0.05) && t.height == c.h, '${t.width} ${t.height}');
		}
		// maxLines: the lines cut, the last ending in an ellipsis where Chromium's line-clamp puts it (its ink's right edge)
		for (c in [
			{s: "The quick brown fox jumps over the lazy dog and keeps on running far away", w: 200.0, n: 2, right: 197.0},
			{s: "Supercalifragilisticexpialidocious word", w: 120.0, n: 1, right: 110.0},
			{s: "short line here and then a second one that is long", w: 150.0, n: 1, right: 131.0},
			{s: "a b c d e f g h i j k l m n o p q r s t u v w x y z", w: 100.0, n: 3, right: 96.0},
			{s: "one two three four five six seven", w: 90.0, n: 2, right: 87.0},
			{s: "aaaa bbbbbbbbbbbbbbbbbbb ccc", w: 80.0, n: 1, right: 54.0}
		]) {
			var t = new TextLayout(c.s, set, 1.25, c.w, null, c.n);
			var l = t.lines[t.lines.length - 1], e = l.glyphs[l.glyphs.length - 1];
			var r = e.x + e.font.bounds(e.id)[2] * set.scale(e.font);
			check("maxLines: " + c.s.substr(0, 16) + ", " + c.n + " lines", t.truncated && t.lines.length == c.n && t.height == 20 * c.n && e.cp == 0x2026 && Math.abs(r - c.right) < 1,
				'${t.lines.length} ${t.height} $r');
		}
		check("maxLines: not cut when it fits", !new TextLayout("short", set, 1.25, 200, null, 1).truncated);
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
				var by = Math.round(y + l.top + l.baseline);
				for (g in l.glyphs) {
					if (g.hidden) continue;
					var gx = 4 + g.x + g.dx, ix = Math.floor(gx), sub = Std.int((gx - ix) * GlyphAtlas.SUBPIXELS);
					var a = atlas.get(g.font, g.id, size, sub);
					for (py in 0...a.h)
						for (px in 0...a.w) {
							var X = ix + a.left + px, Y = by + Math.round(g.dy) + a.top + py;
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
