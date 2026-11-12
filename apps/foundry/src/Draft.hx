import Model;
import haxe.io.Bytes;
import helder.text.FontEncoder;
import helder.text.FontFile;
import helder.text.SystemFonts;

// The face as a font: every glyph with ink, its contours as Ink makes
// them, written by helder.text's FontEncoder; and the draft every text of
// the window can be set in (FAMILY): added to the system's fonts once,
// replaced in place after each edit, so the texts in it are laid out
// again with the new glyphs (as helder.asset reloads a font).
class Draft {
	public static inline var FAMILY = "Foundry Draft";

	static var live:Null<FontFile> = null;
	static var version = 1;

	public static function encode(face:Face, ?family:String, ?postScriptName:String):Bytes {
		var m = face.metrics, src = face.source;
		// (a face from a font: written in its units and its glyphs' order, its layout tables as they were)
		var k = src == null ? 1.0 : src.units / Model.EM;
		var glyphs:Array<FontGlyph> = [], placed = new Map<String, Bool>(), index = new Map<String, Int>();
		function glyph(key:String, keep:Bool) {
			placed.set(key, true);
			var s = Ink.shape(face, key), g = Model.glyph(face, key), cp = Charset.code(key);
			var codes = cp >= 0 ? [cp] : [];
			if (g != null && g.also != null) codes = codes.concat(g.also);
			if (s.contours.length == 0 && !keep) return;
			index.set(key, glyphs.length);
			glyphs.push({
				codes: codes,
				advance: (s.contours.length == 0 ? g?.advance ?? 0 : s.advance) * k,
				contours: [for (c in s.contours) [for (p in c) {x: p.x * k, y: p.y * k, on: p.on}]]
			});
		}
		if (src != null) {
			for (key in src.order)
				glyph(key, true);
		} else {
			glyphs.push({codes: [], advance: 500, contours: []});
			glyphs.push({codes: [32, 0xA0], advance: Math.round(Model.EM * 0.22 + face.pen.width * 0.5), contours: []});
		}
		for (key in Charset.list(face))
			if (!placed.exists(key)) glyph(key, false);
		var tables = new Map<String, Bytes>();
		if (src != null)
			for (tag => b in src.tables)
				tables.set(tag, haxe.crypto.Base64.decode(b));
		var top = Math.max(m.ascender, m.capHeight) + face.pen.width * 0.3;
		return FontEncoder.encode({
			family: family ?? (StringTools.trim(face.name) == "" ? "Untitled" : StringTools.trim(face.name)),
			unitsPerEm: src == null ? Model.EM : src.units,
			ascender: Math.round((top + 60) * k),
			descender: Math.round((m.descender - 80) * k),
			lineGap: 0,
			xHeight: Math.round(m.xHeight * k),
			capHeight: Math.round(m.capHeight * k),
			weight: weight(face.pen),
			postScriptName: postScriptName,
			glyphs: glyphs,
			kerning: face.kerning == null ? null : [for (pair => v in face.kerning) {
				var at = pair.indexOf("\t"), l = index.get(pair.substr(0, at)), r = index.get(pair.substr(at + 1));
				if (l != null && r != null) {left: l, right: r, value: Math.round(v * k)};
			}].filter(p -> p != null),
			tables: tables
		});
	}

	// the draft font shown in the window: the face's glyphs now
	public static function show(face:Face) {
		// (each version its own PostScript name: Core Text keeps the first font of a name)
		var bytes = encode(face, FAMILY, "FoundryDraft-" + version++);
		var fresh = try FontFile.parse(bytes) catch (_:Dynamic) null;
		if (fresh == null) return;
		var f = live;
		if (f == null) live = SystemFonts.get().add(bytes)[0] else f.replace(fresh);
	}

	// how heavy the pen draws, as CSS's weights
	public static function weight(pen:Pen):Int {
		var w = Math.round((pen.width - 20) / 160 * 800 + 100);
		return Std.int(Math.max(100, Math.min(900, Math.round(w / 100) * 100)));
	}

	// a weight's name, for the panel
	public static function weightName(pen:Pen):String
		return switch weight(pen) {
			case 100: "Thin";
			case 200: "Extra Light";
			case 300: "Light";
			case 400: "Regular";
			case 500: "Medium";
			case 600: "Semibold";
			case 700: "Bold";
			case 800: "Extra Bold";
			case _: "Black";
		}
}
