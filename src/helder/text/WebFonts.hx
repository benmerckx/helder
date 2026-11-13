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
}
#end
