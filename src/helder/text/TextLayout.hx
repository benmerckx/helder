package helder.text;

import haxe.ds.Vector;

// Text laid out in lines: shaped (each character's glyph from the first
// face of the FontSet that has it, advances from hmtx, kerning (GPOS, kern)
// between glyphs of the same face) and broken greedily at break
// opportunities (after spaces and hyphens, around CJK ideographs, kana and
// hangul, after a soft hyphen, shown as a hyphen where the line breaks)
// to fit maxWidth (NaN: only at "\n"); a word wider than a line is cut
// between characters (breaking: as CSS's overflow-wrap and word-break),
// except at a maxWidth of 0: the min-content layout, every opportunity
// taken and no word cut. Text written right to
// left is ordered by the bidirectional algorithm (Bidi: each paragraph's
// levels; each line's glyphs placed in visual order, mirrored brackets on
// right-to-left levels; a base's marks drawn after it), its caret and hits
// by each glyph's direction. The standard ligatures (GSUB's liga and clig)
// are applied as Chromium applies them by default, except where letters
// are spaced; GPOS gives kerning and marks' positions.
// Positions are pixels; character indices are the text's UTF-16 units
// (String indices). Arabic is shaped (Arabic: its letters' joining forms
// and required ligatures, through the font's GSUB).
//
// Its glyphs are flat, as HarfBuzz's glyph infos and positions: the lines'
// in one buffer, each line's in visual order (TextLine.glyphStart to
// glyphEnd), read by index (glyphId, glyphFont, glyphX, glyphAdvance,
// glyphOffsetX and Y, glyphCluster...). Its buffers are kept: wrap lays the
// same shaped text out at another width, reset shapes another text into
// them, neither allocating per glyph (a TextLine is kept and reused too).
@:allow(helder.text.Arabic)
class TextLayout {
	public var text(default, null):String;
	public var fonts(default, null):FontSet;
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
	public var lineHeight(default, null):Float;
	public var baseline(default, null):Float;
	// parts of the text in other fonts (each glyph's run: glyphRun)
	public var runs(default, null):Array<TextRun>;
	// a tab's stops: every TAB_SIZE spaces from the line's start (CSS's tab-size)
	public static inline var TAB_SIZE = 8;
	// where lines may break besides the opportunities, as CSS's
	// overflow-wrap and word-break (breaking: these added up)
	// BREAK_WORD: a word wider than its line cut where it must (else it overflows the line)
	public static inline var BREAK_WORD = 1;
	// ANYWHERE: that, the min-content width as cut (each character's)
	public static inline var ANYWHERE = 2;
	// BREAK_ALL: between any two letters (not before closing punctuation, after opening)
	public static inline var BREAK_ALL = 4;
	// KEEP_ALL: not between CJK characters
	public static inline var KEEP_ALL = 8;
	var breaking = BREAK_WORD;

	// whether lines were cut (by maxLines: the last one; by cut: each too
	// wide), ending in an ellipsis
	public var truncated(default, null) = false;

	// lineHeight: a multiple of the size; runs: parts of the text in other
	// fonts and line heights (in order, not overlapping), the rest in fonts.
	// A line is as high as CSS makes its line box: the paragraph's own font
	// and each run on it, each centred in its line height (half the leading
	// above, half below) on the common baseline.
	// maxLines: at most so many lines (0: any), the last ending in an
	// ellipsis that fits the width when more were cut, as CSS's line-clamp;
	// letterSpacing and wordSpacing: pixels after each character and on each
	// space, as CSS adds them (outside the runs, which have their own);
	// base: each paragraph's direction (0 left to right, 1 right to left, as
	// CSS's direction sets it; -1: from its first strong character); cut:
	// each line wider than it given up at its end until an ellipsis after it
	// fits (CSS's text-overflow: ellipsis; NaN: none); breaking: BREAK_WORD
	// and the others above added up (0: CSS's overflow-wrap: normal)
	public function new(text:String, fonts:FontSet, lineHeight:Float, maxWidth:Float, ?runs:Array<TextRun>, maxLines = 0, letterSpacing = 0.0,
			wordSpacing = 0.0, base = -1, cut = Math.NaN, breaking = BREAK_WORD)
		reset(text, fonts, lineHeight, maxWidth, runs, maxLines, letterSpacing, wordSpacing, base, cut, breaking);

	// another text shaped and laid out into this layout's buffers (as new)
	public function reset(text:String, fonts:FontSet, lineHeight:Float, maxWidth:Float, ?runs:Array<TextRun>, maxLines = 0, letterSpacing = 0.0,
			wordSpacing = 0.0, base = -1, cut = Math.NaN, breaking = BREAK_WORD) {
		this.text = text;
		this.breaking = breaking;
		this.fonts = fonts;
		this.runs = runs != null ? runs : this.runs != null && this.runs.length == 0 ? this.runs : [];
		this.lineHeight = fonts.size * lineHeight;
		var a = fonts.ascent, d = fonts.descent;
		baseline = (this.lineHeight - (a + d)) / 2 + a;
		direction = 0;
		hasBidi = false;
		bidiCps = null;
		bidiLevels = null;
		if (paragraphLevels != null) paragraphLevels.resize(0);
		// (the text's highest UTF-16 unit: below U+0590 nothing right to left,
		// below U+0600 no Arabic, below U+200D no emoji sequences)
		var top = 0;
		for (i in 0...text.length) {
			var c = StringTools.fastCodeAt(text, i);
			if (c > top) top = c;
		}
		shape(letterSpacing, top);
		space(letterSpacing, wordSpacing);
		// (a tab's stops: its advance before bidi's kerning)
		hasTabs = false;
		for (i in 0...count)
			if (lCp[i] == 9) {
				if (!hasTabs) tabRoom();
				tabStop[i] = lAdvance[i];
			}
		if (base == 1 || top >= 0x590) bidi(base);
		shaped = count;
		minWidth = minContent();
		wrap(maxWidth, maxLines, cut);
	}

