package helder.asset;

import helder.text.FontFile;
import helder.text.SystemFonts;

// Asset.font's loader: the file's faces added to the program's fonts
// (SystemFonts.add: ui finds them by their family's name, before the
// system's), the first face the value. A reload's face is put in the old
// one (FontFile.replace: a new id, so atlases draw its glyphs again, and
// ui's texts laid out again), not added again.
class FontAsset {
	static final added = new Map<String, Bool>();

	@:helder.asset.load public static function load(key:String, ?file:String):Asset<FontFile>
		return Assets.handle("font", key, _ -> {
			var bytes = Files.read(key, file);
			var face = if (added.exists(key)) FontFile.parse(bytes) else {
				var faces = SystemFonts.get().add(bytes);
				if (faces.length == 0) throw 'not a font this reads (OpenType: TrueType or CFF outlines)';
				added.set(key, true);
				faces[0];
			}
			face;
		}, (old, fresh) -> {
			old.replace(fresh);
			old;
		});
}
