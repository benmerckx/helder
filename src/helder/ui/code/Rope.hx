package helder.ui.code;

// A code editor's text: a rope of chunks (each at most MAX UTF-16 units,
// never splitting a surrogate pair), each with its length, its UTF-8
// length and its line breaks, and their prefix sums kept from the first
// chunk an edit touched: an edit rebuilds one or two chunks (a few KB, not
// the file), an offset's line and a line's start are binary searches over
// the chunks then a search in one, and UTF-16 offsets (the String's, the
// editor's) map to UTF-8 bytes (helder.view.Source's, a language
// server's) and back the same way. Lines end with "\n" ("\r\n" is the
// owner's to normalise: CodeModel does on load).
class Rope {
	// (a chunk's size: an edit's rebuilt chunk split above MAX, joined to its next below MIN)
	public static inline var MAX = 1024;
	static inline var MIN = 256;

	final chunks:Array<String> = [];
	final lens:Array<Int> = [];
	final u8s:Array<Int> = [];
	// (each chunk's line breaks, offsets in it; null: not counted yet)
	final breaks:Array<Null<Array<Int>>> = [];
	final nls:Array<Int> = [];
	// (the sums of the chunks before each: UTF-16 length, line breaks, UTF-8 length; valid below prefixValid)
	final preLen:Array<Int> = [];
	final preNl:Array<Int> = [];
	final pre8:Array<Int> = [];
	var prefixValid = 0;
	// (toString's, until an edit)
	var whole:Null<String> = null;

	// UTF-16 units, lines (breaks + 1), UTF-8 bytes
	public var length(default, null) = 0;
	public var lineCount(default, null) = 1;
	public var utf8Length(default, null) = 0;
	// bumped by each edit
	public var version(default, null) = 0;

	public function new(text = "")
		set(text);

	// the whole text replaced
	public function set(text:String) {
		chunks.resize(0);
		lens.resize(0);
		u8s.resize(0);
		breaks.resize(0);
		nls.resize(0);
		prefixValid = 0;
		length = utf8Length = 0;
		lineCount = 1;
		var pieces = split(text);
		for (p in pieces)
			pushChunk(chunks.length, p);
		if (chunks.length == 0) pushChunk(0, "");
		whole = text;
		version++;
	}

	public function toString():String {
		if (whole == null) whole = chunks.join("");
		return whole;
	}

	// (text in pieces of at most MAX, a surrogate pair kept whole)
	static function split(text:String):Array<String> {
		var out = [], at = 0;
		while (at < text.length) {
			var e = at + MAX;
			if (e >= text.length) e = text.length else {
				var c = StringTools.fastCodeAt(text, e - 1);
				if (c >= 0xD800 && c < 0xDC00) e--;
			}
			out.push(text.substring(at, e));
			at = e;
		}
		return out;
	}

	function pushChunk(at:Int, s:String) {
		chunks.insert(at, s);
		lens.insert(at, s.length);
		var b = 0, nl = 0;
		for (k in 0...s.length) {
			var c = StringTools.fastCodeAt(s, k);
			b += c < 0x80 ? 1 : c < 0x800 ? 2 : c >= 0xD800 && c < 0xE000 ? 2 : 3;
			if (c == "\n".code) nl++;
		}
		u8s.insert(at, b);
		nls.insert(at, nl);
		breaks.insert(at, null);
		length += s.length;
		utf8Length += b;
		lineCount += nl;
		if (at < prefixValid) prefixValid = at;
	}

	function removeChunk(at:Int) {
		length -= lens[at];
		utf8Length -= u8s[at];
		lineCount -= nls[at];
		chunks.splice(at, 1);
		lens.splice(at, 1);
		u8s.splice(at, 1);
		nls.splice(at, 1);
		breaks.splice(at, 1);
		if (at < prefixValid) prefixValid = at;
	}

	function ensurePrefix() {
		var c = chunks.length;
		if (prefixValid >= c && preLen.length >= c) return;
		if (preLen.length < c) {
			preLen.resize(c);
			preNl.resize(c);
			pre8.resize(c);
		}
		var k = prefixValid;
		var l = k == 0 ? 0 : preLen[k - 1] + lens[k - 1], nl = k == 0 ? 0 : preNl[k - 1] + nls[k - 1], b = k == 0 ? 0 : pre8[k - 1] + u8s[k - 1];
		while (k < c) {
			preLen[k] = l;
			preNl[k] = nl;
			pre8[k] = b;
			l += lens[k];
			nl += nls[k];
			b += u8s[k];
			k++;
		}
		prefixValid = c;
	}

	// (the chunk holding offset pos: the last one starting at or before it)
	function chunkAt(pos:Int):Int {
		ensurePrefix();
		var lo = 0, hi = chunks.length - 1;
		while (lo < hi) {
			var mid = (lo + hi + 1) >> 1;
			if (preLen[mid] <= pos) lo = mid else hi = mid - 1;
		}
		return lo;
	}

	function breaksOf(c:Int):Array<Int> {
		var b = breaks[c];
		if (b == null) {
			b = [];
			var s = chunks[c];
			for (k in 0...s.length)
				if (StringTools.fastCodeAt(s, k) == "\n".code) b.push(k);
			breaks[c] = b;
		}
		return b;
	}

