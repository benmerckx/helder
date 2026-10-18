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

	// the faces a font is laid out with (shared: a FontSet does not change), each
	// one's features beside it: found by comparing, no key built
	final sets:Array<FontSet> = [];
	final setFeatures:Array<String> = [];
	var lastSet:Null<FontSet>;
	var lastFeatures = "";

	function fontSet(font:Font):FontSet {
		var f = face(font), oblique = font.italic && !f.italic;
		if (lastSet != null && lastSet.primary == f && lastSet.size == font.size && lastSet.oblique == oblique && lastFeatures == font.features) return lastSet;
		var set:Null<FontSet> = null;
		for (i in 0...sets.length) {
			var s = sets[i];
			if (s.primary == f && s.size == font.size && s.oblique == oblique && setFeatures[i] == font.features) {
				set = s;
				break;
			}
		}
		if (set == null) {
			set = new FontSet(f, fallbackFaces, font.size, more, emoji);
			set.oblique = oblique;
			if (font.features != "") set.features = hxmc.text.FontFeature.parse(font.features);
			sets.push(set);
			setFeatures.push(font.features);
		}
		lastFeatures = font.features;
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

	public function runs(width:Float, align:TextAlign):Array<GlyphRun> {
		var t = layout, out:Array<GlyphRun> = [], cur:Null<GlyphRun> = null, last = -1;
		for (l in t.lines) {
			var lx = switch align {
				case Center: (width - l.width) / 2;
				case Right: width - l.width;
				case _: 0.0;
			}
			for (g in l.glyphs) {
				if (g.hidden || g.cp == 10) continue;
				var set = g.run < 0 ? t.fonts : t.runs[g.run].fonts, f = g.font;
				if (cur == null || cur.font.id != f.id || cur.size != set.size || cur.span != g.run) {
					cur = {
						font: {family: f.family, weight: f.weight, italic: f.italic, data: f.data, id: f.id},
						size: set.size,
						glyphs: [],
						x: [],
						y: [],
						text: [],
						span: g.run
					};
					out.push(cur);
				}
				cur.glyphs.push(g.id);
				cur.x.push(lx + g.x + g.dx);
				cur.y.push(l.top + l.baseline + g.dy);
				// (a cluster's characters on its first glyph)
				cur.text.push(g.cluster == last ? "" : t.text.substr(g.cluster, g.length));
				last = g.cluster;
			}
		}
		return out;
	}

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

	public function decoration(start:Int, end:Int, kind:hxmc.ui.TextDecoration, scale:Float, ?thickness:Float, ?offset:Float):Array<{
		x:Float,
		y:Float,
		width:Float,
		height:Float,
		lineWidth:Float
	}>
		return layout.decoration(start, end, kind == LineThrough ? 1 : kind == Overline ? 2 : 0, scale, thickness == null ? Math.NaN : thickness,
			offset == null ? Math.NaN : offset);
}
