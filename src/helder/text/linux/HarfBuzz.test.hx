package helder.text.linux;

import helder.test.Test;

// The native stack's first slice on Linux (natively; skipped without
// fontconfig or HarfBuzz): fontconfig's fallback finding a face for each
// script's text, then helder.text's own shaping against HarfBuzz's on it
// (the glyphs, in visual order). Latin, Hebrew, Arabic and CJK as helder
// shapes them already must match; Devanagari and Thai (reordering,
// conjuncts, which helder's engine does not do) are recorded, the case for
// shaping through HarfBuzz itself.
function tests() {
	describe("HarfBuzz and fontconfig (Linux)", () -> {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		var native = hxmc.unsafe.Mem.os() == 0 && hxmc.unsafe.Mem.target() < 9 && HarfBuzz.available();
		function ids(text:String, f:helder.text.FontFile):{helder:Array<Int>, hb:Array<Int>} {
			var l = new helder.text.TextLayout(text, new helder.text.FontSet(f, [], 16), 1.2, Math.NaN);
			var mine = [for (i in 0...l.glyphCount) if (l.glyphId(i) != 0 || true) l.glyphId(i)];
			var hb = [for (g in HarfBuzz.shape(f.data, @:privateAccess f.index, text)) g.id];
			return {helder: mine, hb: hb};
		}
		for (c in [
			{name: "Latin", text: "Shaping wave", must: true},
			{name: "Hebrew", text: "שלום עולם", must: true},
			{name: "Arabic", text: "مرحبا بالعالم", must: true},
			{name: "CJK", text: "日本語の文字", must: true},
			{name: "Devanagari", text: "हिन्दी", must: false},
			{name: "Thai", text: "สวัสดีครับ", must: false}
		])
			test('${c.name}: fontconfig\'s face, helder\'s glyphs against HarfBuzz\'s', () -> {
				if (!native) return;
				var cp = 0;
				for (u in new haxe.iterators.StringIteratorUnicode(c.text))
					if (u > 0x7F && cp == 0) cp = u;
				var m = Fontconfig.fileFor(cp == 0 ? "S".code : cp);
				if (m == null) {
					Sys.println('  (${c.name}: no font on this system)');
					return;
				}
				var f = helder.text.FontFile.parse(sys.io.File.getBytes(m.path), m.index);
				var r = ids(c.text, f);
				if (c.must) equals(r.helder, r.hb, '${c.name} in ${m.path}') else
					Sys.println('  (${c.name} in ${haxe.io.Path.withoutDirectory(m.path)}: helder ${r.helder.join(",")}, HarfBuzz ${r.hb.join(",")}: ${r.helder.join(",") == r.hb.join(",") ? "the same" : "not the same"})');
			});
		test("SystemFonts' fallback through fontconfig: a character none of its lists has", () -> {
			if (!native) return;
			// (a CJK ideograph: MORE's names may be missing, fontconfig finds what the system has)
			var m = Fontconfig.fileFor(0x65E5);
			if (m == null) return;
			var f = helder.text.SystemFonts.get().fallbackFor(0x65E5);
			assert(f != null && f.glyph(0x65E5) != 0, "a face with 日");
		});
		#end
	});
}