	// start...end replaced by text (offsets clamped)
	public function replace(start:Int, end:Int, text:String) {
		if (start < 0) start = 0;
		if (end > length) end = length;
		if (end < start) end = start;
		if (start == end && text.length == 0) return;
		var c0 = chunkAt(start), c1 = chunkAt(end);
		var o0 = start - preLen[c0], o1 = end - preLen[c1];
		var merged = chunks[c0].substr(0, o0) + text + chunks[c1].substr(o1);
		// (small: joined with the next)
		if (merged.length < MIN && c1 + 1 < chunks.length) {
			c1++;
			merged += chunks[c1];
		}
		var k = c1;
		while (k >= c0)
			removeChunk(k--);
		if (merged.length == 0) {} else if (merged.length <= MAX) pushChunk(c0, merged) else {
			var at = c0;
			for (p in split(merged))
				pushChunk(at++, p);
		}
		if (chunks.length == 0) pushChunk(0, "");
		whole = null;
		version++;
	}

	public inline function insert(pos:Int, text:String)
		replace(pos, pos, text);

	public inline function delete(start:Int, end:Int)
		replace(start, end, "");

	// the UTF-16 unit at pos (-1: none)
	public function codeAt(pos:Int):Int {
		if (pos < 0 || pos >= length) return -1;
		var c = chunkAt(pos);
		var o = pos - preLen[c];
		// (pos at a chunk's end: the next chunk's first)
		while (o >= lens[c]) {
			o -= lens[c];
			c++;
		}
		return StringTools.fastCodeAt(chunks[c], o);
	}

	public function substring(start:Int, end:Int):String {
		if (start < 0) start = 0;
		if (end > length) end = length;
		if (end <= start) return "";
		if (whole != null) return whole.substring(start, end);
		var c = chunkAt(start), o = start - preLen[c];
		while (o >= lens[c] && c + 1 < chunks.length) {
			o -= lens[c];
			c++;
		}
		if (o + (end - start) <= lens[c]) return chunks[c].substr(o, end - start);
		var b = new StringBuf(), left = end - start;
		while (left > 0 && c < chunks.length) {
			var take = lens[c] - o;
			if (take > left) take = left;
			b.addSub(chunks[c], o, take);
			left -= take;
			o = 0;
			c++;
		}
		return b.toString();
	}

	// the offset where line starts (0-based; past the last: the length)
	public function lineStart(line:Int):Int {
		if (line <= 0) return 0;
		if (line >= lineCount) return length;
		ensurePrefix();
		// (the chunk holding the line-th break: the last with fewer before it)
		var lo = 0, hi = chunks.length - 1;
		while (lo < hi) {
			var mid = (lo + hi + 1) >> 1;
			if (preNl[mid] < line) lo = mid else hi = mid - 1;
		}
		var b = breaksOf(lo);
		return preLen[lo] + b[line - preNl[lo] - 1] + 1;
	}

	// the offset of line's end (before its "\n")
	public function lineEnd(line:Int):Int
		return line + 1 >= lineCount ? length : lineStart(line + 1) - 1;

	// the line of offset pos
	public function lineOf(pos:Int):Int {
		if (pos <= 0) return 0;
		if (pos >= length) return lineCount - 1;
		var c = chunkAt(pos), o = pos - preLen[c];
		var b = breaksOf(c);
		// (breaks before o)
		var lo = 0, hi = b.length;
		while (lo < hi) {
			var mid = (lo + hi) >> 1;
			if (b[mid] < o) lo = mid + 1 else hi = mid;
		}
		return preNl[c] + lo;
	}

	// a line's text, without its "\n"
	public function lineText(line:Int):String
		return substring(lineStart(line), lineEnd(line));

	// the UTF-8 byte offset of UTF-16 offset pos
	public function utf8Of(pos:Int):Int {
		if (pos <= 0) return 0;
		if (pos >= length) return utf8Length;
		var c = chunkAt(pos), o = pos - preLen[c];
		var s = chunks[c], b = pre8[c];
		for (k in 0...o) {
			var u = StringTools.fastCodeAt(s, k);
			b += u < 0x80 ? 1 : u < 0x800 ? 2 : u >= 0xD800 && u < 0xE000 ? 2 : 3;
		}
		return b;
	}

	// the UTF-16 offset of UTF-8 byte offset b (inside a character: its start)
	public function utf16Of(b:Int):Int {
		if (b <= 0) return 0;
		if (b >= utf8Length) return length;
		ensurePrefix();
		var lo = 0, hi = chunks.length - 1;
		while (lo < hi) {
			var mid = (lo + hi + 1) >> 1;
			if (pre8[mid] <= b) lo = mid else hi = mid - 1;
		}
		var s = chunks[lo], at = pre8[lo], k = 0;
		while (k < s.length) {
			var u = StringTools.fastCodeAt(s, k);
			var w = u < 0x80 ? 1 : u < 0x800 ? 2 : u >= 0xD800 && u < 0xDC00 ? 4 : 3;
			if (at + w > b) break;
			at += w;
			k += w == 4 ? 2 : 1;
		}
		return preLen[lo] + k;
	}

	// the chunks (tests: their sizes within MAX)
	public function chunkLengths():Array<Int>
		return lens.copy();
}
