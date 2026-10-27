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
}
#end
