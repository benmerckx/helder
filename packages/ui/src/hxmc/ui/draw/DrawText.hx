package hxmc.ui.draw;

import hxmc.text.*;
import hxmc.ui.Font;
import hxmc.ui.Paragraph;
import hxmc.ui.TextEngine;
import hxmc.ui.TextSpan;

// hxmc.ui's TextEngine on hxmc.text: a node's Font matched among the
// system's fonts (and those added: SystemFonts.add), laid out by TextLayout
// in the UI's pixels. The Renderer draws these paragraphs.
class DrawText implements TextEngine {
	public final fonts:SystemFonts;
	final faces = new Map<String, FontFile>();
	var fallbackFaces:Null<Array<FontFile>>;
	var more:Null<Int->Null<FontFile>>;
	var emoji:Null<Int->Null<FontFile>>;

	public function new(?fonts:SystemFonts)
		this.fonts = fonts == null ? SystemFonts.get() : fonts;

	// (the last face asked for: most text has its neighbour's font)
	var lastFamily = "";
	var lastWeight = -1;
	var lastItalic = false;
	var lastFace:Null<FontFile>;

	public function face(f:Font):FontFile {
		if (lastFace != null && f.family == lastFamily && f.weight == lastWeight && f.italic == lastItalic) return lastFace;
		var key = f.family + "|" + f.weight + "|" + f.italic;
		var face = faces.get(key);
		if (face == null) {
			face = fonts.match(f.family, f.weight, f.italic);
			if (face == null) throw "hxmc.ui.draw: no font (no system fonts found: SystemFonts.add one)";
			faces.set(key, face);
		}
		lastFamily = f.family;
		lastWeight = f.weight;
		lastItalic = f.italic;
		lastFace = face;
		return face;
	}

	// the faces a font is laid out with (shared: a FontSet does not change)
	final sets = new Map<String, FontSet>();
	var lastSet:Null<FontSet>;

	function fontSet(font:Font):FontSet {
		var f = face(font), oblique = font.italic && !f.italic;
		if (lastSet != null && lastSet.primary == f && lastSet.size == font.size && lastSet.oblique == oblique) return lastSet;
		var key = f.id + "|" + font.size + "|" + oblique;
		var set = sets.get(key);
		if (set == null) {
			set = new FontSet(f, fallbackFaces, font.size, more, emoji);
			set.oblique = oblique;
			sets.set(key, set);
		}
		return lastSet = set;
	}

	public function layout(text:String, font:Font, maxWidth:Float, ?spans:Array<TextSpan>, maxLines:Int = 0, justify:Bool = false, base:Int = -1, cut:Float = -1):Paragraph {
		if (fallbackFaces == null) {
			fallbackFaces = fonts.fallbacks();
			more = fonts.fallbackFor;
			emoji = fonts.emojiFor;
		}
		var set = fontSet(font);
		var runs = spans == null ? null : [
			for (s in spans)
				new TextRun(s.start, s.end, fontSet(s.font), s.font.lineHeight, s.font.letterSpacing, s.font.wordSpacing)
		];
		var breaking = (switch font.overflowWrap {
			case Normal: 0;
			case BreakWord: TextLayout.BREAK_WORD;
			case Anywhere: TextLayout.ANYWHERE;
		}) + (switch font.wordBreak {
			case Normal: 0;
			case BreakAll: TextLayout.BREAK_ALL;
			case KeepAll: TextLayout.KEEP_ALL;
		});
		var l = new TextLayout(text, set, font.lineHeight, maxWidth, runs, maxLines, font.letterSpacing, font.wordSpacing, base, cut < 0 ? Math.NaN : cut,
			breaking);
		if (justify) l.justify(maxWidth);
		return new DrawParagraph(l);
	}
}

class DrawParagraph implements Paragraph {
	public final layout:TextLayout;

	public var width(get, never):Float;
	public var height(get, never):Float;
	public var lineCount(get, never):Int;
	public var minWidth(get, never):Float;
	public var baseline(get, never):Float;

	public function new(layout:TextLayout)
		this.layout = layout;

	inline function get_baseline()
		return layout.lines.length == 0 ? layout.baseline : layout.lines[0].top + layout.lines[0].baseline;

	inline function get_width()
		return layout.width;

	inline function get_height()
		return layout.height;

	inline function get_minWidth()
		return layout.minWidth;

	inline function get_lineCount()
		return layout.lines.length;

	public function caret(i:Int):{x:Float, y:Float, height:Float} {
		var c = layout.caret(i);
		return {x: c.x, y: c.y, height: layout.lines[c.line].height};
	}

	public function hit(x:Float, y:Float):Int
		return layout.hit(x, y);

	public function selection(start:Int, end:Int):Array<{x:Float, y:Float, width:Float}>
		return layout.selection(start, end);

	public function lineWidth(y:Float):Float {
		var ls = layout.lines, k = 0;
		while (k < ls.length - 1 && y >= ls[k].top + ls[k].height)
			k++;
		return ls.length == 0 ? 0 : ls[k].width;
	}

	public function decoration(start:Int, end:Int, kind:hxmc.ui.TextDecoration, scale:Float):Array<{x:Float, y:Float, width:Float, height:Float, lineWidth:Float}>
		return layout.decoration(start, end, kind == LineThrough ? 1 : kind == Overline ? 2 : 0, scale);
}