	// the shaped text in lines again, no wider than maxWidth (maxLines and
	// cut as new's): the lines and glyphs before it are let go (its
	// TextLines reused); justify after it as after new
	public function wrap(maxWidth:Float, maxLines = 0, cut = Math.NaN) {
		count = shaped;
		glyphCount = 0;
		lines.resize(0);
		width = 0;
		height = 0;
		truncated = false;
		placedRoom(shaped + 1);
		if (hasTabs)
			for (i in 0...shaped)
				tabPlaced[i] = lAdvance[i];
		breakLines(maxWidth);
		if (maxLines > 0 && lines.length > maxLines) {
			lines.resize(maxLines);
			glyphCount = lines[maxLines - 1].glyphEnd;
			ellipsize(maxLines - 1, maxWidth);
		}
		if (!Math.isNaN(cut))
			for (k in 0...lines.length)
				if (lines[k].width > cut + 1e-6) ellipsize(k, cut);
	}

	// --- the glyphs, as laid out: glyphCount of them, line by line, each
	// line's in visual order (TextLine.glyphStart to glyphEnd)

	public var glyphCount(default, null) = 0;

	// its glyph id in its font
	public inline function glyphId(i:Int):Int
		return lId[oGlyph[i]];

	public inline function glyphFont(i:Int):FontFile
		return faces[lFace[oGlyph[i]]];

	// the FontSet of its run (the layout's own, or its TextRun's): its size, oblique
	public inline function glyphFontSet(i:Int):FontSet {
		var r = lRun[oGlyph[i]];
		return r < 0 ? fonts : runs[r].fonts;
	}

	// pixels from its line's start to its origin, and to the next glyph's
	public inline function glyphX(i:Int):Float
		return oX[i];

	public inline function glyphAdvance(i:Int):Float
		return oAdvance[i];

	// where it is drawn from its origin (pixels, y down): a mark on its base by GPOS's anchors
	public inline function glyphOffsetX(i:Int):Float
		return hasMarks ? oDx[i] : 0;

	public inline function glyphOffsetY(i:Int):Float
		return hasMarks ? oDy[i] : 0;

	// the characters it shows: its first's index in the text and their length (UTF-16 units)
	public inline function glyphCluster(i:Int):Int
		return lCluster[oGlyph[i]];

	public inline function glyphLength(i:Int):Int
		return lLength[oGlyph[i]];

	// the character (code point) it shows: its cluster's first, a composed character's, a ligature's
	public inline function glyphChar(i:Int):Int
		return lCp[oGlyph[i]];

	// the characters a ligature shows (each one UTF-16 unit; else 1), the caret placed between them by equal parts
	public inline function glyphParts(i:Int):Int
		return parts(oGlyph[i]);

	// its bidi level (odd: right to left)
	public inline function glyphLevel(i:Int):Int
		return lFlags[oGlyph[i]] & LEVEL;

	// its run (runs; -1: the paragraph's own font)
	public inline function glyphRun(i:Int):Int
		return lRun[oGlyph[i]];

	// not drawn (a default ignorable character: a variation selector, a joiner)
	public inline function glyphHidden(i:Int):Bool
		return lFlags[oGlyph[i]] & HIDDEN != 0;

	// --- the buffers: the glyphs shaped in logical order (0 to shaped), then
	// those a wrap adds (a hyphen shown, an ellipsis: to count); the glyphs
	// laid out (0 to glyphCount), each a shaped one (oGlyph) placed

	// (the faces the glyphs are in: lFace)
	final faces:Array<FontFile> = [];
	var lastFace:Null<FontFile> = null;
	var lastFaceIndex = -1;
	var count = 0;
	var shaped = 0;
	var capacity = 0;
	var lFace = NO_INTS;
	var lId = NO_INTS;
	var lCp = NO_INTS;
	var lCluster = NO_INTS;
	var lLength = NO_INTS;
	var lRun = NO_INTS;
	// (its bidi level and these)
	var lFlags = NO_INTS;
	var lAdvance = NO_FLOATS;
	// (with marks: the glyph each is attached to (-1: none), its offset from
	// that glyph's origin, where the last wrap placed it (its index among the
	// glyphs laid out); the offsets of those laid out)
	var hasMarks = false;
	var lPos:Null<Vector<Int>> = null;
	var lAttach:Null<Vector<Int>> = null;
	var lAx:Null<Vector<Float>> = null;
	var lAy:Null<Vector<Float>> = null;
	var oDx:Null<Vector<Float>> = null;
	var oDy:Null<Vector<Float>> = null;
	// (with tabs: each one's advance as shaped, the distance between its
	// stops; as the last wrap placed it, to its stop)
	var hasTabs = false;
	var tabStop:Null<Vector<Float>> = null;
	var tabPlaced:Null<Vector<Float>> = null;
	var placedCapacity = 0;
	var oGlyph = NO_INTS;
	var oX = NO_FLOATS;
	var oAdvance = NO_FLOATS;
	static inline var LEVEL = 0xFF;
	static inline var HIDDEN = 0x100;
	// (a ligature: its parts its characters)
	static inline var LIGATURE = 0x200;
	static inline var MARK = 0x400;
	// (every TextLine made: lines[k] is pool[k])
	final pool:Array<TextLine> = [];
	// (the buffers before the first: none allocated with the layout)
	static final NO_INTS = new Vector<Int>(0);
	static final NO_FLOATS = new Vector<Float>(0);

	function faceIndex(f:FontFile):Int {
		if (f == lastFace) return lastFaceIndex;
		var k = faces.indexOf(f);
		if (k < 0) {
			k = faces.length;
			faces.push(f);
		}
		lastFace = f;
		return lastFaceIndex = k;
	}

	static function moreInts(v:Vector<Int>, n:Int, keep:Int):Vector<Int> {
		var w = new Vector<Int>(n);
		Vector.blit(v, 0, w, 0, keep);
		return w;
	}

	static function moreFloats(v:Vector<Float>, n:Int, keep:Int):Vector<Float> {
		var w = new Vector<Float>(n);
		Vector.blit(v, 0, w, 0, keep);
		return w;
	}

	static function moreBools(v:Vector<Bool>, n:Int, keep:Int):Vector<Bool> {
		var w = new Vector<Bool>(n);
		Vector.blit(v, 0, w, 0, keep);
		return w;
	}

