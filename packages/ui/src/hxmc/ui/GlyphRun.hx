package hxmc.ui;

import haxe.io.Bytes;

// glyphs in one face at one size (Paragraph.runs): what a writer embeds
// (the face's file, subset to the glyph ids: font.id keeps faces apart)
// and places (each glyph's origin on its baseline, from the paragraph's
// top left as it is drawn aligned), with each glyph's source text (its
// cluster's characters on its first glyph, "" on the others: search and
// copy) and the span it is from (Canvas.text's colors; -1: the paragraph's)
typedef GlyphRun = {
	font:{family:String, weight:Int, italic:Bool, data:Bytes, id:Int},
	size:Float,
	glyphs:Array<Int>,
	x:Array<Float>,
	y:Array<Float>,
	text:Array<String>,
	span:Int
}
