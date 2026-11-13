package helder.image;

#if (hxmc.target == "wasm32-wasi")
import hxmc.ReadOnlySpan;
import hxmc.Span;
import hxmc.unsafe.UInt8;

// Images the browser decodes (WebAssembly): imports of the module
// "helder_image", which src/helder/gfx/imports.mjs provides beside the GPU's
// (helder.gfx uploads them: ImageTexture). An image is a handle into the
// page's table: its file (a Uint8Array) and, once decoded, an ImageBitmap,
// neither in the module's memory. A decode's end wakes the loop
// (helder_async's wake).
@:hxmc.c @:hxmc.fast @:hxmc.lib("helder_image") extern class WebImages {
	// an image decoded from a fetch's body (helder_async's handle, taken:
	// freed), or from length bytes of file (copied) when fetch is 0;
	// premultiply 1: its pixels premultiplied by their alpha
	@:hxmc.safe @:hxmc.len(file, length) static function decode(fetch:Int, file:ReadOnlySpan<UInt8>, length:Int, premultiply:Int):Int;
	// 0 while it decodes, 1 decoded, -1 not an image the browser reads
	static function state(image:Int):Int;
	static function width(image:Int):Int;
	static function height(image:Int):Int;
	// its file's length, and the file copied into buf (no more than its length)
	static function file_length(image:Int):Int;
	@:hxmc.safe static function file_take(image:Int, buf:Span<UInt8>):Void;
	// its decoded pixels given back (the file kept: decoded again when needed)
	static function close(image:Int):Void;
	static function free(image:Int):Void;
}
#end