	// (room for n shaped glyphs, the first count kept)
	function room(n:Int) {
		if (n <= capacity) return;
		var c = n > 2 * capacity ? n : 2 * capacity;
		lFace = moreInts(lFace, c, count);
		lId = moreInts(lId, c, count);
		lCp = moreInts(lCp, c, count);
		lCluster = moreInts(lCluster, c, count);
		lLength = moreInts(lLength, c, count);
		lRun = moreInts(lRun, c, count);
		lFlags = moreInts(lFlags, c, count);
		lAdvance = moreFloats(lAdvance, c, count);
		if (lAttach != null) {
			lPos = moreInts(lPos, c, count);
			lAttach = moreInts(lAttach, c, count);
			lAx = moreFloats(lAx, c, count);
			lAy = moreFloats(lAy, c, count);
		}
		if (tabStop != null) {
			tabStop = moreFloats(tabStop, c, count);
			tabPlaced = moreFloats(tabPlaced, c, count);
		}
		capacity = c;
	}

	// (the marks' columns, none attached)
	function markRoom() {
		hasMarks = true;
		if (lAttach == null || lAttach.length < capacity) {
			lPos = new Vector(capacity);
			lAttach = new Vector(capacity);
			lAx = new Vector(capacity);
			lAy = new Vector(capacity);
		}
		if (oDx == null || oDx.length < placedCapacity) {
			oDx = new Vector(placedCapacity);
			oDy = new Vector(placedCapacity);
		}
		for (i in 0...count)
			lAttach[i] = -1;
	}

	function tabRoom() {
		hasTabs = true;
		if (tabStop == null || tabStop.length < capacity) {
			tabStop = new Vector(capacity);
			tabPlaced = new Vector(capacity);
		}
	}

	// (room for n laid out, the first glyphCount kept)
	function placedRoom(n:Int) {
		if (n <= placedCapacity) return;
		var c = n > 2 * placedCapacity ? n : 2 * placedCapacity;
		oGlyph = moreInts(oGlyph, c, glyphCount);
		oX = moreFloats(oX, c, glyphCount);
		oAdvance = moreFloats(oAdvance, c, glyphCount);
		if (oDx != null) {
			oDx = moreFloats(oDx, c, glyphCount);
			oDy = moreFloats(oDy, c, glyphCount);
		}
		placedCapacity = c;
	}

	// (a glyph at the end: a copy of from, or blank)
	function append(from = -1):Int {
		room(count + 1);
		var g = count++;
		if (from >= 0) {
			lFace[g] = lFace[from];
			lId[g] = lId[from];
			lCp[g] = lCp[from];
			lCluster[g] = lCluster[from];
			lLength[g] = lLength[from];
			lRun[g] = lRun[from];
			lFlags[g] = lFlags[from] & ~MARK;
			lAdvance[g] = lAdvance[from];
		} else {
			lRun[g] = -1;
			lFlags[g] = 0;
			lAdvance[g] = 0;
		}
		if (hasMarks) lAttach[g] = -1;
		return g;
	}

	// (the k shaped glyphs from at taken out: a ligature's other parts)
	function remove(at:Int, k:Int) {
		if (k <= 0) return;
		for (i in at...count - k) {
			var j = i + k;
			lFace[i] = lFace[j];
			lId[i] = lId[j];
			lCp[i] = lCp[j];
			lCluster[i] = lCluster[j];
			lLength[i] = lLength[j];
			lRun[i] = lRun[j];
			lFlags[i] = lFlags[j];
			lAdvance[i] = lAdvance[j];
		}
		count -= k;
	}

	inline function parts(g:Int):Int
		return lFlags[g] & LIGATURE != 0 ? lLength[g] : 1;

	inline function level(g:Int):Int
		return lFlags[g] & LEVEL;

	inline function hidden(g:Int):Bool
		return lFlags[g] & HIDDEN != 0;

	// (its advance as the last wrap placed it: a tab's to its stop)
	inline function placed(g:Int):Float
		return hasTabs && lCp[g] == 9 ? tabPlaced[g] : lAdvance[g];

	inline function setOf(run:Int):FontSet
		return run < 0 ? fonts : runs[run].fonts;

	inline function fontOf(g:Int):FontFile
		return faces[lFace[g]];

	function newLine():TextLine {
		var k = lines.length;
		if (k == pool.length) pool.push(new TextLine());
		var l = pool[k];
		l.bidi = false;
		l.base = 0;
		lines.push(l);
		return l;
	}

	// a line's end given up (its trailing spaces, then characters) until an
	// ellipsis after it fits the width
	function ellipsize(k:Int, maxWidth:Float) {
		truncated = true;
		var l = lines[k], s = l.glyphStart, e = l.glyphEnd;
		var rtl = l.bidi && l.base & 1 == 1;
		// (the logical end: the right in a left-to-right line, the left in a right-to-left one)
		var last = s == e ? -1 : oGlyph[rtl ? s : e - 1];
		var set = last < 0 || lRun[last] < 0 ? fonts : runs[lRun[last]].fonts;
		var f = set.faceFor(0x2026);
		var x = append();
		lFace[x] = faceIndex(f);
		lId[x] = f.glyph(0x2026);
		lCp[x] = 0x2026;
		lAdvance[x] = f.advance(lId[x]) * set.scale(f);
		lRun[x] = last < 0 ? -1 : lRun[last];
		lFlags[x] = rtl ? 1 : 0;
		var ea = lAdvance[x];
		while (s < e && isSpace(lCp[oGlyph[rtl ? s : e - 1]]))
			if (rtl) s++ else e--;
		// (characters given up one by one: a space they leave at the end stays, as Chromium leaves it)
		if (!Math.isNaN(maxWidth)) {
			var used = 0.0;
			for (i in s...e)
				used += oAdvance[i];
			while (s < e && used + ea > maxWidth + 1e-6) {
				used -= oAdvance[rtl ? s : e - 1];
				if (rtl) s++ else e--;
			}
		}
		var endAt = l.start;
		for (i in s...e) {
			var g = oGlyph[i];
			if (lCluster[g] + lLength[g] > endAt) endAt = lCluster[g] + lLength[g];
		}
		lCluster[x] = endAt;
		lLength[x] = 0;
		// (the line's glyphs again from its start, the ellipsis before or after them; the next lines' moved)
		var from = l.glyphStart, n = e - s + 1, delta = from + n - l.glyphEnd;
		if (delta > 0) {
			placedRoom(glyphCount + delta);
			move(l.glyphEnd, l.glyphEnd + delta, glyphCount - l.glyphEnd);
			move(s, rtl ? from + 1 : from, e - s);
		} else {
			move(s, rtl ? from + 1 : from, e - s);
			move(l.glyphEnd, l.glyphEnd + delta, glyphCount - l.glyphEnd);
		}
		var at = rtl ? from : from + n - 1;
		oGlyph[at] = x;
		oAdvance[at] = ea;
		if (hasMarks) oDx[at] = oDy[at] = 0;
		var px = 0.0;
		for (i in from...from + n) {
			oX[i] = px;
			px += oAdvance[i];
		}
		glyphCount += delta;
		l.glyphEnd = from + n;
		for (j in k + 1...lines.length) {
			lines[j].glyphStart += delta;
			lines[j].glyphEnd += delta;
		}
		l.end = endAt;
		l.width = l.advance = px;
		width = 0;
		height = 0;
		for (k in lines) {
			if (k.width > width) width = k.width;
			height += k.height;
		}
	}

