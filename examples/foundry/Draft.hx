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

	public static function encode(face:Face, ?family:String):Bytes {
		var m = face.metrics, glyphs:Array<FontGlyph> = [{codes: [], advance: 500, contours: []}];
		glyphs.push({codes: [32, 0xA0], advance: Math.round(Model.EM * 0.22 + face.pen.width * 0.5), contours: []});
		for (char in Charset.all) {
			var s = Ink.shape(face, char);
			if (s.contours.length == 0) continue;
			glyphs.push({codes: [Charset.code(char)], advance: s.advance, contours: s.contours});
		}
		var top = Math.max(m.ascender, m.capHeight) + face.pen.width * 0.3;
		return FontEncoder.encode({
			family: family ?? (StringTools.trim(face.name) == "" ? "Untitled" : StringTools.trim(face.name)),
			unitsPerEm: Model.EM,
			ascender: Math.round(top + 60),
			descender: Math.round(m.descender - 80),
			lineGap: 0,
			xHeight: Math.round(m.xHeight),
			capHeight: Math.round(m.capHeight),
			weight: weight(face.pen),
			glyphs: glyphs
		});
	}

	// the draft font shown in the window: the face's glyphs now
	public static function show(face:Face) {
		var bytes = encode(face, FAMILY);
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
