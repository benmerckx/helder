package helder.text;

#if (target.name == "hxmc")
import hxmc.unsafe.*;

// The fonts a page gives a WebAssembly module (src/helder/text/imports.mjs:
// run's option fonts): SystemFonts adds them when it looks for fonts in the
// browser
@:hxmc.c @:hxmc.fast @:hxmc.lib("hxmc_text") extern class WebFontsImports {
	static function font_count():Int;
	static function font_size(i:Int):Int;
	// (safe: no more than buf's length, imports.mjs)
	@:hxmc.safe static function font_read(i:Int, buf:hxmc.Span<UInt8>):Void;
	// (the family a string copied for the call, the file a span: imports.mjs)
	@:hxmc.safe static function font_face(family:String, weight:Int, italic:Int, buf:hxmc.ReadOnlySpan<UInt8>):Void;
}

class WebFonts {
	// the page's fonts' bytes
	public static function all():Array<haxe.io.Bytes> {
		var out = [];
		for (i in 0...WebFontsImports.font_count()) {
			var n = WebFontsImports.font_size(i);
			var b = haxe.io.Bytes.alloc(n);
			WebFontsImports.font_read(i, hxmc.Span.ofBytes(b));
			out.push(b);
		}
		return out;
	}

	// a font the program added (or one it replaced: the same family, weight
	// and style, the page's face replaced too) given to
	// the page too, as a FontFace: the page's own text fields
	// (WebViews' editors) are set in it by its family's name
	public static function face(f:FontFile) {
		if (hxmc.Platform.os() != hxmc.Platform.WASI) return;
		WebFontsImports.font_face(f.family, f.weight, f.italic ? 1 : 0, hxmc.ReadOnlySpan.ofBytes(f.data));
	}
}
#end