	// (n laid out glyphs from src to dst)
	function move(src:Int, dst:Int, n:Int) {
		if (src == dst || n <= 0) return;
		inline function one(i:Int, j:Int) {
			oGlyph[j] = oGlyph[i];
			oX[j] = oX[i];
			oAdvance[j] = oAdvance[i];
			if (hasMarks) {
				oDx[j] = oDx[i];
				oDy[j] = oDy[i];
			}
		}
		if (dst < src) {
			for (k in 0...n)
				one(src + k, dst + k);
		} else {
			var k = n;
			while (k-- > 0)
				one(src + k, dst + k);
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
			for (i in l.glyphStart...l.glyphEnd) {
				var g = oGlyph[i], c = lCp[g];
				if (c == 10 || c == 13) hard = true else if (!isSpace(c) && lCluster[g] > last) last = lCluster[g];
			}
			if (hard || last < 0) continue;
			var spaces = 0;
			for (i in l.glyphStart...l.glyphEnd) {
				var g = oGlyph[i], c = lCp[g];
				if (isSpace(c) && c != 10 && lCluster[g] < last) spaces++;
			}
			if (spaces == 0) continue;
			var extra = (width - l.width) / spaces, shift = 0.0;
			// (in visual order: what follows a widened space moves right)
			for (i in l.glyphStart...l.glyphEnd) {
				var g = oGlyph[i], c = lCp[g];
				oX[i] += shift;
				if (isSpace(c) && c != 10 && lCluster[g] < last) {
					oAdvance[i] += extra;
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

	// letter and word spacing: after each glyph (a ligature takes one; a
	// mark, a hidden or zero-width glyph none) and on each space, the run's
	// or the paragraph's, as Chromium adds them; no letter spacing in a
	// cursive script (CSS's: Arabic, Syriac... joined), a space, digit or
	// sign taking the script before it (at a paragraph's start, after it)
	function space(letter:Float, word:Float) {
		var joined = false, k = 0, n = count;
		for (i in 0...n) {
			var c = lCp[i];
			if (c == 10) joined = false;
			// (the script of what has none: the last one's, else the next one's)
			if (!common(c)) joined = cursive(c) else if (i >= k) {
				k = i;
				while (k < n && common(lCp[k]) && lCp[k] != 10)
					k++;
				if (i == 0 || lCp[i - 1] == 10) joined = k < n && cursive(lCp[k]);
			}
			if (hidden(i) || c == 10 || c == 13 || hasMarks && lAttach[i] >= 0) continue;
			var r = lRun[i];
			var l = r < 0 ? letter : runs[r].letterSpacing, w = r < 0 ? word : runs[r].wordSpacing;
			if (l == 0 && w == 0) continue;
			if (joined) l = 0;
			// (a tab: TAB_SIZE spaces, each with both)
			if (c == 9) lAdvance[i] += TAB_SIZE * (l + w) else if (lAdvance[i] > 0 || parts(i) > 1) lAdvance[i] += l;
			if (c == 32 || c == 0xA0) lAdvance[i] += w;
		}
	}

	// (the cursive scripts letter spacing leaves alone: Arabic, Syriac, N'Ko, Mandaic, Mongolian)
	static inline function cursive(c:Int):Bool
		return Arabic.isArabic(c) || c >= 0x700 && c <= 0x74F || c >= 0x7C0 && c <= 0x85F || c >= 0x1800 && c <= 0x18AF;

	// (no script of its own: spaces, digits, punctuation, signs)
	static inline function common(c:Int):Bool
		return c < 0x80 ? !(c >= "A".code && c <= "Z".code || c >= "a".code && c <= "z".code) : c <= 0xBF || c == 0xD7 || c == 0xF7
			|| c >= 0x2000 && c <= 0x2BFF || c >= 0x3000 && c <= 0x303F;

	function shape(letterSpacing:Float, top:Int) {
		var text = text, base = fonts, runs = runs;
		var i = 0, n = text.length;
		count = 0;
		hasMarks = false;
		faces.resize(0);
		lastFace = null;
		// (at most a glyph per UTF-16 unit)
		room(n + 2);
		// (the run of each unit: the current one, moved along)
		var run = -1, next = 0;
		var emoji = top >= 0x200D ? emojiClusters(text) : null;
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
			if (count > 0 && c >= 0x300 && Bidi.classOf(c) == Bidi.NSM && lRun[count - 1] == run) {
				var p = count - 1, k = Compose.pair(lCp[p], c), pf = fontOf(p);
				if (k > 0 && pf.glyph(k) != 0) {
					lCp[p] = k;
					lId[p] = pf.glyph(k);
					lLength[p] += len;
					i += len;
					continue;
				}
			}
			var g = count++;
			lCp[g] = c;
			lCluster[g] = i;
			lLength[g] = len;
			lRun[g] = run;
			lFlags[g] = 0;
			lAdvance[g] = 0;
			if (c == 10 || c == 13) {
				lFace[g] = faceIndex(fonts.primary);
				lId[g] = 0;
			} else {
				// (in an emoji's sequence: a colour face; a variation selector or joiner keeps the face before it, its run unbroken)
				var f = c == 9 ? fonts.primary : emoji != null && emoji[i] ? (ignorable(c) && g > 0 ? fontOf(g - 1) : fonts.emojiFaceFor(c)) : fonts.faceFor(c);
				lFace[g] = faceIndex(f);
				lId[g] = c == 9 ? f.glyph(32) : f.glyph(c);
			}
			i += len;
		}
		// (Arabic's forms and ligatures: other glyphs; a colour font's sequences: one glyph)
		if (top >= 0x600) Arabic.shape(this);
		gsub(letterSpacing);
		if (emoji != null) colorLigatures();
		for (g in 0...count)
			if (ignorable(lCp[g])) lFlags[g] |= HIDDEN;
		var prev = -1;
		for (g in 0...count) {
			var c = lCp[g];
			if (c == 10 || c == 13) {
				lAdvance[g] = 0;
			} else {
				var f = fontOf(g), fonts = setOf(lRun[g]);
				lAdvance[g] = hidden(g) ? 0 : (f.bitmapsOnly ? f.advanceAt(lId[g], fonts.size) : f.advance(lId[g]) * fonts.scale(f)) * (c == 9 ? TAB_SIZE : 1);
				if (prev >= 0 && lFace[prev] == lFace[g] && lRun[prev] == lRun[g] && lCp[prev] != 10 && kerns(fonts))
					lAdvance[prev] += f.kerning(lId[prev], lId[g]) * fonts.scale(f);
			}
			prev = g;
		}
		marks();
	}

	// (kerning unless turned off: FontSet.features' kern 0)
	static inline function kerns(set:FontSet):Bool
		return set.features == null || set.feature("kern") != 0;

	// (a segment's ids, which FontFile's lookups read: from segment in the glyphs; a ligature shortens both)
	var ids:Null<Array<Int>> = null;
	var segment = 0;

	inline function substitutable(g:Int):Bool {
		var c = lCp[g], f = fontOf(g);
		return c != 10 && c != 13 && c != 9 && !f.hasColor && !f.bitmapsOnly && !Arabic.isArabic(c);
	}

	// GSUB's substitutions as Chromium (HarfBuzz) makes them by default (the
	// standard and contextual ligatures and alternates: liga, clig, calt) and
	// those asked for (FontSet.features: tnum, ss01, dlig, liga 0...): on
	// each segment of glyphs of one face, run and script, its lookups
	// (FontFile.gsubLookupsFor) one after another, each over the segment;
	// not Arabic's (its own), a colour face's or across lines. A ligature's
	// caret positions are its characters' equal parts.
	function gsub(letterSpacing:Float) {
		var i = 0;
		while (i < count) {
			if (!substitutable(i)) {
				i++;
				continue;
			}
			var face = lFace[i], f = faces[face], run = lRun[i], sc = script(lCp[i]), j = i + 1;
			while (j < count && lFace[j] == face && lRun[j] == run && substitutable(j) && script(lCp[j]) == sc)
				j++;
			var set = setOf(run);
			var spaced = (run < 0 ? letterSpacing : runs[run].letterSpacing) != 0;
			var lookups = f.gsubLookupsFor(sc, set.features, set.featuresKey, spaced);
			if (lookups.length == 0) {
				i = j;
				continue;
			}
			if (ids == null) ids = [];
			ids.resize(0);
			for (k in i...j)
				ids.push(lId[k]);
			segment = i;
			for (l in lookups) {
				var starts = f.lookupStarts(l.lookup), k = 0;
				while (k < ids.length) {
					var id = ids[k];
					k += id < starts.length && starts.get(id) != 0 ? applyAt(f, l.lookup, l.value, k, 0) : 1;
				}
			}
			i += ids.length;
		}
	}

	// (a lookup at the segment's at: its substitution there, if it has one;
	// how far to go on: past a context's input, else one glyph; a context's
	// lookups applied in it, nested as deep as eight)
	function applyAt(f:FontFile, lookup:Int, value:Int, at:Int, depth:Int):Int {
		switch f.gsubType(lookup) {
			case 1 | 3:
				var id = f.substitute(lookup, ids[at], value);
				ids[at] = id;
				lId[segment + at] = id;
			case 4:
				var lig = f.ligature(lookup, ids, at);
				if (lig.count >= 2) {
					var g = segment + at, last = g + lig.count - 1;
					lId[g] = lig.glyph;
					lLength[g] = lCluster[last] + lLength[last] - lCluster[g];
					lFlags[g] |= LIGATURE;
					ids[at] = lig.glyph;
					remove(g + 1, lig.count - 1);
					for (k in at + 1...ids.length - lig.count + 1)
						ids[k] = ids[k + lig.count - 1];
					ids.resize(ids.length - lig.count + 1);
				}
			case 5 | 6:
				var m = f.context(lookup, ids, at, 0, ids.length);
				if (m == null) return 1;
				var length = m.length, k = 0;
				while (k < m.records.length && depth < 8) {
					var p = at + m.records[k], before = ids.length;
					if (p < ids.length && p < at + length) applyAt(f, m.records[k + 1], 1, p, depth + 1);
					// (a ligature in it: the input shorter by its parts)
					length -= before - ids.length;
					k += 2;
				}
				return length < 1 ? 1 : length;
			case _:
		}
		return 1;
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
	function colorLigatures() {
		inline function selector(c:Int):Bool
			return c >= 0xFE00 && c <= 0xFE0F;
		var i = 0;
		while (i < count) {
			var face = lFace[i], f = faces[face];
			if (f.hasColor && lCp[i] != 10) {
				var j = i;
				while (j < count && lFace[j] == face && lCp[j] != 10)
					j++;
				if (j - i > 1 && !selector(lCp[i])) {
					// (variation selectors skipped in the match, as HarfBuzz skips them; taken into the ligature)
					var keep = [for (k in i...j) if (!selector(lCp[k])) k];
					var ids = [for (k in keep) lId[k]];
					var merged = false;
					for (l in f.gsubLookups("DFLT", "ccmp")) {
						var lig = f.ligature(l, ids, 0);
						if (lig.count > 1) {
							var end = keep[lig.count - 1] + 1;
							while (end < j && selector(lCp[end]))
								end++;
							lId[i] = lig.glyph;
							lLength[i] = lCluster[end - 1] + lLength[end - 1] - lCluster[i];
							remove(i + 1, end - i - 1);
							i++;
							merged = true;
							break;
						}
					}
					if (merged) continue;
				}
			}
			i++;
		}
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
	function marks() {
		// (which glyphs are marks: only they attach, the others are passed over)
		var any = false;
		for (i in 0...count)
			if (lCp[i] != 10 && lCp[i] != 13 && isMark(i)) {
				lFlags[i] |= MARK;
				any = true;
			}
		if (!any) return;
		markRoom();
		inline function mark(g:Int):Bool
			return lFlags[g] & MARK != 0;
		for (i in 0...count) {
			if (!mark(i)) continue;
			var face = lFace[i], f = faces[face];
			lAdvance[i] = 0;
			var b = i - 1;
			while (b >= 0 && lFace[b] == face && mark(b))
				b--;
			if (b < 0 || lFace[b] != face || lCp[b] == 10) continue;
			var prev = i - 1;
			var component = parts(b) > 1 ? parts(b) - 1 : -1;
			for (l in f.markLookups(script(lCp[b]))) {
				var a = f.markAttachment(l, lId[b], component, lFace[prev] == face && mark(prev) ? lId[prev] : -1, lId[i]);
				if (a == null) continue;
				var s = setOf(lRun[i]).scale(f);
				lAttach[i] = a.toPrev ? prev : b;
				lAx[i] = a.x * s;
				lAy[i] = -a.y * s;
			}
		}
	}

	inline function isMark(g:Int):Bool {
		var f = fontOf(g);
		return f.hasGlyphClasses ? f.glyphClass(lId[g]) == 3 : Bidi.classOf(lCp[g]) == Bidi.NSM;
	}

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
	function bidi(base:Int) {
		var n = count;
		var cps = [for (i in 0...n) lCp[i]];
		if (base != 1 && !Bidi.hasRtl(cps)) return;
		var start = 0, first = true;
		if (paragraphLevels == null) paragraphLevels = [];
		while (start <= n) {
			var end = start;
			while (end < n && lCp[end] != 10)
				end++;
			var r = Bidi.levels(cps.slice(start, end), base);
			if (first) direction = r.base;
			first = false;
			for (i in start...end)
				lFlags[i] = lFlags[i] & ~LEVEL | r.levels[i - start];
			if (end < n) lFlags[end] = lFlags[end] & ~LEVEL | r.base;
			paragraphLevels.push({start: start, end: end, base: r.base});
			start = end + 1;
		}
		for (i in 0...n) {
			if (level(i) & 1 == 0) continue;
			var m = Bidi.mirror(lCp[i]);
			if (m != lCp[i]) {
				var id = fontOf(i).glyph(m);
				if (id != 0) lId[i] = id;
			}
			// (a right-to-left pair's kerning: on its left glyph, the second)
			var set = setOf(lRun[i]);
			var p = i - 1;
			if (i > 0 && level(p) & 1 == 1 && lFace[p] == lFace[i] && lRun[p] == lRun[i] && lCp[p] != 10 && kerns(set)) {
				var f = fontOf(i), k = f.kerning(lId[p], lId[i]) * set.scale(f);
				lAdvance[p] -= k;
				lAdvance[i] += k;
			}
		}
		hasBidi = true;
		// (the code points and levels Bidi.reorder takes for each line)
		bidiCps = cps;
		bidiLevels = [for (i in 0...n) level(i)];
	}

	var hasBidi = false;
	var bidiCps:Null<Array<Int>> = null;
	var bidiLevels:Null<Array<Int>> = null;
	var paragraphLevels:Null<Array<{start:Int, end:Int, base:Int}>> = null;

	// --- line breaking ---

	static inline function isSpace(c:Int):Bool
		return c == 32 || c == 9 || c == 0x3000;

	static inline function isCJK(c:Int):Bool
		return (c >= 0x2E80 && c <= 0x9FFF) || (c >= 0xAC00 && c <= 0xD7AF) || (c >= 0xF900 && c <= 0xFAFF) || (c >= 0xFF00 && c <= 0xFFEF)
			|| (c >= 0x20000 && c <= 0x3FFFF);

	// may a line break before glyph i?
	function breakBefore(i:Int):Bool {
		if (i == 0) return false;
		var p = lCp[i - 1], c = lCp[i];
		if (isSpace(c)) return false; // (spaces stay at the end of the line)
		if (p == 0xAD) return true;
		// (most text: letters before letters, the tests below all false)
		if (p < 0x2010 && c < 0x2E80 && breaking & BREAK_ALL == 0) return p == 32 || p == 9 || p == 0x2D || p == 0x2F;
		if (isSpace(p) || p == 0x2D || p == 0x2010 || p == 0x2013 || p == 0x2014 || p == 0x2F) return true;
		if (breaking & BREAK_ALL != 0) return within(i) && !closes(c) && !opens(p);
		return breaking & KEEP_ALL == 0 && (isCJK(p) || isCJK(c));
	}

	// may a word be cut before glyph i (not before a mark or what is not shown)?
	inline function within(i:Int):Bool
		return !hidden(i) && !isMark(i) && lCp[i] != 10;

	// (UAX 14's closing punctuation, infix separators, exclamations and quotes: no break before; opening and quotes: none after)
	static function closes(c:Int):Bool
		return switch c {
			case ")".code | "]".code | "}".code | ",".code | ".".code | ":".code | ";".code | "!".code | "?".code | '"'.code | "'".code | 0x2019 | 0x201D
				| 0x3001 | 0x3002 | 0xFF09 | 0xFF0C | 0xFF0E: true;
			case _: false;
		}

	static function opens(c:Int):Bool
		return switch c {
			case "(".code | "[".code | "{".code | '"'.code | "'".code | 0x2018 | 0x201C | 0xFF08: true;
			case _: false;
		}

	function minContent():Float {
		var widest = 0.0, x = 0.0, visible = 0.0;
		var anywhere = breaking & ANYWHERE != 0;
		for (i in 0...count) {
			var c = lCp[i];
			if (c == 10 || breakBefore(i) || (anywhere && i > 0 && !isSpace(c) && within(i))) {
				// (a soft hyphen broken at: the hyphen shown)
				if (i > 0 && lCp[i - 1] == 0xAD) visible = x + hyphenAdvance(i - 1);
				if (visible > widest) widest = visible;
				x = visible = 0;
				if (c == 10) continue;
			}
			x += lAdvance[i];
			if (!isSpace(c)) visible = x;
		}
		return visible > widest ? visible : widest;
	}

	// the hyphen a soft hyphen shows at a line's end: its face's (U+2010, else "-"), its advance
	function hyphenId(g:Int):Int {
		var f = fontOf(g), id = f.glyph(0x2010);
		return id == 0 ? f.glyph(0x2D) : id;
	}

	function hyphenAdvance(g:Int):Float {
		var f = fontOf(g);
		return f.advance(hyphenId(g)) * setOf(lRun[g]).scale(f);
	}

	function breakLines(maxWidth:Float) {
		var wrap = !Math.isNaN(maxWidth);
		var start = 0, n = shaped;
		while (true) {
			// one hard line: start until "\n" (or the end)
			var end = start;
			while (end < n && lCp[end] != 10)
				end++;
			fill(start, end, wrap ? maxWidth : Math.POSITIVE_INFINITY);
			if (end >= n) break;
			// (after a final "\n": an empty line, filled by the next round)
			start = end + 1;
		}
		if (lines.length == 0) addLine(0, 0);
		height = 0;
		for (l in lines)
			height += l.height;
	}

	// the glyphs start...end (no "\n") in lines no wider than max
	function fill(start:Int, end:Int, max:Float) {
		if (start == end) {
			addLine(start, end, start < shaped ? lCluster[start] : text.length);
			return;
		}
		var lineStart = start;
		while (lineStart < end) {
			var w = 0.0, lastBreak = -1, i = lineStart;
			while (i < end) {
				var c = lCp[i];
				// (after a soft hyphen: only where the hyphen fits too)
				if (i > lineStart && breakBefore(i) && (lCp[i - 1] != 0xAD || w + hyphenAdvance(i - 1) <= max + 1e-3)) lastBreak = i;
				// (a tab: to its next stop from the line's start, the next but one if that is
				// closer than half a space, as CSS has it)
				if (c == 9) {
					var t = tabStop[i], next = (Math.floor(w / t + 1e-9) + 1) * t;
					if (next - w < t / TAB_SIZE / 2) next += t;
					tabPlaced[i] = next - w;
				}
				// (trailing spaces may overflow)
				var a = placed(i);
				if (!isSpace(c) && w + a > max + 1e-3 && i > lineStart) break;
				w += a;
				i++;
			}
			// (at a width of 0, or not to be cut, a word stays whole: up to the next opportunity)
			if ((max <= 0 || breaking & (BREAK_WORD | ANYWHERE) == 0) && lastBreak <= lineStart && i < end) {
				while (i < end && !breakBefore(i))
					i++;
			}
			var cut = i >= end ? end : lastBreak > lineStart ? lastBreak : i;
			// (a word cut: not before a mark or what is not shown)
			if (cut < end && cut > lineStart && !breakBefore(cut))
				while (cut > lineStart + 1 && !within(cut))
					cut--;
			// (broken after a soft hyphen: a hyphen shown there, a glyph of its own)
			var shy = -1, shown = -1;
			if (cut < end && cut > lineStart && lCp[cut - 1] == 0xAD) {
				shy = cut - 1;
				shown = append(shy);
				lId[shown] = hyphenId(shy);
				lAdvance[shown] = hyphenAdvance(shy);
				lFlags[shown] &= ~HIDDEN;
			}
			addLine(lineStart, cut, -1, shy, shown);
			lineStart = cut;
		}
	}

	// (the shaped glyphs start...end as a line; emptyAt: an empty line's
	// index in the text; shy, shown: a soft hyphen shown as the glyph shown)
	function addLine(start:Int, end:Int, emptyAt = -1, shy = -1, shown = -1) {
		var l = newLine();
		// (its line box: the paragraph's strut and each run on it, on one baseline)
		var above = baseline, below = lineHeight - baseline;
		// (each run once: in order in the text)
		var seen = -1;
		if (runs.length > 0) for (i in start...end) {
			var r = lRun[i];
			if (r < 0 || r == seen) continue;
			seen = r;
			var f = runs[r].fonts, lh = f.size * runs[r].lineHeight, half = (lh - (f.ascent + f.descent)) / 2;
			if (f.ascent + half > above) above = f.ascent + half;
			if (f.descent + half > below) below = f.descent + half;
		}
		l.height = above + below;
		l.baseline = above;
		var k = lines.length - 1;
		l.top = k == 0 ? 0 : lines[k - 1].top + lines[k - 1].height;
		var x = 0.0, visible = 0.0, o = glyphCount;
		l.glyphStart = o;
		placedRoom(o + end - start);
		if (hasBidi && end > start) {
			// in visual order (its paragraph's base level for its trailing spaces)
			var base = 0;
			for (p in paragraphLevels)
				if (start >= p.start && start <= p.end) base = p.base;
			l.base = base;
			// (a right-to-left base's marks before it, as HarfBuzz leaves them: at its origin, unattached)
			for (i in Bidi.reorder(bidiCps, bidiLevels, base, start, end)) {
				var g = i == shy ? shown : i;
				var a = placed(g);
				oGlyph[o] = g;
				oX[o] = x;
				oAdvance[o] = a;
				if (hasMarks) lPos[i] = o;
				o++;
				x += a;
			}
			// (without the spaces at the line's logical end)
			var trailing = 0.0, e = end - 1;
			while (e >= start && isSpace(lCp[e])) {
				trailing += placed(e);
				e--;
			}
			visible = x - trailing;
			// (a right-to-left base's trailing spaces, visually first: hung before the line's start, the rest from 0, as Chromium's)
			if (base & 1 == 1 && trailing > 0)
				for (j in l.glyphStart...o)
					oX[j] -= trailing;
		} else
			for (i in start...end) {
				var g = i == shy ? shown : i;
				var a = placed(g);
				oGlyph[o] = g;
				oX[o] = x;
				oAdvance[o] = a;
				if (hasMarks) lPos[i] = o;
				o++;
				x += a;
				if (!isSpace(lCp[g])) visible = x;
			}
		// (marks: drawn on the glyph they are attached to, logical order putting it first)
		if (hasMarks) {
			for (j in l.glyphStart...o)
				oDx[j] = oDy[j] = 0;
			for (i in start...end) {
				var a = lAttach[i];
				if (a < 0 || lCluster[a] < lCluster[start]) continue;
				var pi = lPos[i], pa = lPos[a];
				oDx[pi] = oX[pa] + oDx[pa] + lAx[i] - oX[pi];
				oDy[pi] = oDy[pa] + lAy[i];
			}
		}
		glyphCount = o;
		l.glyphEnd = o;
		l.width = visible;
		l.advance = x;
		l.start = start < end ? lCluster[start] : emptyAt >= 0 ? emptyAt : (start < shaped ? lCluster[start] : text.length);
		l.end = start < end ? lCluster[end - 1] + lLength[end - 1] : l.start;
		l.bidi = hasBidi;
		if (visible > width) width = visible;
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
		for (i in l.glyphStart...l.glyphEnd) {
			var g = oGlyph[i], c = lCluster[g];
			if (c >= index) break;
			// (inside a ligature: by its characters' equal parts)
			if (parts(g) > 1 && index < c + lLength[g]) {
				x = oX[i] + oAdvance[i] * (index - c) / parts(g);
				break;
			}
			x = oX[i] + oAdvance[i];
		}
		if (index <= l.start) x = 0;
		return {x: x, y: l.top, line: k};
	}

	// the caret before index in a line placed by the bidi algorithm: its
	// character's leading edge (the left of a left-to-right glyph, the right
	// of a right-to-left one), else the trailing edge of the one before
	function bidiCaret(l:TextLine, index:Int):Float {
		var lead = -1, trail = -1;
		for (i in l.glyphStart...l.glyphEnd) {
			var g = oGlyph[i], c = lCluster[g];
			if (index >= c && index < c + lLength[g]) lead = i;
			if (c + lLength[g] == index) trail = i;
		}
		if (lead >= 0) {
			var g = oGlyph[lead], f = parts(g) > 1 ? (index - lCluster[g]) / parts(g) : 0.0;
			return level(g) & 1 == 1 ? oX[lead] + oAdvance[lead] * (1 - f) : oX[lead] + oAdvance[lead] * f;
		}
		if (trail >= 0) return level(oGlyph[trail]) & 1 == 1 ? oX[trail] : oX[trail] + oAdvance[trail];
		return l.base & 1 == 1 ? l.advance : 0;
	}

	// the index nearest to x in such a line: before or after the glyph under
	// it, by its half and its direction
	function bidiHit(l:TextLine, x:Float):Int {
		if (l.glyphEnd == l.glyphStart) return l.start;
		for (i in l.glyphStart...l.glyphEnd) {
			var g = oGlyph[i], a = oAdvance[i], gx = oX[i];
			if (a > 0 && x < gx + a) {
				var rtl = level(g) & 1 == 1;
				if (parts(g) > 1) {
					var f = (x - gx) / a;
					var k = Math.round((rtl ? 1 - f : f) * parts(g));
					return lCluster[g] + k;
				}
				var left = x < gx + a / 2;
				return left != rtl ? lCluster[g] : lCluster[g] + lLength[g];
			}
		}
		var last = oGlyph[l.glyphEnd - 1];
		return level(last) & 1 == 1 ? lCluster[last] : lCluster[last] + lLength[last];
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
			for (i in l.glyphStart...l.glyphEnd) {
				var g = oGlyph[i], gx = oX[i], adv = oAdvance[i];
				var a = gx, b = gx + adv;
				var s = lCluster[g], e = s + lLength[g], parts = parts(g);
				var inside = s < end && e > start && lCp[g] != 10;
				if (inside && parts > 1 && (s < start || e > end)) {
					// (part of a ligature: its characters by equal parts, from its leading edge)
					var f0 = (Math.max(start, s) - s) / parts, f1 = (Math.min(end, e) - s) / parts;
					if (level(g) & 1 == 1) {
						a = gx + adv * (1 - f1);
						b = gx + adv * (1 - f0);
					} else {
						a = gx + adv * f0;
						b = gx + adv * f1;
					}
				}
				if (inside && adv > 0) {
					if (open && Math.abs(a - x1) < 1e-6) x1 = b else {
						if (open) out.push({x: x0, y: l.top, width: x1 - x0});
						x0 = a;
						x1 = b;
						open = true;
					}
				} else if (!inside && adv > 0 && open) {
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
	public function decoration(start:Int, end:Int, kind:Int, scale = 1.0, thickness = Math.NaN, offset = Math.NaN):Array<{
		x:Float,
		y:Float,
		width:Float,
		height:Float,
		lineWidth:Float
	}> {
		var set = fonts;
		if (runs != null)
			for (r in runs)
				if (r.start <= start && start < r.end) set = r.fonts;
		var f = set.primary, size = set.size * scale;
		// (thickness and an underline's offset below the baseline: CSS's text-decoration-thickness, text-underline-offset; NaN: auto)
		var t = Math.max(1, Math.round(Math.isNaN(thickness) ? size / 10 : thickness * scale)), ascent = f.ascender * size / f.unitsPerEm;
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
				case _: Math.isNaN(offset) ? b + Math.max(1, Math.ceil(t / 2)) : b + Math.round(offset * scale);
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
		for (i in l.glyphStart...l.glyphEnd) {
			var g = oGlyph[i], gx = oX[i], a = oAdvance[i];
			if (lCp[g] == 10) break;
			// (a ligature: the nearest of its characters' boundaries)
			if (parts(g) > 1 && x < gx + a) return lCluster[g] + Math.round(Math.max(0, x - gx) / a * parts(g));
			// (a mark, no advance of its own: not between it and its base)
			if (a > 0 && x < gx + a / 2) return lCluster[g];
		}
		// (the end of a wrapped line: before its trailing break)
		return l.end;
	}
}

// a line of a TextLayout: its glyphs the layout's glyphStart to glyphEnd
// (in visual order). Kept by the layout and reused when it is laid out again.
class TextLine {
	public var glyphStart = 0;
	public var glyphEnd = 0;
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
