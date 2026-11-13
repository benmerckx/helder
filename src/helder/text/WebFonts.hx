package helder.text;

#if (target.name == "hxmc")
import hxmc.unsafe.*;

// The fonts a page gives a WebAssembly module (src/helder/text/imports.mjs:
// run's option fonts): SystemFonts adds them when it looks for fonts in the
// browser
@:hxmc.c @:hxmc.fast @:hxmc.lib("hxmc_text") extern class WebFontsImports {
	static function font_count():Int;
	static function font_size(i:Int):Int;
	static function font_read(i:Int, p:Ptr):Void;
	static function font_face(family:Ptr, weight:Int, italic:Int, p:Ptr, n:Int):Void;
}

class WebFonts {
	// the page's fonts' bytes
	public static function all():Array<haxe.io.Bytes> {
		var out = [];
		for (i in 0...WebFontsImports.font_count()) {
			var n = WebFontsImports.font_size(i);
			var b = haxe.io.Bytes.alloc(n);
			// (the Bytes cannot move during an import)
			var p = BytesPtr.of(b, 0, n);
			WebFontsImports.font_read(i, p);
			BytesPtr.written(b, 0, p, n);
			out.push(b);
		}
		return out;
	}

	// a font the program added (or one it replaced: the same family, weight
	// and style, the page's face replaced too) given to
	// the page too, as a FontFace: the page's own text fields
	// (WebViews' editors) are set in it by its family's name
	public static function face(f:FontFile) {
		if (Mem.os() != 3) return;
		var b = f.data;
		Arena.scoped(a -> {
			var p = BytesPtr.of(b, 0, b.length);
			WebFontsImports.font_face(a.cstring(f.family), f.weight, f.italic ? 1 : 0, p, b.length);
		});
	}
}
#end
