import Model;
import helder.asset.Asset;
import helder.text.FontFile;
import helder.text.SystemFonts;

// The fonts a face can come from, by name: "current" (the one being
// drawn), "Pebble", the open fonts Foundry carries (Inter, Hanken
// Grotesk, Geist Mono), any font installed on the system (by family);
// each read once, its outlines kept (Outlines) or traced into pen lines
// (Trace), and kept.
class Sources {
	static final BUNDLED = ["Inter", "Hanken Grotesk", "Geist Mono"];
	static final kept = new Map<String, Face>();

	public static function names():Array<String> {
		var out = ["current", "Pebble"].concat(BUNDLED);
		#if !(hxmc.target == "wasm32-wasi")
		for (f in SystemFonts.get().families())
			if (f.charAt(0) != "." && out.indexOf(f) < 0) out.push(f);
		#end
		return out;
	}

	// name's face: its outlines kept (else traced into pen lines)
	public static function face(name:String, ws:Workshop, pen = false):Face {
		var key = name.toLowerCase();
		if (key == "current") return ws.value();
		if (key == "pebble") return Sample.face();
		var id = (pen ? "pen:" : "outline:") + key, hit = kept.get(id);
		if (hit != null) return hit;
		var font = switch key {
			case "inter": FontFile.parse(Asset.embed("fonts/Inter.ttf"));
			case "hanken grotesk": FontFile.parse(Asset.embed("fonts/HankenGrotesk-Regular.ttf"));
			case "geist mono": FontFile.parse(Asset.embed("fonts/GeistMono-Regular.ttf"));
			case _:
				var f = SystemFonts.get().match(name);
				if (f == null || f.family.toLowerCase() != key) throw 'No font named "$name" (sources.list names them)';
				f;
		}
		var made = pen ? Trace.face(font, name) : Outlines.face(font, name);
		kept.set(id, made);
		return made;
	}
}
