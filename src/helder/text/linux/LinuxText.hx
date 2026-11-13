package helder.text.linux;

import helder.text.Shaping;

// Linux's text stack behind helder.text: fontconfig's fallback and
// families, HarfBuzz's shaping, FreeType's rasters; each library loaded
// when first needed (none: helder's own for that part).
class LinuxText implements TextBackend {
	public static function create():Null<TextBackend>
		return new LinuxText();

	function new() {}

	public function blend():Null<GlyphBlend>
		return null;

	public function name():String
		return "HarfBuzz";

	public function shape(font:FontFile, text:String, start:Int, end:Int, rtl:Bool, out:ShapedGlyphs):Bool
		return HarfBuzz.shapeInto(font, text, start, end, rtl, out);

	public function rasterize(font:FontFile, glyph:Int, size:Float, dx:Float, out:GlyphBitmap):Bool
		return FreeType.rasterize(font, glyph, size, dx, out);

	public function fallback(cp:Int, ?lang:String):Null<{path:String, index:Int}>
		return Fontconfig.fileFor(cp, lang);

	public function find(family:String, weight:Int, italic:Bool):Null<{path:String, index:Int}>
		return Fontconfig.family(family, weight, italic);
}
