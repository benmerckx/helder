package helder.text.linux;

import helder.test.Test;
import helder.text.Shaping;

// The platform's stack on Linux (natively; skipped without fontconfig or
// HarfBuzz): fontconfig's fallback finding a face for each script's text,
// then TextLayout's glyphs against HarfBuzz's on it (in visual order), with
// the platform's engine: Latin, Hebrew, Arabic, CJK and Thai shaped by
// helder's own engine, Devanagari, Bengali, Tamil (reordering, conjuncts,
// split vowels) by HarfBuzz through TextLayout; with helder's engine chosen
// (Shaping.HELDER, the tests' default) Devanagari stays its own.
function tests() {
	describe("HarfBuzz and fontconfig (Linux)", () -> {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		var native = hxmc.unsafe.Mem.os() == 0 && hxmc.unsafe.Mem.target() < 9 && HarfBuzz.available() && Fontconfig.available();
		function layout(text:String, f:FontFile, engine:Int):TextLayout {
			var was = Shaping.engine;
			Shaping.engine = engine;
			var l = new TextLayout(text, new FontSet(f, [], 16), 1.2, Math.NaN);
			Shaping.engine = was;
			return l;
		}
		function face(text:String):Null<FontFile> {
			var cp = 0;
			for (u in new haxe.iterators.StringIteratorUnicode(text))
				if (u > 0x7F && cp == 0) cp = u;
			var m = Fontconfig.fileFor(cp == 0 ? "S".code : cp);
			if (m == null) return null;
			var f = FontFile.parse(sys.io.File.getBytes(m.path), m.index);
			f.path = m.path;
			return f;
		}
		for (c in [
			{name: "Latin", text: "Shaping wave"},
			{name: "Hebrew", text: "שלום עולם"},
			{name: "Arabic", text: "مرحبا بالعالم"},
			{name: "CJK", text: "日本語の文字"},
			{name: "Thai", text: "สวัสดีครับ"},
			{name: "Devanagari", text: "हिन्दी"},
			{name: "Bengali", text: "বাংলা ভাষা কোথায়"},
			{name: "Tamil", text: "தமிழ் கொண்டு"}
		])
			test('${c.name}: fontconfig\'s face, TextLayout\'s glyphs as HarfBuzz\'s', () -> {
				if (!native) return;
				var f = face(c.text);
				if (f == null) {
					Sys.println('  (${c.name}: no font on this system)');
					return;
				}
				var l = layout(c.text, f, Shaping.SYSTEM);
				// (right to left: the whole text, in visual order; left to right each word and space
				// shaped alone, as TextLayout shapes a complex script's runs)
				var rtl = helder.text.Bidi.hasRtl([for (u in new haxe.iterators.StringIteratorUnicode(c.text)) u]), hb = [];
				if (rtl) for (g in HarfBuzz.shape(f, c.text, true)) hb.push(g.id) else for (w in c.text.split(" ").join("\u0000 \u0000").split("\u0000"))
					if (w != "") for (g in HarfBuzz.shape(f, w)) hb.push(g.id);
				var mine = [for (i in 0...l.glyphCount) l.glyphId(i)];
				equals(mine, hb, '${c.name} in ${f.path}');
			});
		test("helder's own engine chosen: Devanagari not reordered (the deterministic engine stays)", () -> {
			if (!native) return;
			var f = face("हिन्दी");
			if (f == null) return;
			var own = layout("हिन्दी", f, Shaping.HELDER), sys = layout("हिन्दी", f, Shaping.SYSTEM);
			// (ि, the vowel sign before its consonant: HarfBuzz's first glyph, helder's second)
			assert(own.glyphId(0) != sys.glyphId(0), "different first glyphs");
			f.engine = Shaping.HELDER;
			var perFont = layout("हिन्दी", f, Shaping.SYSTEM);
			equals([for (i in 0...perFont.glyphCount) perFont.glyphId(i)], [for (i in 0...own.glyphCount) own.glyphId(i)], "the font's own choice");
		});
		test("the shaped clusters: carets and lines by characters", () -> {
			if (!native) return;
			var f = face("हिन्दी");
			if (f == null) return;
			var text = "हिन्दी हिन्दी हिन्दी";
			var l = layout(text, f, Shaping.SYSTEM);
			var one = layout("हिन्दी", f, Shaping.SYSTEM);
			// (each glyph's characters within the text, in order; the caret at the text's end its width)
			for (i in 0...l.glyphCount)
				assert(l.glyphCluster(i) >= 0 && l.glyphCluster(i) + l.glyphLength(i) <= text.length, "within the text");
			assert(Math.abs(l.caret(text.length).x - l.width) < 1e-6, "the caret at the end");
			// (broken at the spaces: three lines of one word)
			var was = Shaping.engine;
			Shaping.engine = Shaping.SYSTEM;
			var wrapped = new TextLayout(text, new FontSet(f, [], 16), 1.2, one.width + 1);
			Shaping.engine = was;
			equals(wrapped.lines.length, 3, "a word a line");
		});
		test("SystemFonts' fallback through fontconfig: a character none of its lists has", () -> {
			if (!native) return;
			// (a CJK ideograph: MORE's names may be missing, fontconfig finds what the system has)
			var m = Fontconfig.fileFor(0x65E5);
			if (m == null) return;
			var f = SystemFonts.get().fallbackFor(0x65E5);
			assert(f != null && f.glyph(0x65E5) != 0, "a face with 日");
		});
		test("FreeType's rasters: a glyph's coverage near helder's own", () -> {
			if (!native || !FreeType.available()) return;
			var f = face("S");
			if (f == null) return;
			var b = new GlyphBitmap();
			assert(FreeType.rasterize(f, f.glyph("S".code), 32, 0, b), "drawn");
			var ink = 0;
			for (i in 0...b.width * b.height)
				ink += b.pixels.get(i);
			assert(b.width > 8 && b.height > 16 && b.top < 0 && ink > 255 * 40, 'an S: ${b.width}x${b.height} at ${b.left},${b.top}');
		});
		#end
	});
}
