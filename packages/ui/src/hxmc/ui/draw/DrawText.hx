package hxmc.ui.draw;

import hxmc.text.*;
import hxmc.ui.Font;
import hxmc.ui.Paragraph;
import hxmc.ui.TextEngine;

// hxmc.ui's TextEngine on hxmc.text: a node's Font matched among the
// system's fonts (and those added: SystemFonts.add), laid out by TextLayout
// in the UI's pixels. The Renderer draws these paragraphs.
class DrawText implements TextEngine {
	public final fonts:SystemFonts;
	final faces = new Map<String, FontFile>();
	var fallbackFaces:Null<Array<FontFile>>;

	public function new(?fonts:SystemFonts)
		this.fonts = fonts == null ? SystemFonts.get() : fonts;

	public function face(f:Font):FontFile {
		var key = f.family + "|" + f.weight + "|" + f.italic;
		var face = faces.get(key);
		if (face == null) {
			face = fonts.match(f.family, f.weight, f.italic);
			if (face == null) throw "hxmc.ui.draw: no font (no system fonts found: SystemFonts.add one)";
			faces.set(key, face);
		}
		return face;
	}

	public function layout(text:String, font:Font, maxWidth:Float):Paragraph {
		if (fallbackFaces == null) fallbackFaces = fonts.fallbacks();
		var set = new FontSet(face(font), fallbackFaces, font.size);
		return new DrawParagraph(new TextLayout(text, set, font.lineHeight, maxWidth));
	}
}

class DrawParagraph implements Paragraph {
	public final layout:TextLayout;

	public var width(get, never):Float;
	public var height(get, never):Float;
	public var lineCount(get, never):Int;

	public function new(layout:TextLayout)
		this.layout = layout;

	inline function get_width()
		return layout.width;

	inline function get_height()
		return layout.height;

	inline function get_lineCount()
		return layout.lines.length;

	public function caret(i:Int):{x:Float, y:Float, height:Float} {
		var c = layout.caret(i);
		return {x: c.x, y: c.y, height: layout.lineHeight};
	}

	public function hit(x:Float, y:Float):Int
		return layout.hit(x, y);
}
