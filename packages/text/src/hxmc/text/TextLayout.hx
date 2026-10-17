package hxmc.text;

// Text laid out in lines: shaped (each character's glyph from the first
// face of the FontSet that has it, advances from hmtx, kerning (GPOS, kern)
// between glyphs of the same face) and broken greedily at break
// opportunities (after spaces and hyphens, around CJK ideographs, kana and
// hangul) to fit maxWidth (NaN: only at "\n"); a word wider than a line is
// cut between characters, except at a maxWidth of 0: the min-content
// layout, every opportunity taken and no word cut. Text written right to
// left is ordered by the bidirectional algorithm (Bidi: each paragraph's
// levels; each line's glyphs placed in visual order, mirrored brackets on
// right-to-left levels; a base's marks drawn after it), its caret and hits
// by each glyph's direction. The standard ligatures (GSUB's liga and clig)
// are applied as Chromium applies them by default, except where letters
// are spaced; GPOS gives kerning and marks' positions.
// Positions are pixels; character indices are the text's UTF-16 units
// (String indices). Arabic is shaped (Arabic: its letters' joining forms
// and required ligatures, through the font's GSUB).
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
	// the first paragraph's direction: 0 left to right, 1 right to left
	public var direction(default, null) = 0;
	// a line's height and its baseline below its top, in the paragraph's own
	// font (with runs of others, each line's own: TextLine.height, baseline)
	public final lineHeight:Float;
	public final baseline:Float;
	// parts of the text in other fonts (each glyph's run: Glyph.run)
	public final runs:Array<TextRun>;
	// a tab's stops: every TAB_SIZE spaces from the line's start (CSS's tab-size)
	public static inline var TAB_SIZE = 8;
	// (each tab's glyph index: the distance between its stops)
	var tabs:Null<Map<Int, Float>> = null;

	// lineHeight: a multiple of the size; runs: parts of the text in other
	// fonts and line heights (in order, not overlapping), the rest in fonts.
	// A line is as high as CSS makes its line box: the paragraph's own font
	// and each run on it, each centred in its line height (half the leading
	// above, half below) on the common baseline
	// whether lines were cut (by maxLines: the last one; by cut: each too
	// wide), ending in an ellipsis
	public var truncated(default, null) = false;

	// maxLines: at most so many lines (0: any), the last ending in an
	// ellipsis that fits the width when more were cut, as CSS's line-clamp;
	// letterSpacing and wordSpacing: pixels after each character and on each
	// space, as CSS adds them (outside the runs, which have their own);
	// base: each paragraph's direction (0 left to right, 1 right to left, as
	// CSS's direction sets it; -1: from its first strong character); cut:
	// each line wider than it given up at its end until an ellipsis after it
	// fits (CSS's text-overflow: ellipsis; NaN: none)
	public function new(text:String, fonts:FontSet, lineHeight:Float, maxWidth:Float, ?runs:Array<TextRun>, maxLines = 0, letterSpacing = 0.0,
			wordSpacing = 0.0, base = -1, cut = Math.NaN) {
		this.text = text;
		this.fonts = fonts;
		this.runs = runs == null ? [] : runs;
		this.lineHeight = fonts.size * lineHeight;
		var a = fonts.ascent, d = fonts.descent;
		baseline = (this.lineHeight - (a + d)) / 2 + a;
		var glyphs = shape(text, fonts, this.runs, letterSpacing);
		space(glyphs, letterSpacing, wordSpacing);
		for (i in 0...glyphs.length)
			if (glyphs[i].cp == 9) {
				if (tabs == null) tabs = new Map();
				tabs.set(i, glyphs[i].advance);
			}
		bidi(glyphs, base);
		minWidth = minContent(glyphs);
		breakLines(glyphs, maxWidth);
		if (maxLines > 0 && lines.length > maxLines) {
			lines.resize(maxLines);
			ellipsize(lines[maxLines - 1], maxWidth);
		}
		if (!Math.isNaN(cut))
			for (l in lines)
				if (l.width > cut + 1e-6) ellipsize(l, cut);
	}

	// a line's end given up (its trailing spaces, then characters) until an
	// ellipsis after it fits the width
	function ellipsize(l:TextLine, maxWidth:Float) {
		truncated = true;
		var gs = l.glyphs;
		var rtl = l.bidi && l.base & 1 == 1;
		// (the logical end: the right in a left-to-right line, the left in a right-to-left one)
		inline function endGlyph():Null<Glyph>
			return gs.length == 0 ? null : rtl ? gs[0] : gs[gs.length - 1];
		inline function dropEnd()
			if (rtl) gs.shift() else gs.pop();
		var last = endGlyph();
		var set = last == null || last.run < 0 ? fonts : runs[last.run].fonts;
		var f = set.faceFor(0x2026);
		var e = new Glyph();
		e.cp = 0x2026;
		e.font = f;
		e.id = f.glyph(0x2026);
		e.advance = f.advance(e.id) * set.scale(f);
		e.run = last == null ? -1 : last.run;
		e.level = rtl ? 1 : 0;
		while (gs.length > 0 && isSpace(endGlyph().cp))
			dropEnd();
		// (characters given up one by one: a space they leave at the end stays, as Chromium leaves it)
		if (!Math.isNaN(maxWidth)) {
			var used = 0.0;
			for (g in gs)
				used += g.advance;
			while (gs.length > 0 && used + e.advance > maxWidth + 1e-6) {
				used -= endGlyph().advance;
				dropEnd();
			}
		}
		var endAt = l.start;
		for (g in gs)
			if (g.cluster + g.length > endAt) endAt = g.cluster + g.length;
		e.cluster = endAt;
		e.length = 0;
		if (rtl) gs.unshift(e) else gs.push(e);
		var x = 0.0;
		for (g in gs) {
			g.x = x;
			x += g.advance;
		}
		l.end = endAt;
		l.width = l.advance = x;
		width = 0;
		height = 0;
		for (k in lines) {
			if (k.width > width) width = k.width;
			height += k.height;
		}
	}

	// --- shaping ---

	// justified to width (text-align: justify): each line but the last and
	// those a hard break ends gets the room it has left shared among its
	// spaces (not its trailing ones), as Chromium shares it; a line with no
	// space stays as it is. Its glyphs move, so that carets, hits and
	// selections follow.
	public function justify(width:Float) {
		if (Math.isNaN(width)) return;
		for (k in 0...lines.length) {
			var l = lines[k];
			if (k == lines.length - 1 || l.width >= width) continue;
			// (the logical order: a hard break at its end, its last character that is not a space)
			var last = -1, hard = false;
			for (g in l.glyphs) {
				if (g.cp == 10 || g.cp == 13) hard = true else if (!isSpace(g.cp) && g.cluster > last) last = g.cluster;
			}
			if (hard || last < 0) continue;
			var spaces = 0;
			for (g in l.glyphs)
				if (isSpace(g.cp) && g.cp != 10 && g.cluster < last) spaces++;
			if (spaces == 0) continue;
			var extra = (width - l.width) / spaces, shift = 0.0;
			// (in visual order: what follows a widened space moves right)
			for (g in l.glyphs) {
				g.x += shift;
				if (isSpace(g.cp) && g.cp != 10 && g.cluster < last) {
					g.advance += extra;
					shift += extra;
				}
			}
			l.width = width;
			l.advance += shift;
		}
		this.width = 0;
		for (l in lines)
			if (l.width > this.width) this.width = l.width;
	}

	// letter and word spacing: after each character (a mark, a hidden or
	// zero-width glyph takes none) and on each space, the run's or the paragraph's
	function space(gs:Array<Glyph>, letter:Float, word:Float) {
		for (g in gs) {
			if (g.hidden || g.cp == 10 || g.cp == 13 || g.attach != null) continue;
			var l = g.run < 0 ? letter : runs[g.run].letterSpacing, w = g.run < 0 ? word : runs[g.run].wordSpacing;
			if (l == 0 && w == 0) continue;
			// (a tab: TAB_SIZE spaces, each with both)
			if (g.cp == 9) g.advance += TAB_SIZE * (l + w) else if (g.advance > 0 || g.parts > 1) g.advance += l * (g.parts > 1 ? g.parts : 1);
			if (g.cp == 32 || g.cp == 0xA0) g.advance += w;
		}
	}

	static function shape(text:String, base:FontSet, runs:Array<TextRun>, letterSpacing:Float):Array<Glyph> {
		var out:Array<Glyph> = [];
		var i = 0, n = text.length, count = 0;
		// (the run of each unit: the current one, moved along)
		var run = -1, next = 0;
		inline function setOf(g:Glyph):FontSet
			return g.run < 0 ? base : runs[g.run].fonts;
		// (at most a glyph per UTF-16 unit: allocated once, cut to the count after)
		out.resize(n);
		var emoji = emojiClusters(text);
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
			while (next < runs.length && runs[next].start <= i) {
				run = next;
				next++;
			}
			if (run >= 0 && i >= runs[run].end) run = -1;
			var fonts = run < 0 ? base : runs[run].fonts;
			// (a mark composed with the character before it when that one's face has the composition, as HarfBuzz does)
			if (count > 0 && c >= 0x300 && Bidi.classOf(c) == Bidi.NSM && out[count - 1].run == run) {
				var p = out[count - 1], k = Compose.pair(p.cp, c);
				if (k > 0 && p.font.glyph(k) != 0) {
					p.cp = k;
					p.id = p.font.glyph(k);
					p.length += len;
					i += len;
					continue;
				}
			}
			var g = new Glyph();
			g.cp = c;
			g.cluster = i;
			g.length = len;
			g.run = run;
			if (c == 10 || c == 13) {
				g.font = fonts.primary;
				g.id = 0;
			} else {
				// (in an emoji's sequence: a colour face; a variation selector or joiner keeps the face before it, its run unbroken)
				var f = c == 9 ? fonts.primary : emoji != null && emoji[i] ? (ignorable(c) && count > 0 ? out[count - 1].font : fonts.emojiFaceFor(c)) : fonts.faceFor(c);
				g.font = f;
				g.id = c == 9 ? f.glyph(32) : f.glyph(c);
			}
			out[count++] = g;
			i += len;
		}
		out.resize(count);
		// (Arabic's forms and ligatures: other glyphs; a colour font's sequences: one glyph)
		out = Arabic.shape(out);
		out = ligatures(out, runs, letterSpacing);
		if (emoji != null) out = colorLigatures(out);
		for (g in out)
			if (ignorable(g.cp)) g.hidden = true;
		for (g in out) {
			var c = g.cp;
			if (c == 10 || c == 13) {
				g.advance = 0;
			} else {
				var f = g.font, fonts = setOf(g);
				g.advance = g.hidden ? 0 : (f.bitmapsOnly ? f.advanceAt(g.id, fonts.size) : f.advance(g.id) * fonts.scale(f)) * (c == 9 ? TAB_SIZE : 1);
				if (prev != null && prev.font == f && prev.run == g.run && prev.cp != 10) prev.advance += f.kerning(prev.id, g.id) * fonts.scale(f);
			}
			prev = g;
		}
		marks(out, base, runs);
		return out;
	}

	// the standard ligatures (GSUB's liga and clig lookups for the script, in
	// the lookup list's order) on runs of one face, as Chromium applies them
	// by default: not Arabic's (its own), a colour face's or across lines,
	// and none where letters are spaced (CSS turns them off with
	// letter-spacing). A ligature's caret positions are its characters'
	// equal parts.
	static function ligatures(gs:Array<Glyph>, runs:Array<TextRun>, letterSpacing:Float):Array<Glyph> {
		var n = gs.length;
		// (the glyphs that may take part: their ids, else -1, which no ligature has;
		// none when no face has these lookups)
		var ids:Null<Array<Int>> = null;
		var lastFont:Null<FontFile> = null, lastScript = "", lastLookups:Array<Int> = [], starts:Null<haxe.io.Bytes> = null;
		for (k in 0...n) {
			var g = gs[k];
			var spaced = (g.run < 0 ? letterSpacing : runs[g.run].letterSpacing) != 0;
			var ok = g.font != null && g.cp != 10 && g.cp != 13 && g.cp != 9 && !g.font.hasColor && !g.font.bitmapsOnly && !spaced && !Arabic.isArabic(g.cp);
			if (ok && ids == null) {
				var sc = script(g.cp);
				if (g.font != lastFont || sc != lastScript) {
					lastFont = g.font;
					lastScript = sc;
					lastLookups = g.font.ligatureLookups(sc);
				}
				if (lastLookups.length == 0) continue;
				ids = [];
				ids.resize(n);
				for (j in 0...k)
					ids[j] = -1;
			}
			if (ids != null) ids[k] = ok ? g.id : -1;
		}
		if (ids == null) return gs;
		var out:Null<Array<Glyph>> = null;
		var i = 0;
		while (i < n) {
			var g = gs[i], merged = false;
			if (ids[i] >= 0 && i + 1 < n && ids[i + 1] >= 0) {
				var f = g.font, sc = script(g.cp);
				if (f != lastFont || sc != lastScript || starts == null) {
					lastFont = f;
					lastScript = sc;
					lastLookups = f.ligatureLookups(sc);
					starts = f.ligatureStarts(lastLookups);
				}
				// (a glyph no ligature begins with: none tried)
				if (ids[i] < starts.length && starts.get(ids[i]) != 0) for (l in lastLookups) {
					var lig = f.ligature(l, ids, i);
					if (lig.count < 2) continue;
					// (its parts in this face and run)
					var same = true;
					for (k in i + 1...i + lig.count)
						if (gs[k].font != f || gs[k].run != g.run) same = false;
					if (!same) continue;
					if (out == null) out = gs.slice(0, i);
					var last = gs[i + lig.count - 1];
					g.id = lig.glyph;
					g.length = last.cluster + last.length - g.cluster;
					g.parts = g.length;
					out.push(g);
					i += lig.count;
					merged = true;
					break;
				}
			}
			if (merged) continue;
			if (out != null) out.push(g);
			i++;
		}
		return out == null ? gs : out;
	}

	// which UTF-16 units are in an emoji's sequence (a grapheme cluster with
	// VS16, an emoji modifier, a zero width joiner, regional indicators or a
	// keycap): drawn with a colour face; null: none in the text
	static function emojiClusters(text:String):Null<haxe.ds.Vector<Bool>> {
		var any = false;
		for (i in 0...text.length) {
			var c = StringTools.fastCodeAt(text, i);
			if (c == 0xFE0F || c == 0x200D || c == 0x20E3 || c == 0xD83C || c >= 0x1F1E6 && c <= 0x1F1FF || c >= 0x1F3FB && c <= 0x1F3FF) any = true;
		}
		if (!any) return null;
		var out = new haxe.ds.Vector<Bool>(text.length);
		for (i in 0...text.length)
			out[i] = false;
		var b = Grapheme.boundaries(text);
		for (k in 0...b.length - 1) {
			var marked = false, i = b[k];
			while (i < b[k + 1]) {
				var c = StringTools.fastCodeAt(text, i), len = 1;
				if (c >= 0xD800 && c < 0xDC00 && i + 1 < text.length) {
					c = 0x10000 + ((c - 0xD800) << 10) + (StringTools.fastCodeAt(text, i + 1) - 0xDC00);
					len = 2;
				}
				if (c == 0xFE0F || c == 0x200D || c == 0x20E3 || c >= 0x1F1E6 && c <= 0x1F1FF || c >= 0x1F3FB && c <= 0x1F3FF) marked = true;
				i += len;
			}
			if (marked)
				for (j in b[k]...b[k + 1])
					out[j] = true;
		}
		return out;
	}

	// a colour font's sequences (its ccmp ligatures: a person and a skin tone,
	// a family joined by zero width joiners, a flag) as one glyph
	static function colorLigatures(gs:Array<Glyph>):Array<Glyph> {
		var out:Array<Glyph> = [];
		var i = 0, n = gs.length;
		while (i < n) {
			var g = gs[i], f = g.font;
			if (f != null && f.hasColor && g.cp != 10) {
				var j = i;
				while (j < n && gs[j].font == f && gs[j].cp != 10)
					j++;
				if (j - i > 1 && !(g.cp >= 0xFE00 && g.cp <= 0xFE0F)) {
					// (variation selectors skipped in the match, as HarfBuzz skips them; taken into the ligature)
					var keep = [for (k in i...j) if (!(gs[k].cp >= 0xFE00 && gs[k].cp <= 0xFE0F)) k];
					var ids = [for (k in keep) gs[k].id];
					var merged = false;
					for (l in f.gsubLookups("DFLT", "ccmp")) {
						var lig = f.ligature(l, ids, 0);
						if (lig.count > 1) {
							var end = keep[lig.count - 1] + 1;
							while (end < j && gs[end].cp >= 0xFE00 && gs[end].cp <= 0xFE0F)
								end++;
							g.id = lig.glyph;
							var last = gs[end - 1];
							g.length = last.cluster + last.length - g.cluster;
							out.push(g);
							i = end;
							merged = true;
							break;
						}
					}
					if (merged) continue;
				}
			}
			out.push(g);
			i++;
		}
		return out;
	}

	// default ignorable characters (variation selectors, joiners, tags...): not drawn, no advance, as HarfBuzz hides them
	static inline function ignorable(c:Int):Bool
		return c >= 0xFE00 && c <= 0xFE0F || c >= 0x200B && c <= 0x200F || c >= 0x2060 && c <= 0x2064 || c >= 0xE0000 && c <= 0xE0FFF || c == 0x34F
			|| c >= 0x180B && c <= 0x180D || c == 0xAD;

	// GPOS's mark positioning (the features mark and mkmk, for the base's
	// script), as HarfBuzz applies it: a glyph a lookup covers attached to
	// the glyph before it that is not a mark (or that ligature's last
	// component), or to the mark just before it, drawn at the anchors'
	// offset; marks (GDEF's, else Unicode's nonspacing marks) take no advance
	static function marks(gs:Array<Glyph>, own:FontSet, runs:Array<TextRun>) {
		// (which glyphs are marks: only they attach, the others are passed over)
		var mark = [for (g in gs) g.font != null && g.cp != 10 && g.cp != 13 && isMark(g)];
		for (i in 0...gs.length) {
			if (!mark[i]) continue;
			var g = gs[i], f = g.font;
			g.advance = 0;
			var b = i - 1;
			while (b >= 0 && gs[b].font == f && mark[b])
				b--;
			if (b < 0 || gs[b].font != f || gs[b].cp == 10) continue;
			var base = gs[b], prev = gs[i - 1];
			var component = base.parts > 1 ? base.parts - 1 : -1;
			for (l in f.markLookups(script(base.cp))) {
				var a = f.markAttachment(l, base.id, component, prev.font == f && mark[i - 1] ? prev.id : -1, g.id);
				if (a == null) continue;
				var s = (g.run < 0 ? own : runs[g.run].fonts).scale(f);
				g.attach = a.toPrev ? prev : base;
				g.ax = a.x * s;
				g.ay = -a.y * s;
			}
		}
	}

	static inline function isMark(g:Glyph):Bool
		return g.font.hasGlyphClasses ? g.font.glyphClass(g.id) == 3 : Bidi.classOf(g.cp) == Bidi.NSM;

	// the OpenType script tag of a base character, for its features
	static function script(c:Int):String {
		if (Arabic.isArabic(c)) return "arab";
		if (c >= 0x590 && c <= 0x5FF) return "hebr";
		if (c >= 0x370 && c <= 0x3FF) return "grek";
		if (c >= 0x400 && c <= 0x52F) return "cyrl";
		return "latn";
	}

	// the glyphs' bidi levels, by paragraph (between "\n"s), when any is
	// written right to left or the base is: mirrored brackets, kerning on the
	// visual side
	function bidi(gs:Array<Glyph>, base:Int) {
		var cps = [for (g in gs) g.cp];
		if (base != 1 && !Bidi.hasRtl(cps)) return;
		var start = 0, first = true;
		while (start <= gs.length) {
			var end = start;
			while (end < gs.length && gs[end].cp != 10)
				end++;
			var r = Bidi.levels(cps.slice(start, end), base);
			if (first) direction = r.base;
			first = false;
			for (i in start...end)
				gs[i].level = r.levels[i - start];
			if (end < gs.length) gs[end].level = r.base;
			paragraphLevels.push({start: start, end: end, base: r.base});
			start = end + 1;
		}
		for (i in 0...gs.length) {
			var g = gs[i];
			if (g.level & 1 == 0) continue;
			var m = Bidi.mirror(g.cp);
			if (m != g.cp) {
				var id = g.font.glyph(m);
				if (id != 0) g.id = id;
			}
			// (a right-to-left pair's kerning: on its left glyph, the second)
			if (i > 0 && gs[i - 1].level & 1 == 1 && gs[i - 1].font == g.font && gs[i - 1].run == g.run && gs[i - 1].cp != 10) {
				var p = gs[i - 1], k = g.font.kerning(p.id, g.id) * (g.run < 0 ? fonts : runs[g.run].fonts).scale(g.font);
				p.advance -= k;
				g.advance += k;
			}
		}
		hasBidi = true;
	}

	var hasBidi = false;
	final paragraphLevels:Array<{start:Int, end:Int, base:Int}> = [];

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
		// (most text: letters before letters, the tests below all false)
		if (p < 0x2010 && c < 0x2E80) return p == 32 || p == 9 || p == 0x2D || p == 0x2F;
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
		height = 0;
		for (l in lines)
			height += l.height;
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
				// (a tab: to its next stop from the line's start, the next but one if that is
				// closer than half a space, as CSS has it)
				if (g.cp == 9 && tabs != null) {
					var t = tabs.get(i), next = (Math.floor(w / t + 1e-9) + 1) * t;
					if (next - w < t / TAB_SIZE / 2) next += t;
					g.advance = next - w;
				}
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
		// (its line box: the paragraph's strut and each run on it, on one baseline)
		var above = baseline, below = lineHeight - baseline;
		var seen = new Map<Int, Bool>();
		for (i in start...end) {
			var r = gs[i].run;
			if (r < 0 || seen.exists(r)) continue;
			seen.set(r, true);
			var f = runs[r].fonts, lh = f.size * runs[r].lineHeight, half = (lh - (f.ascent + f.descent)) / 2;
			if (f.ascent + half > above) above = f.ascent + half;
			if (f.descent + half > below) below = f.descent + half;
		}
		l.height = above + below;
		l.baseline = above;
		l.top = lines.length == 0 ? 0 : lines[lines.length - 1].top + lines[lines.length - 1].height;
		var x = 0.0, visible = 0.0;
		l.glyphs.resize(end - start);
		if (hasBidi && end > start) {
			// in visual order (its paragraph's base level for its trailing spaces)
			var base = 0;
			for (p in paragraphLevels)
				if (start >= p.start && start <= p.end) base = p.base;
			l.base = base;
			var cps = [for (g in gs) g.cp], lv = [for (g in gs) g.level];
			var order = Bidi.reorder(cps, lv, base, start, end);
			// (a right-to-left base's marks before it, as HarfBuzz leaves them: at its origin, unattached)
			var k = 0;
			for (i in order) {
				var g = gs[i];
				g.x = x;
				l.glyphs[k++] = g;
				x += g.advance;
			}
			// (without the spaces at the line's logical end)
			var trailing = 0.0, e = end - 1;
			while (e >= start && isSpace(gs[e].cp)) {
				trailing += gs[e].advance;
				e--;
			}
			visible = x - trailing;
		} else
			for (i in start...end) {
				var g = gs[i];
				g.x = x;
				l.glyphs[i - start] = g;
				x += g.advance;
				if (!isSpace(g.cp)) visible = x;
			}
		// (marks: drawn on the glyph they are attached to, logical order putting it first)
		for (i in start...end) {
			var g = gs[i], a = g.attach;
			if (a == null || a.cluster < gs[start].cluster) continue;
			g.dx = a.x + a.dx + g.ax - g.x;
			g.dy = a.dy + g.ay;
		}
		l.width = visible;
		l.advance = x;
		l.start = start < end ? gs[start].cluster : emptyAt != null ? emptyAt : (start < gs.length ? gs[start].cluster : text.length);
		l.end = start < end ? gs[end - 1].cluster + gs[end - 1].length : l.start;
		l.bidi = hasBidi;
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
		if (l.bidi) return {x: bidiCaret(l, index), y: l.top, line: k};
		var x = 0.0;
		for (g in l.glyphs) {
			if (g.cluster >= index) break;
			// (inside a ligature: by its characters' equal parts)
			if (g.parts > 1 && index < g.cluster + g.length) {
				x = g.x + g.advance * (index - g.cluster) / g.parts;
				break;
			}
			x = g.x + g.advance;
		}
		if (index <= l.start) x = 0;
		return {x: x, y: l.top, line: k};
	}

	// the caret before index in a line placed by the bidi algorithm: its
	// character's leading edge (the left of a left-to-right glyph, the right
	// of a right-to-left one), else the trailing edge of the one before
	function bidiCaret(l:TextLine, index:Int):Float {
		var lead:Null<Glyph> = null, trail:Null<Glyph> = null;
		for (g in l.glyphs) {
			if (index >= g.cluster && index < g.cluster + g.length) lead = g;
			if (g.cluster + g.length == index) trail = g;
		}
		if (lead != null) {
			var f = lead.parts > 1 ? (index - lead.cluster) / lead.parts : 0.0;
			return lead.level & 1 == 1 ? lead.x + lead.advance * (1 - f) : lead.x + lead.advance * f;
		}
		if (trail != null) return trail.level & 1 == 1 ? trail.x : trail.x + trail.advance;
		return l.base & 1 == 1 ? l.advance : 0;
	}

	// the index nearest to x in such a line: before or after the glyph under
	// it, by its half and its direction
	function bidiHit(l:TextLine, x:Float):Int {
		if (l.glyphs.length == 0) return l.start;
		for (g in l.glyphs)
			if (g.advance > 0 && x < g.x + g.advance) {
				if (g.parts > 1) {
					var f = (x - g.x) / g.advance;
					var k = Math.round((g.level & 1 == 1 ? 1 - f : f) * g.parts);
					return g.cluster + k;
				}
				var left = x < g.x + g.advance / 2, rtl = g.level & 1 == 1;
				return left != rtl ? g.cluster : g.cluster + g.length;
			}
		var last = l.glyphs[l.glyphs.length - 1];
		return last.level & 1 == 1 ? last.cluster : last.cluster + last.length;
	}

	// what the characters start...end cover: each line's runs of selected
	// glyphs in visual order (one run on a line of one direction), with its
	// top; a ligature partly selected by its parts
	public function selection(start:Int, end:Int):Array<{x:Float, y:Float, width:Float}> {
		var out = [];
		if (end <= start) return out;
		for (l in lines) {
			if (l.end <= start || l.start >= end) continue;
			var x0 = 0.0, x1 = 0.0, open = false;
			for (g in l.glyphs) {
				var a = g.x, b = g.x + g.advance;
				var s = g.cluster, e = g.cluster + g.length;
				var inside = s < end && e > start && g.cp != 10;
				if (inside && g.parts > 1 && (s < start || e > end)) {
					// (part of a ligature: its characters by equal parts, from its leading edge)
					var f0 = (Math.max(start, s) - s) / g.parts, f1 = (Math.min(end, e) - s) / g.parts;
					if (g.level & 1 == 1) {
						a = g.x + g.advance * (1 - f1);
						b = g.x + g.advance * (1 - f0);
					} else {
						a = g.x + g.advance * f0;
						b = g.x + g.advance * f1;
					}
				}
				if (inside && g.advance > 0) {
					if (open && Math.abs(a - x1) < 1e-6) x1 = b else {
						if (open) out.push({x: x0, y: l.top, width: x1 - x0});
						x0 = a;
						x1 = b;
						open = true;
					}
				} else if (!inside && g.advance > 0 && open) {
					out.push({x: x0, y: l.top, width: x1 - x0});
					open = false;
				}
			}
			if (open) out.push({x: x0, y: l.top, width: x1 - x0});
		}
		return out;
	}

	// the lines a decoration of the characters start...end draws (kind: 0
	// underline, 1 line-through, 2 overline), placed as Chromium places
	// text-decoration's auto lines in the font of the run at start (else the
	// paragraph's), snapped to the pixels of scale: a tenth of the size
	// thick; an underline a gap of half that below the baseline, a
	// line-through centred a third of the ascent above it, an overline its
	// thickness above the ascent. On each line, not past a left-to-right
	// line's trailing spaces: rectangles, each with its line's width (to align it)
	public function decoration(start:Int, end:Int, kind:Int, scale = 1.0):Array<{x:Float, y:Float, width:Float, height:Float, lineWidth:Float}> {
		var set = fonts;
		if (runs != null)
			for (r in runs)
				if (r.start <= start && start < r.end) set = r.fonts;
		var f = set.primary, size = set.size * scale;
		var t = Math.max(1, Math.round(size / 10)), ascent = f.ascender * size / f.unitsPerEm;
		var out = [];
		for (r in selection(start, end)) {
			var line:Null<TextLine> = null;
			for (l in lines)
				if (l.top == r.y) line = l;
			if (line == null) continue;
			var x0 = r.x, x1 = r.x + r.width;
			// (a left-to-right line's trailing spaces: not decorated)
			if (line.base == 0 && x1 > line.width) x1 = line.width;
			if (x1 <= x0) continue;
			var b = Math.round((line.top + line.baseline) * scale);
			var top = switch kind {
				case 1: Math.round(b - ascent / 3 - t / 2);
				case 2: Math.round(b - ascent - t);
				case _: b + Math.max(1, Math.ceil(t / 2));
			}
			out.push({x: x0, y: top / scale, width: x1 - x0, height: t / scale, lineWidth: line.width});
		}
		return out;
	}

	// the character index nearest to (x, y)
	public function hit(x:Float, y:Float):Int {
		var k = 0;
		while (k < lines.length - 1 && y >= lines[k].top + lines[k].height)
			k++;
		var l = lines[k];
		if (l.bidi) return bidiHit(l, x);
		for (g in l.glyphs) {
			if (g.cp == 10) break;
			// (a ligature: the nearest of its characters' boundaries)
			if (g.parts > 1 && x < g.x + g.advance) return g.cluster + Math.round(Math.max(0, x - g.x) / g.advance * g.parts);
			// (a mark, no advance of its own: not between it and its base)
			if (g.advance > 0 && x < g.x + g.advance / 2) return g.cluster;
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
	// the characters a ligature shows (each one UTF-16 unit), the caret placed between them by equal parts
	public var parts = 1;
	// its bidi level (odd: right to left)
	public var level = 0;
	// not drawn (a default ignorable character: a variation selector, a joiner)
	public var hidden = false;
	// its run in the layout (TextLayout.runs; -1: the paragraph's own font)
	public var run = -1;
	// where it is drawn from its place (pixels, y down): a mark on its base by GPOS's anchors
	public var dx(get, set):Float;
	public var dy(get, set):Float;
	// (a mark: the glyph it is attached to, and its offset from that glyph's origin)
	public var attach(get, set):Null<Glyph>;
	public var ax(get, set):Float;
	public var ay(get, set):Float;

	// (those five: in a GlyphMark made when one is set, marks being few)
	var mark:Null<GlyphMark> = null;

	public function new() {}

	inline function get_dx():Float
		return mark == null ? 0.0 : mark.dx;

	function set_dx(v:Float):Float {
		if (mark == null) {
			if (v == 0) return v;
			mark = new GlyphMark();
		}
		return mark.dx = v;
	}

	inline function get_dy():Float
		return mark == null ? 0.0 : mark.dy;

	function set_dy(v:Float):Float {
		if (mark == null) {
			if (v == 0) return v;
			mark = new GlyphMark();
		}
		return mark.dy = v;
	}

	inline function get_attach():Null<Glyph>
		return mark == null ? null : mark.attach;

	function set_attach(v:Null<Glyph>):Null<Glyph> {
		if (mark == null) {
			if (v == null) return v;
			mark = new GlyphMark();
		}
		return mark.attach = v;
	}

	inline function get_ax():Float
		return mark == null ? 0.0 : mark.ax;

	function set_ax(v:Float):Float {
		if (mark == null) {
			if (v == 0) return v;
			mark = new GlyphMark();
		}
		return mark.ax = v;
	}

	inline function get_ay():Float
		return mark == null ? 0.0 : mark.ay;

	function set_ay(v:Float):Float {
		if (mark == null) {
			if (v == 0) return v;
			mark = new GlyphMark();
		}
		return mark.ay = v;
	}
}

private class GlyphMark {
	public var dx:Float = 0.0;
	public var dy:Float = 0.0;
	public var attach:Null<Glyph> = null;
	public var ax:Float = 0.0;
	public var ay:Float = 0.0;

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
	// its height and its baseline below its top
	public var height = 0.0;
	public var baseline = 0.0;
	// its glyphs in visual order by the bidi algorithm, its paragraph's base level
	public var bidi = false;
	public var base = 0;

	public function new() {}
}
