import haxe.io.Bytes;
import helder.text.*;
import helder.text.Shaping;

// The platform's text stack behind helder.text (the system-text lane,
// natively: Linux's fontconfig, HarfBuzz and FreeType; Windows' DirectWrite;
// macOS's Core Text): fallback faces for each script, a family found, the
// complex scripts shaped (Devanagari's reordered vowel sign, Bengali's split
// vowel, Tamil's), TextLayout through it, glyphs rasterised; a sample of
// every script drawn through the atlas with the platform's engine and with
// helder's own (bin/text/system-<os>.png).
class SystemTextTest {
	static var failures = 0;
	// (under Wine, from Linux: its DirectWrite falls back to its own few fonts and does not reorder Indic scripts; noted, not failed)
	static final wine = Sys.getEnv("HELDER_UNDER_WINE") == "1";

	static function check(name:String, ok:Bool, ?detail:String, ?lenient:Bool) {
		var soft = lenient == true && wine;
		Sys.println((ok ? "ok   " : soft ? "wine " : "FAIL ") + name + (detail != null ? ": " + detail : ""));
		if (!ok && !soft) failures++;
	}

	static final SCRIPTS = [
		{name: "Latin", text: "Shaping wave AV", cp: "S".code},
		{name: "Hebrew", text: "שלום עולם", cp: 0x5E9},
		{name: "Arabic", text: "مرحبا بالعالم", cp: 0x645},
		{name: "Devanagari", text: "हिन्दी भाषा", cp: 0x939},
		{name: "Bengali", text: "বাংলা কোথায়", cp: 0x9AC},
		{name: "Tamil", text: "தமிழ் கொண்டு", cp: 0xBA4},
		{name: "Thai", text: "สวัสดีครับ", cp: 0xE2A},
		{name: "CJK", text: "日本語の文字", cp: 0x65E5},
		{name: "Emoji", text: "😀 🎉", cp: 0x1F600}
	];

	static function main() {
		Shaping.engine = Shaping.SYSTEM;
		var be = Shaping.backend();
		check("a platform back end", be != null, be == null ? "none" : be.name());
		if (be == null) Sys.exit(1);
		var fonts = SystemFonts.get();
		var sans = fonts.match("sans-serif", 400);
		check("a sans-serif face", sans != null);
		// fallback: a face for each script, the system's
		var faces = new Map<String, FontFile>();
		for (s in SCRIPTS) {
			var m = be.fallback(s.cp);
			var f = sans != null && sans.glyph(s.cp) != 0 ? sans : fonts.fallbackFor(s.cp);
			if (f == null) for (g in fonts.fallbacks()) if (g.glyph(s.cp) != 0) f = g;
			if (f == null && s.name == "Emoji") f = fonts.emojiFor(s.cp);
			Sys.println('     ${s.name}: ${be.name()} falls back to ${m == null ? "nothing" : m.path + "#" + m.index}; laid out in ${f == null ? "none" : f.family}');
			if (f != null) faces.set(s.name, f);
			if (s.name != "Emoji" && s.name != "Thai" && s.name != "Bengali" && s.name != "Tamil") check(s.name + ": a fallback face", m != null, null, s.name != "Latin");
		}
		// discovery: a family the system has
		// (Wine's prefix may have only its own and DejaVu)
		var families = Sys.systemName() == "Windows" ? ["Arial", "Tahoma", "DejaVu Sans"] : Sys.systemName() == "Mac" ? ["Helvetica"] : ["DejaVu Sans"];
		var found:Null<{path:String, index:Int}> = null, family = "";
		for (f in families)
			if (found == null) {
				found = be.find(f, 700, false);
				family = f;
			}
		check('$family Bold found', found != null, found == null ? null : found.path + "#" + found.index);
		// shaping: the reordering helder's engine does not do
		var out = new ShapedGlyphs();
		var d = faces.get("Devanagari");
		if (d != null) {
			var ok = be.shape(d, "हि", 0, 2, false, out);
			check("Devanagari: हि shaped, the vowel sign first", ok && out.count >= 2 && out.ids[0] != d.glyph(0x939) && out.ids[out.count - 1] == d.glyph(0x939),
				[for (i in 0...out.count) out.ids[i] + "@" + out.clusters[i]].join(" ") + ' (ह ${d.glyph(0x939)})', true);
			var l = new TextLayout("हिन्दी", new FontSet(d, [], 24), 1.2, Math.NaN);
			check("Devanagari: TextLayout's first glyph not ह", l.glyphId(0) != d.glyph(0x939), null, true);
		}
		var b = faces.get("Bengali");
		if (b != null) {
			var ok = be.shape(b, "কো", 0, 2, false, out);
			check("Bengali: কো split around its consonant", ok && out.count >= 3 && out.ids[1] == b.glyph(0x995), [for (i in 0...out.count) out.ids[i]].join(" "), true);
		}
		var t = faces.get("Tamil");
		if (t != null) {
			var ok = be.shape(t, "கொ", 0, 2, false, out);
			check("Tamil: கொ split around its consonant", ok && out.count >= 3 && out.ids[1] == t.glyph(0xB95), [for (i in 0...out.count) out.ids[i]].join(" "), true);
		}
		// rasterising
		if (sans != null) {
			var bm = new GlyphBitmap();
			var ok = be.rasterize(sans, sans.glyph("S".code), 32, 0, bm), ink = 0;
			for (i in 0...bm.width * bm.height)
				ink += bm.pixels.get(i);
			check("an S rasterised at 32 px", ok && bm.width > 8 && bm.height > 16 && bm.top < 0 && ink > 255 * 40, '${bm.width}x${bm.height} at ${bm.left},${bm.top}');
		}
		sample(faces, fonts, sans);
		Sys.println(failures == 0 ? "system-text: all passed" : 'system-text: $failures failed');
		Sys.exit(failures == 0 ? 0 : 1);
	}

