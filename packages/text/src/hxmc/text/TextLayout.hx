package hxmc.text;

// Text laid out in lines: shaped (each character's glyph from the first
// face of the FontSet that has it, advances from hmtx, kerning pairs
// between glyphs of the same face) and broken greedily at break
// opportunities (after spaces and hyphens, around CJK ideographs, kana and
// hangul) to fit maxWidth (NaN: only at "\n"); a word wider than a line is
// cut between characters, except at a maxWidth of 0: the min-content
// layout, every opportunity taken and no word cut. Left to right only (no bidi), no ligatures or
// mark positioning (no GSUB, GPOS). Positions are pixels; character
// indices are the text's UTF-16 units (String indices).
class TextLayout {
	public final text:String;
	public final fonts:FontSet;
	public final lines:Array<TextLine> = [];
	// the widest line (trailing spaces excluded), the lines' total height
	public var width(default, null) = 0.0;
	public var height(default, null) = 0.0;
	// the min-content width: the widest run between break opportunities
	// (trailing spaces excluded), the width of the layout at a maxWidth of 0
	public var minWidth(default, null) = 0.0;
	// a line's height and its baseline below its top
	public final lineHeight:Float;
	public final baseline:Float;

	// lineHeight: a multiple of the size
	public function new(text:String, fonts:FontSet, lineHeight:Float, maxWidth:Float) {
		this.text = text;
		this.fonts = fonts;
		this.lineHeight = fonts.size * lineHeight;
		var a = fonts.ascent, d = fonts.descent;
		baseline = (this.lineHeight - (a + d)) / 2 + a;
		var glyphs = shape(text, fonts);
		minWidth = minContent(glyphs);
		breakLines(glyphs, maxWidth);
	}

	// --- shaping ---

	static function shape(text:String, fonts:FontSet):Array<Glyph> {
		var out:Array<Glyph> = [];
		var i = 0, n = text.length, count = 0;
		// (at most a glyph per UTF-16 unit: allocated once, cut to the count after)
		out.resize(n);
		var prev:Null<Glyph> = null;
		while (i < n) {
			var c = StringTools.fastCodeAt(text, i), len = 1;
			if (c >= 0xD800 && c < 0xDC00 && i + 1 < n) {
				var d = StringTools.fastCodeAt(text, i + 1);
				if (d >= 0xDC00 && d < 0xE000) {
					c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
					len = 2;
				}
			}
			var g = new Glyph();
			g.cp = c;
			g.cluster = i;
			g.length = len;
			if (c == 10 || c == 13) {
				g.font = fonts.primary;
				g.id = 0;
				g.advance = 0;
			} else {
				var f = c == 9 ? fonts.primary : fonts.faceFor(c);
				g.font = f;
				g.id = c == 9 ? f.glyph(32) : f.glyph(c);
				g.advance = f.advance(g.id) * fonts.scale(f) * (c == 9 ? 4 : 1);
				if (prev != null && prev.font == f && prev.cp != 10) prev.advance += f.kerning(prev.id, g.id) * fonts.scale(f);
			}
			out[count++] = g;
			prev = g;
			i += len;
		}
		out.resize(count);
		return out;
	}

	// --- line breaking ---

	static inline function isSpace(c:Int):Bool
		return c == 32 || c == 9 || c == 0x3000;

	static inline function isCJK(c:Int):Bool
		return (c >= 0x2E80 && c <= 0x9FFF) || (c >= 0xAC00 && c <= 0xD7AF) || (c >= 0xF900 && c <= 0xFAFF) || (c >= 0xFF00 && c <= 0xFFEF)
			|| (c >= 0x20000 && c <= 0x3FFFF);

	// may a line break before glyph i?
	static function breakBefore(gs:Array<Glyph>, i:Int):Bool {
		if (i == 0) return false;
		var p = gs[i - 1].cp, c = gs[i].cp;
		if (isSpace(c)) return false; // (spaces stay at the end of the line)
		return isSpace(p) || p == 0x2D || p == 0x2010 || p == 0x2013 || p == 0x2014 || p == 0x2F || isCJK(p) || isCJK(c);
	}

	static function minContent(gs:Array<Glyph>):Float {
		var widest = 0.0, x = 0.0, visible = 0.0;
		for (i in 0...gs.length) {
			var g = gs[i];
			if (g.cp == 10 || breakBefore(gs, i)) {
				if (visible > widest) widest = visible;
				x = visible = 0;
				if (g.cp == 10) continue;
			}
			x += g.advance;
			if (!isSpace(g.cp)) visible = x;
		}
		return visible > widest ? visible : widest;
	}

