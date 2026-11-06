package helder.canvas;

// A Painter that keeps glyph outlines on its own side (web.WebCanvas: a
// Path2D each in the page), so text repeats send a key and a transform,
// not the outline: glyphs(paint) once, then glyph(key, outline, matrix)
// for each, the outline asked for only the first time a key is drawn.
// Keys are the caller's (a font's id and its glyph), the same for the
// whole program.
interface GlyphCache {
	function glyphs(paint:Paint):Void;
	function glyph(key:Int, outline:() -> Path, m:Matrix):Void;
}