	// each script's line with the platform's engine (left) and helder's (right)
	static function sample(faces:Map<String, FontFile>, fonts:SystemFonts, sans:Null<FontFile>) {
		if (sans == null) return;
		var W = 640, H = 34 * SCRIPTS.length + 8;
		var img = Bytes.alloc(W * H * 4);
		img.fill(0, img.length, 255);
		for (engine in [Shaping.SYSTEM, Shaping.HELDER]) {
			Shaping.engine = engine;
			var atlas = new GlyphAtlas(1024, 1024), x0 = engine == Shaping.SYSTEM ? 8 : W / 2 + 8, y = 4.0;
			for (s in SCRIPTS) {
				var set = new FontSet(sans, fonts.fallbacks(), 22, fonts.fallbackFor, fonts.emojiFor);
				var l = new TextLayout(s.text, set, 1.4, W / 2 - 16);
				for (line in l.lines) {
					var by = Math.round(y + line.top + line.baseline);
					for (i in line.glyphStart...line.glyphEnd) {
						if (l.glyphHidden(i) || l.glyphFont(i).hasColor) continue;
						var gx = x0 + l.glyphX(i) + l.glyphOffsetX(i), ix = Math.floor(gx), sub = Std.int((gx - ix) * GlyphAtlas.SUBPIXELS);
						var a = atlas.get(l.glyphFont(i), l.glyphId(i), 22, sub);
						for (py in 0...a.h)
							for (px in 0...a.w) {
								var X = ix + a.left + px, Y = by + Math.round(l.glyphOffsetY(i)) + a.top + py;
								if (X < 0 || Y < 0 || X >= W || Y >= H) continue;
								var cov = atlas.pixels.get((a.y + py) * atlas.width + a.x + px), o = 4 * (Y * W + X);
								var v = Std.int(img.get(o) * (255 - cov) / 255);
								img.set(o, v);
								img.set(o + 1, v);
								img.set(o + 2, v);
							}
					}
				}
				y += 34;
			}
		}
		sys.FileSystem.createDirectory("bin/text");
		var os = Sys.systemName().toLowerCase();
		sys.io.File.saveBytes('bin/text/system-$os.png', helder.image.PngEncoder.encode(img, W, H));
		Sys.println('     bin/text/system-$os.png: the platform\'s engine left, helder\'s right');
	}
}
