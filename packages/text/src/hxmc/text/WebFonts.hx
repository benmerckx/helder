package hxmc.text;

#if (target.name == "hxmc")
import hxmc.unsafe.*;

// The fonts a page gives a WebAssembly module (packages/text/imports.mjs:
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
			var b = haxe.io.Bytes.alloc(WebFontsImports.font_size(i));
			// (the Bytes cannot move during an import)
			WebFontsImports.font_read(i, Mem.addr(b).add(8));
			out.push(b);
		}
		return out;
	}
}
#end