	function breakLines(gs:Array<Glyph>, maxWidth:Float) {
		var wrap = !Math.isNaN(maxWidth);
		var start = 0, n = gs.length;
		while (true) {
			// one hard line: start until "\n" (or the end)
			var end = start;
			while (end < n && gs[end].cp != 10)
				end++;
			fill(gs, start, end, wrap ? maxWidth : Math.POSITIVE_INFINITY);
			if (end >= n) break;
			// (after a final "\n": an empty line, filled by the next round)
			start = end + 1;
		}
		if (lines.length == 0) addLine(gs, 0, 0);
		height = lines.length * lineHeight;
	}

	// the glyphs start...end (no "\n") in lines no wider than max
	function fill(gs:Array<Glyph>, start:Int, end:Int, max:Float) {
		if (start == end) {
			addLine(gs, start, end, start < gs.length ? gs[start].cluster : text.length);
			return;
		}
		var lineStart = start;
		while (lineStart < end) {
			var w = 0.0, lastBreak = -1, i = lineStart;
			while (i < end) {
				var g = gs[i];
				if (i > lineStart && breakBefore(gs, i)) lastBreak = i;
				// (trailing spaces may overflow)
				if (!isSpace(g.cp) && w + g.advance > max + 1e-3 && i > lineStart) break;
				w += g.advance;
				i++;
			}
			// (at a width of 0, a word stays whole: up to the next opportunity)
			if (max <= 0 && lastBreak <= lineStart && i < end) {
				while (i < end && !breakBefore(gs, i))
					i++;
			}
			var cut = i >= end ? end : lastBreak > lineStart ? lastBreak : i;
			addLine(gs, lineStart, cut);
			lineStart = cut;
		}
	}

	function addLine(gs:Array<Glyph>, start:Int, end:Int, ?emptyAt:Int) {
		var l = new TextLine();
		l.top = lines.length * lineHeight;
		var x = 0.0, visible = 0.0;
		l.glyphs.resize(end - start);
		for (i in start...end) {
			var g = gs[i];
			g.x = x;
			l.glyphs[i - start] = g;
			x += g.advance;
			if (!isSpace(g.cp)) visible = x;
		}
		l.width = visible;
		l.advance = x;
		l.start = start < end ? gs[start].cluster : emptyAt != null ? emptyAt : (start < gs.length ? gs[start].cluster : text.length);
		l.end = start < end ? gs[end - 1].cluster + gs[end - 1].length : l.start;
		if (visible > width) width = visible;
		lines.push(l);
	}

	// --- queries ---

	// the line of a character index
	public function lineOf(index:Int):Int {
		for (k in 0...lines.length)
			if (index < lines[k].end || k == lines.length - 1) return k;
		return lines.length - 1;
	}

	// the caret before character index (x from the line's start, the line's top)
	public function caret(index:Int):{x:Float, y:Float, line:Int} {
		var k = 0;
		for (j in 0...lines.length) {
			var l = lines[j];
			if (index >= l.start) k = j;
		}
		var l = lines[k];
		var x = 0.0;
		for (g in l.glyphs) {
			if (g.cluster >= index) break;
			x = g.x + g.advance;
		}
		if (index <= l.start) x = 0;
		return {x: x, y: l.top, line: k};
	}

	// the character index nearest to (x, y)
	public function hit(x:Float, y:Float):Int {
		var k = Std.int(Math.max(0, Math.min(lines.length - 1, Math.floor(y / lineHeight))));
		var l = lines[k];
		for (g in l.glyphs) {
			if (g.cp == 10) break;
			if (x < g.x + g.advance / 2) return g.cluster;
		}
		// (the end of a wrapped line: before its trailing break)
		return k < lines.length - 1 && l.glyphs.length > 0 ? l.end : l.end;
	}
}

// a glyph placed in its line
class Glyph {
	public var font:FontFile;
	public var id = 0;
	public var cp = 0;
	// pixels from the line's start, and to the next glyph
	public var x = 0.0;
	public var advance = 0.0;
	// the character it shows: its index in the text and length (UTF-16 units)
	public var cluster = 0;
	public var length = 1;

	public function new() {}
}

class TextLine {
	public final glyphs:Array<Glyph> = [];
	// its characters: start (inclusive) to end (exclusive), UTF-16 units
	public var start = 0;
	public var end = 0;
	// pixels: without trailing spaces, with them; its top in the layout
	public var width = 0.0;
	public var advance = 0.0;
	public var top = 0.0;

	public function new() {}
}
