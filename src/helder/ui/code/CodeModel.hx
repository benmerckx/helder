package helder.ui.code;

import helder.syntax.Transaction;

// A selection: anchor (where it started) to head (the caret); goal: the
// column Up and Down keep (-1: the head's)
class Sel {
	public var anchor:Int;
	public var head:Int;
	public var goal:Int = -1;

	public function new(anchor:Int, head:Int) {
		this.anchor = anchor;
		this.head = head;
	}

	public var from(get, never):Int;
	public var to(get, never):Int;

	inline function get_from():Int
		return anchor < head ? anchor : head;

	inline function get_to():Int
		return anchor < head ? head : anchor;

	public inline function empty():Bool
		return anchor == head;

	public function toString():String
		return anchor == head ? '$head' : '$anchor-$head';
}

// A range of the text drawn another way (the studio's "selected on the
// canvas", a search's matches): its background, border and underline (null:
// none), the whole lines it covers or its characters. Its offsets move
// with edits (an insertion at its start or end is outside it).
class Decoration {
	public final id:Int;
	public var start:Int;
	public var end:Int;
	public var background:Null<Color>;
	public var border:Null<Color>;
	public var underline:Null<Color>;
	public var wholeLine:Bool;

	public function new(id:Int, start:Int, end:Int, ?background:Color, ?border:Color, ?underline:Color, wholeLine = false) {
		this.id = id;
		this.start = start;
		this.end = end;
		this.background = background;
		this.border = border;
		this.underline = underline;
		this.wholeLine = wholeLine;
	}
}

// A compiler's message on a range of the text (helder.compiler.service's
// Diagnostic placed: its line and columns as offsets), moving with edits
class CodeDiagnostic {
	public var start:Int;
	public var end:Int;
	// "error", "warning", "info"
	public final severity:String;
	public final message:String;

	public function new(start:Int, end:Int, severity:String, message:String) {
		this.start = start;
		this.end = end;
		this.severity = severity;
		this.message = message;
	}
}

// (an edit applied: its changes against the text before, and the inverse ones against the text after)
private class Step {
	public final changes:Array<Change>;
	public final inverse:Array<Change>;

	public function new(changes, inverse) {
		this.changes = changes;
		this.inverse = inverse;
	}
}

// (an undo's unit: steps, the selections before and after, a run of typing's kind)
private class Group {
	public final steps:Array<Step> = [];
	public final before:Array<Int>;
	public var after:Array<Int>;
	public final kind:Int;
	public var open = true;

	public function new(before, after, kind) {
		this.before = before;
		this.after = after;
		this.kind = kind;
	}
}

// A code editor's document (CodeEditor's, usable without one): its text
// (Rope), its lines' cached texts and highlighting (CodeLanguage, read
// again from an edited line until a line's state is the one it had), its
// selections (several: multi-cursor), the undo history (each command one
// step, a run of typing or of deleting one; undo restores the selections
// too), and the commands the editor's keys and actions run, each on every
// selection: typing with brackets and quotes paired, Enter keeping the
// indentation (and adding one after an opening bracket), Backspace and
// Delete by characters (grapheme clusters) or words, moves by character,
// word, line, page and file, indent and outdent, a line comment toggled,
// lines duplicated and moved, cursors added above, below and at the next
// occurrence, find and replace. Every edit is a list of changes
// (helder.syntax's Change: offsets of the text before, in order), given to
// onChange as they are: a Transaction's.
class CodeModel {
	public static inline var EDIT = 0;
	public static inline var TYPE = 1;
	public static inline var DELETE = 2;

	public final rope = new Rope();
	public var language(default, set):Null<CodeLanguage> = null;
	// the selections, in order and not overlapping; primary: the one the view follows
	public final sels:Array<Sel> = [new Sel(0, 0)];
	public var primary(default, null):Sel;
	public var tabSize = 4;
	// Tab inserts spaces (else a tab); setText guesses from the file
	public var insertSpaces = true;
	// the file's line endings ("\n" or "\r\n"; the text's are "\n")
	public var eol(default, null) = "\n";
	// lines Page Up and Down move by (the view's)
	public var pageLines = 20;
	// each edit's changes (against the text before, in order)
	public var onChange:Null<Array<Change>->Void> = null;
	// bumped by each edit and selection change
	public var version(default, null) = 0;
	public var readOnly = false;

	// (per line: its text (null: not fetched), the state its tokens were read
	// from (-1: none, its text changed), the state after it, its tokens, what
	// the view laid it out as)
	final texts:Array<Null<String>> = [""];
	final tokStart:Array<Int> = [-1];
	final endState:Array<Int> = [-1];
	final tokens:Array<Null<Array<Int>>> = [null];
	@:allow(helder.ui.code) final laid:Array<Null<Paragraph>> = [null];
	final pool:Array<Array<Int>> = [];
	// (lines from which highlighting may be out of date)
	var dirtyFrom = 0;

	final undos:Array<Group> = [];
	final redos:Array<Group> = [];
	// the most undo steps kept
	public var historyLimit = 1000;

	public final decorations:Array<Decoration> = [];
	var nextDecoration = 1;
	public final diagnostics:Array<CodeDiagnostic> = [];

	// (copy's pieces: a paste of as many goes one to each cursor)
	var copied:Null<String> = null;
	var copiedCount = 0;

	public function new(text = "", ?language:CodeLanguage) {
		primary = sels[0];
		this.language = language;
		setText(text);
	}

	function set_language(l:Null<CodeLanguage>):Null<CodeLanguage> {
		language = l;
		for (k in 0...tokStart.length)
			tokStart[k] = -1;
		dirtyFrom = 0;
		for (k in 0...laid.length)
			laid[k] = null;
		version++;
		return l;
	}

	// ---- the text

	// the whole text replaced (its line endings made "\n", eol kept; the
	// indentation guessed; the selection at the start, the history cleared)
	public function setText(text:String) {
		eol = text.indexOf("\r\n") >= 0 ? "\r\n" : "\n";
		if (text.indexOf("\r") >= 0) text = StringTools.replace(StringTools.replace(text, "\r\n", "\n"), "\r", "\n");
		rope.set(text);
		var lines = text.split("\n");
		texts.resize(0);
		tokStart.resize(0);
		endState.resize(0);
		for (t in tokens)
			if (t != null) pool.push(t);
		tokens.resize(0);
		laid.resize(0);
		var tabbed = 0, spaced = 0;
		for (l in lines) {
			texts.push(l);
			tokStart.push(-1);
			endState.push(-1);
			tokens.push(null);
			laid.push(null);
			if (l.length > 0) {
				var c = StringTools.fastCodeAt(l, 0);
				if (c == "\t".code) tabbed++ else if (c == " ".code && l.length > 1 && StringTools.fastCodeAt(l, 1) == " ".code) spaced++;
			}
		}
		if (tabbed + spaced > 0) insertSpaces = spaced > tabbed;
		dirtyFrom = 0;
		sels.resize(1);
		sels[0] = primary = new Sel(0, 0);
		undos.resize(0);
		redos.resize(0);
		decorations.resize(0);
		diagnostics.resize(0);
		version++;
	}

	public inline function text():String
		return rope.toString();

	// the text with the file's line endings
	public function fileText():String
		return eol == "\n" ? rope.toString() : StringTools.replace(rope.toString(), "\n", eol);

	public var length(get, never):Int;

	inline function get_length():Int
		return rope.length;

	public var lineCount(get, never):Int;

	inline function get_lineCount():Int
		return rope.lineCount;

	// a line's text (kept until it changes)
	public function line(i:Int):String {
		var t = texts[i];
		if (t == null) texts[i] = t = rope.lineText(i);
		return t;
	}

	public inline function lineStart(i:Int):Int
		return rope.lineStart(i);

	public inline function lineEnd(i:Int):Int
		return rope.lineEnd(i);

	public inline function lineOf(pos:Int):Int
		return rope.lineOf(pos);

	inline function codeAt(pos:Int):Int
		return rope.codeAt(pos);

	// ---- highlighting

	// line i's tokens (start, end, TokenClass, ... in the line), read by highlight (null: not yet, or no language)
	public function lineTokens(i:Int):Null<Array<Int>>
		return language == null || tokStart[i] < 0 || tokStart[i] != startOf(i) ? null : tokens[i];

	inline function startOf(i:Int):Int
		return i == 0 ? language.startState() : endState[i - 1];

	// whether every line is highlighted
	public function highlighted():Bool
		return language == null || dirtyFrom >= lineCount;

	// the lines up to last highlighted (read from the first that is not, until
	// a line's state is the one it had; then on to the next edited line);
	// at most budget lines read (-1: any): the lines read
	public function highlight(last:Int, budget = -1):Int {
		if (language == null) return 0;
		var n = lineCount, i = dirtyFrom, read = 0;
		if (last >= n) last = n - 1;
		while (i <= last && i < n) {
			var st = startOf(i);
			if (tokStart[i] == st && st >= 0) {
				// (the same as before: the next line that changed)
				i++;
				while (i < n && tokStart[i] == endState[i - 1] && tokStart[i] >= 0)
					i++;
				continue;
			}
			if (budget >= 0 && read >= budget) break;
			var out = tokens[i];
			if (out == null) tokens[i] = out = pool.length > 0 ? pool.pop() : [];
			out.resize(0);
			var end = language.tokenize(line(i), st, out);
			tokStart[i] = st;
			endState[i] = end;
			laid[i] = null;
			read++;
			i++;
		}
		dirtyFrom = i;
		return read;
	}

	// ---- edits

	// changes (against the text now, in order, not overlapping) applied:
	// the selections after (null: the selections mapped through them), the
	// history's kind (TYPE, DELETE: runs joined); false when read only or none
	public function apply(changes:Array<Change>, ?after:Array<Sel>, kind = EDIT, record = true):Bool {
		if (readOnly || changes.length == 0) return false;
		var before = record ? snapshot() : null;
		// (the inverse: each change's new text's range given its old text back)
		var inverse = [], delta = 0;
		for (c in changes) {
			var s = c.start + delta;
			inverse.push(new Change(s, s + c.text.length, rope.substring(c.start, c.end)));
			delta += c.text.length - (c.end - c.start);
		}
		var k = changes.length;
		while (--k >= 0) {
			var c = changes[k];
			replaceLines(c.start, c.end, c.text);
		}
		mapRanges(changes);
		if (after != null) setSels(after, after.length == sels.length ? after[sels.indexOf(primary)] : null) else {
			for (s in sels) {
				s.anchor = map(s.anchor, changes, 1);
				s.head = map(s.head, changes, 1);
			}
			normalize();
		}
		if (record) {
			redos.resize(0);
			var step = new Step(changes, inverse);
			var last = undos.length > 0 ? undos[undos.length - 1] : null;
			if (kind != EDIT && last != null && last.open && last.kind == kind && same(last.after, before)) {
				last.steps.push(step);
				last.after = snapshot();
			} else {
				if (last != null) last.open = false;
				var g = new Group(before, snapshot(), kind);
				g.steps.push(step);
				undos.push(g);
				if (undos.length > historyLimit) undos.shift();
			}
			// (a space or a line ends a run of typing)
			if (kind == TYPE)
				for (c in changes)
					if (c.text.indexOf(" ") >= 0 || c.text.indexOf("\n") >= 0) undos[undos.length - 1].open = false;
		}
		version++;
		if (onChange != null) onChange(changes);
		return true;
	}

	// one change applied to the rope and the lines' arrays
	function replaceLines(start:Int, end:Int, text:String) {
		var l0 = rope.lineOf(start), l1 = rope.lineOf(end);
		rope.replace(start, end, text);
		var added = 0, at = 0;
		while ((at = text.indexOf("\n", at)) >= 0) {
			added++;
			at++;
		}
		var removed = l1 - l0;
		// (the lines' tokens arrays kept for others)
		for (k in l0 + 1...l1 + 1)
			if (tokens[k] != null) pool.push(tokens[k]);
		var len = texts.length;
		splice(texts, l0 + 1, removed, added, null);
		splice(tokStart, l0 + 1, removed, added, -1);
		splice(endState, l0 + 1, removed, added, -1);
		splice(tokens, l0 + 1, removed, added, null);
		splice(laid, l0 + 1, removed, added, null);
		for (k in l0...l0 + added + 1) {
			texts[k] = null;
			tokStart[k] = -1;
			laid[k] = null;
		}
		if (l0 < dirtyFrom) dirtyFrom = l0;
	}

	// (a's entries at...at+remove replaced by add of fill, without allocating)
	static function splice<T>(a:Array<T>, at:Int, remove:Int, add:Int, fill:T) {
		var len = a.length;
		if (add > remove) {
			var extra = add - remove;
			a.resize(len + extra);
			var k = len - 1;
			while (k >= at + remove) {
				a[k + extra] = a[k];
				k--;
			}
		} else if (remove > add) {
			var less = remove - add;
			for (k in at + add...len - less)
				a[k] = a[k + less];
			a.resize(len - less);
		}
		for (k in at...at + add)
			a[k] = fill;
	}

	// where offset pos is after changes (against the text before): inside a
	// replaced range its end; at an insertion, after it (assoc > 0) or before
	public static function map(pos:Int, changes:Array<Change>, assoc:Int):Int {
		var delta = 0;
		for (c in changes) {
			if (pos < c.start || pos == c.start && (c.end > c.start || assoc < 0)) break;
			if (pos < c.end) return c.start + delta + c.text.length;
			delta += c.text.length - (c.end - c.start);
		}
		return pos + delta;
	}

	function mapRanges(changes:Array<Change>) {
		for (d in decorations) {
			d.start = map(d.start, changes, 1);
			d.end = map(d.end, changes, -1);
			if (d.end < d.start) d.end = d.start;
		}
		for (d in diagnostics) {
			d.start = map(d.start, changes, 1);
			d.end = map(d.end, changes, -1);
			if (d.end < d.start) d.end = d.start;
		}
	}

	// ---- selections

	function snapshot():Array<Int> {
		var out = [];
		for (s in sels) {
			out.push(s.anchor);
			out.push(s.head);
		}
		out.push(sels.indexOf(primary));
		return out;
	}

	static function same(a:Array<Int>, b:Array<Int>):Bool {
		if (a.length != b.length) return false;
		for (k in 0...a.length)
			if (a[k] != b[k]) return false;
		return true;
	}

	function restore(snap:Array<Int>) {
		sels.resize(0);
		var k = 0;
		while (k + 1 < snap.length) {
			sels.push(new Sel(clamp(snap[k]), clamp(snap[k + 1])));
			k += 2;
		}
		var p = snap[snap.length - 1];
		primary = sels[p >= 0 && p < sels.length ? p : sels.length - 1];
		normalize();
	}

	inline function clamp(i:Int):Int
		return i < 0 ? 0 : i > rope.length ? rope.length : i;

	// the selections replaced (the last the primary, unless one given)
	public function setSels(list:Array<Sel>, ?primaryOne:Sel) {
		if (list.length == 0) return;
		sels.resize(0);
		for (s in list) {
			s.anchor = clamp(s.anchor);
			s.head = clamp(s.head);
			sels.push(s);
		}
		primary = primaryOne != null && list.indexOf(primaryOne) >= 0 ? primaryOne : list[list.length - 1];
		normalize();
		version++;
	}

	// one selection, anchor to head
	public function select(anchor:Int, head:Int)
		setSels([new Sel(anchor, head)]);

	// a cursor (or selection) added
	public function addSel(anchor:Int, head:Int) {
		var s = new Sel(clamp(anchor), clamp(head));
		sels.push(s);
		primary = s;
		normalize();
		version++;
	}

	// the selections sorted, those that overlap (or cursors at the same place) merged
	public function normalize() {
		haxe.ds.ArraySort.sort(sels, (a, b) -> a.from != b.from ? a.from - b.from : a.to - b.to);
		var k = 1;
		while (k < sels.length) {
			var a = sels[k - 1], b = sels[k];
			if (b.from < a.to || b.from == a.from && (a.empty() || b.empty()) || b.from == a.to && (b.empty() || a.empty())) {
				var from = a.from < b.from ? a.from : b.from, to = a.to > b.to ? a.to : b.to;
				var forward = b.head >= b.anchor;
				a.anchor = forward ? from : to;
				a.head = forward ? to : from;
				if (primary == b) primary = a;
				sels.splice(k, 1);
			} else k++;
		}
		if (sels.indexOf(primary) < 0) primary = sels[sels.length - 1];
	}

	// only the primary selection kept (Escape)
	public function collapse():Bool {
		if (sels.length == 1) {
			if (primary.empty()) return false;
			primary.anchor = primary.head;
			version++;
			return true;
		}
		setSels([primary]);
		return true;
	}

	public function selectAll()
		select(0, rope.length);

	// ---- moves

	// where a move takes head (the selection extended or not)
	function moveAll(to:Sel->Int, extend:Bool, keepGoal = false) {
		for (s in sels) {
			var h = to(s);
			s.head = clamp(h);
			if (!extend) s.anchor = s.head;
			if (!keepGoal) s.goal = -1;
		}
		normalize();
		closeRun();
		version++;
	}

	// (a move ends a run of typing)
	inline function closeRun()
		if (undos.length > 0) undos[undos.length - 1].open = false;

	public function moveLeft(extend = false)
		moveAll(s -> !extend && !s.empty() ? s.from : prevChar(s.head), extend);

	public function moveRight(extend = false)
		moveAll(s -> !extend && !s.empty() ? s.to : nextChar(s.head), extend);

	public function moveWordLeft(extend = false)
		moveAll(s -> wordLeft(s.head), extend);

	public function moveWordRight(extend = false)
		moveAll(s -> wordRight(s.head), extend);

	// Home: to the line's first non-blank character, from there to the line's start
	public function moveLineStart(extend = false)
		moveAll(s -> {
			var l = lineOf(s.head), st = lineStart(l), t = line(l), k = 0;
			while (k < t.length && isBlank(StringTools.fastCodeAt(t, k)))
				k++;
			s.head == st + k && k > 0 ? st : st + k;
		}, extend);

	public function moveLineEnd(extend = false)
		moveAll(s -> lineEnd(lineOf(s.head)), extend);

	public function moveDocStart(extend = false)
		moveAll(_ -> 0, extend);

	public function moveDocEnd(extend = false)
		moveAll(_ -> rope.length, extend);

	public function moveUp(extend = false)
		moveLines(-1, extend);

	public function moveDown(extend = false)
		moveLines(1, extend);

	public function movePageUp(extend = false)
		moveLines(-pageLines, extend);

	public function movePageDown(extend = false)
		moveLines(pageLines, extend);

	// by lines, keeping the column (the goal, set by the first)
	function moveLines(by:Int, extend:Bool) {
		for (s in sels) {
			var l = lineOf(s.head);
			if (s.goal < 0) s.goal = column(s.head);
			var target = l + by;
			if (target < 0) s.head = 0 else if (target >= lineCount) s.head = rope.length else s.head = offsetAtColumn(target, s.goal);
			if (!extend) s.anchor = s.head;
		}
		normalize();
		closeRun();
		version++;
	}

	// the column of offset pos on its line (tabs to the next stop)
	public function column(pos:Int):Int {
		var l = lineOf(pos), t = line(l), n = pos - lineStart(l), col = 0;
		for (k in 0...n) {
			var c = StringTools.fastCodeAt(t, k);
			if (c == "\t".code) col += tabSize - col % tabSize else if (!(c >= 0xDC00 && c < 0xE000)) col++;
		}
		return col;
	}

	// the offset at a column of a line (its end when shorter)
	public function offsetAtColumn(l:Int, col:Int):Int {
		var t = line(l), c = 0, k = 0;
		while (k < t.length && c < col) {
			var u = StringTools.fastCodeAt(t, k);
			var w = u == "\t".code ? tabSize - c % tabSize : 1;
			if (c + w > col && c + w - col > col - c) break;
			c += w;
			k++;
			if (u >= 0xD800 && u < 0xDC00 && k < t.length) k++;
		}
		return lineStart(l) + k;
	}

	// the offset a grapheme cluster before pos (a line's start: the line before's end)
	public function prevChar(pos:Int):Int {
		if (pos <= 0) return 0;
		var l = lineOf(pos), st = lineStart(l);
		if (pos == st) return pos - 1;
		return st + helder.text.Grapheme.prev(line(l), pos - st);
	}

	public function nextChar(pos:Int):Int {
		if (pos >= rope.length) return rope.length;
		var l = lineOf(pos), st = lineStart(l), t = line(l);
		if (pos - st >= t.length) return pos + 1;
		return st + helder.text.Grapheme.next(t, pos - st);
	}

	static inline function isBlank(c:Int):Bool
		return c == " ".code || c == "\t".code;

	public static inline function isWordChar(c:Int):Bool
		return c >= "a".code && c <= "z".code || c >= "A".code && c <= "Z".code || c >= "0".code && c <= "9".code || c == "_".code || c == "$".code
			|| c > 0x7F && c != 0xA0 && c != 0x3000;

	// (a character's kind for word moves: 0 blank, 1 word, 2 other, 3 a line break)
	inline function kindAt(pos:Int):Int {
		var c = codeAt(pos);
		return c == "\n".code ? 3 : isBlank(c) ? 0 : isWordChar(c) ? 1 : 2;
	}

	// the start of the word (or run of punctuation) before pos, over blanks; a line's start stops it
	public function wordLeft(pos:Int):Int {
		if (pos <= 0) return 0;
		if (codeAt(pos - 1) == "\n".code) return pos - 1;
		while (pos > 0 && kindAt(pos - 1) == 0)
			pos--;
		if (pos > 0 && kindAt(pos - 1) != 3) {
			var k = kindAt(pos - 1);
			while (pos > 0 && kindAt(pos - 1) == k)
				pos--;
		}
		return pos;
	}

	public function wordRight(pos:Int):Int {
		var n = rope.length;
		if (pos >= n) return n;
		if (codeAt(pos) == "\n".code) return pos + 1;
		while (pos < n && kindAt(pos) == 0)
			pos++;
		if (pos < n && kindAt(pos) != 3) {
			var k = kindAt(pos);
			while (pos < n && kindAt(pos) == k)
				pos++;
		}
		return pos;
	}

	// the word around pos (or the run of other characters), start and end
	public function wordAt(pos:Int):{start:Int, end:Int} {
		var n = rope.length;
		var k = pos < n && kindAt(pos) != 3 ? kindAt(pos) : pos > 0 && kindAt(pos - 1) != 3 ? kindAt(pos - 1) : -1;
		if (k < 0) return {start: pos, end: pos};
		// (a word next to the caret wins over blanks)
		if (k != 1 && pos > 0 && kindAt(pos - 1) == 1) k = 1;
		var a = pos, b = pos;
		while (a > 0 && kindAt(a - 1) == k)
			a--;
		while (b < n && kindAt(b) == k)
			b++;
		return {start: a, end: b};
	}

	// ---- typing

	static inline function closerOf(c:Int):Int
		return c == "(".code ? ")".code : c == "[".code ? "]".code : c == "{".code ? "}".code : c == '"'.code || c == "'".code || c == "`".code ? c : -1;

	// text typed at every selection: a bracket or quote paired (around a
	// selection, or before a blank, a closer or the line's end), a closer
	// typed over the same one after the caret; a run of typing is one undo
	public function type(s:String) {
		if (readOnly) return;
		var changes = [], after = [], delta = 0;
		var c = s.length == 1 ? StringTools.fastCodeAt(s, 0) : -1;
		var closer = closerOf(c);
		for (sel in sels) {
			var from = sel.from, to = sel.to, next = codeAt(to);
			var quote = c == '"'.code || c == "'".code || c == "`".code;
			if (sel.empty() && c >= 0 && (c == ")".code || c == "]".code || c == "}".code || quote) && next == c) {
				// (over the closer already there)
				var p = from + delta + 1;
				after.push(new Sel(p, p));
				continue;
			}
			if (closer >= 0 && !sel.empty()) {
				var inner = rope.substring(from, to);
				changes.push(new Change(from, to, s + inner + String.fromCharCode(closer)));
				after.push(new Sel(from + delta + 1, from + delta + 1 + inner.length));
				delta += 2;
				continue;
			}
			var prev = from > 0 ? codeAt(from - 1) : -1;
			var pair = closer >= 0 && (next < 0 || next == "\n".code || isBlank(next) || next == ")".code || next == "]".code || next == "}".code
				|| next == ",".code || next == ";".code) && !(quote && (isWordChar(prev) || prev == c));
			var text = pair ? s + String.fromCharCode(closer) : s;
			changes.push(new Change(from, to, text));
			var p = from + delta + s.length;
			after.push(new Sel(p, p));
			delta += text.length - (to - from);
		}
		if (changes.length == 0) {
			setSels(after, after[sels.indexOf(primary)]);
			return;
		}
		apply(changes, after, TYPE);
	}

	// Enter: a line break at every selection, the line's indentation kept
	// (one more after an opening bracket or tag; between a pair, the
	// closer on a line of its own)
	public function newline() {
		var changes = [], after = [], delta = 0;
		for (sel in sels) {
			var from = sel.from, to = sel.to;
			var l = lineOf(from), st = lineStart(l), t = line(l);
			var k = 0;
			while (k < t.length && k < from - st && isBlank(StringTools.fastCodeAt(t, k)))
				k++;
			var indent = t.substr(0, k);
			// (the character before, over blanks; the one after)
			var b = from - 1;
			while (b >= st && isBlank(codeAt(b)))
				b--;
			var before = b >= st ? codeAt(b) : -1, next = codeAt(to);
			var opens = before == "{".code || before == "(".code || before == "[".code || before == ">".code && next == "<".code && codeAt(to + 1) == "/".code;
			var text:String, caret:Int;
			if (opens) {
				var inner = indent + unit();
				var closes = next == "}".code || next == ")".code || next == "]".code || next == "<".code;
				text = "\n" + inner + (closes ? "\n" + indent : "");
				caret = 1 + inner.length;
			} else {
				text = "\n" + indent;
				caret = text.length;
			}
			// (blanks before the caret on its line dropped)
			var cut = from;
			while (cut > st && isBlank(codeAt(cut - 1)) && cut - st > k)
				cut--;
			changes.push(new Change(cut, to, text));
			var p = cut + delta + caret;
			after.push(new Sel(p, p));
			delta += text.length - (to - cut);
		}
		apply(changes, after, EDIT);
	}

	// the indentation one level adds: a tab or tabSize spaces
	public function unit():String
		return insertSpaces ? StringTools.lpad("", " ", tabSize) : "\t";

	// Backspace: the selections' text, else the cluster (or word) before
	// each caret; between a pair just typed, both; in a line's indentation
	// of spaces, back to the previous stop
	public function backspace(word = false) {
		var changes = [], after = [], delta = 0;
		for (sel in sels) {
			var from = sel.from, to = sel.to;
			if (sel.empty()) {
				if (from == 0) {
					after.push(new Sel(from + delta, from + delta));
					continue;
				}
				var prev = codeAt(from - 1), next = codeAt(from);
				if (word) from = wordLeft(from) else if (closerOf(prev) >= 0 && closerOf(prev) == next) {
					to = from + 1;
					from--;
				} else if (prev == " ".code && insertSpaces) {
					// (in the indentation: to the stop before)
					var l = lineOf(from), st = lineStart(l), t = line(l), k = 0;
					while (k < from - st && StringTools.fastCodeAt(t, k) == " ".code)
						k++;
					if (k == from - st) {
						var col = k, stop = (col - 1) - (col - 1) % tabSize;
						from = st + stop;
					} else from = prevChar(from);
				} else from = prevChar(from);
			}
			if (overlaps(changes, from)) {
				after.push(new Sel(from + delta, from + delta));
				continue;
			}
			changes.push(new Change(from, to, ""));
			after.push(new Sel(from + delta, from + delta));
			delta -= to - from;
		}
		if (changes.length == 0) return;
		apply(changes, after, DELETE);
	}

	// (a change would start inside the last one: two carets deleting the same character)
	static function overlaps(changes:Array<Change>, from:Int):Bool
		return changes.length > 0 && from < changes[changes.length - 1].end;

	// Delete: the selections' text, else the cluster (or word) after each caret
	public function deleteForward(word = false) {
		var changes = [], after = [], delta = 0;
		for (sel in sels) {
			var from = sel.from, to = sel.to;
			if (sel.empty()) to = word ? wordRight(from) : nextChar(from);
			if (to == from || overlaps(changes, from)) {
				after.push(new Sel(from + delta, from + delta));
				continue;
			}
			changes.push(new Change(from, to, ""));
			after.push(new Sel(from + delta, from + delta));
			delta -= to - from;
		}
		if (changes.length == 0) return;
		apply(changes, after, DELETE);
	}

	// text over every selection (a paste: as many pieces as cursors, one each)
	public function insert(text:String, kind = EDIT) {
		var pieces = copied == text && copiedCount == sels.length && sels.length > 1 ? text.split("\n") : null;
		var changes = [], after = [], delta = 0;
		for (k in 0...sels.length) {
			var sel = sels[k], t = pieces != null ? pieces[k] : text;
			changes.push(new Change(sel.from, sel.to, t));
			var p = sel.from + delta + t.length;
			after.push(new Sel(p, p));
			delta += t.length - (sel.to - sel.from);
		}
		apply(changes, after, kind);
	}

	// the selections' text, one a line (empty selections: their whole lines)
	public function copyText():String {
		var parts = [];
		var allEmpty = true;
		for (s in sels)
			if (!s.empty()) allEmpty = false;
		if (allEmpty) {
			var lastLine = -1;
			for (s in sels) {
				var l = lineOf(s.head);
				if (l == lastLine) continue;
				lastLine = l;
				parts.push(line(l));
			}
			var t = parts.join("\n") + "\n";
			copied = t;
			copiedCount = -1;
			return t;
		}
		for (s in sels)
			parts.push(rope.substring(s.from, s.to));
		var t = parts.join("\n");
		copied = t;
		copiedCount = parts.length;
		return t;
	}

	// copy, then the selections deleted (empty ones: their lines)
	public function cutText():String {
		var t = copyText();
		var allEmpty = true;
		for (s in sels)
			if (!s.empty()) allEmpty = false;
		if (allEmpty) deleteLines() else deleteForward();
		return t;
	}

	// the lines of every selection deleted
	public function deleteLines() {
		var blocks = lineBlocks(), changes = [];
		for (b in blocks) {
			var st = lineStart(b.first), e = b.last + 1 < lineCount ? lineStart(b.last + 1) : rope.length;
			if (b.last + 1 >= lineCount && st > 0) st--;
			changes.push(new Change(st, e, ""));
		}
		apply(changes, null, EDIT);
		for (s in sels) {
			s.anchor = s.head = lineStart(lineOf(s.head));
		}
	}

	// ---- lines

	// (the lines the selections cover, merged where they touch: a selection
	// ending at a line's start leaves that line out)
	function lineBlocks():Array<{first:Int, last:Int}> {
		var out:Array<{first:Int, last:Int}> = [];
		for (s in sels) {
			var a = lineOf(s.from), b = lineOf(s.to);
			if (b > a && s.to == lineStart(b)) b--;
			if (out.length > 0 && a <= out[out.length - 1].last + 1) {
				if (b > out[out.length - 1].last) out[out.length - 1].last = b;
			} else out.push({first: a, last: b});
		}
		return out;
	}

	// Tab: the selected lines indented, else an indentation at each caret
	public function indent() {
		var multi = false;
		for (s in sels)
			if (!s.empty()) multi = true;
		if (!multi) {
			var changes = [], after = [], delta = 0;
			for (s in sels) {
				var t = insertSpaces ? StringTools.lpad("", " ", tabSize - column(s.head) % tabSize) : "\t";
				changes.push(new Change(s.head, s.head, t));
				var p = s.head + delta + t.length;
				after.push(new Sel(p, p));
				delta += t.length;
			}
			apply(changes, after, TYPE);
			return;
		}
		var changes = [], u = unit();
		for (b in lineBlocks())
			for (l in b.first...b.last + 1)
				if (line(l).length > 0) changes.push(new Change(lineStart(l), lineStart(l), u));
		apply(changes, null, EDIT);
	}

	// Shift+Tab: one indentation off the selected lines (or the carets')
	public function outdent() {
		var changes = [];
		for (b in lineBlocks())
			for (l in b.first...b.last + 1) {
				var t = line(l), k = 0;
				if (t.length > 0 && StringTools.fastCodeAt(t, 0) == "\t".code) k = 1 else
					while (k < tabSize && k < t.length && StringTools.fastCodeAt(t, k) == " ".code)
						k++;
				if (k > 0) changes.push(new Change(lineStart(l), lineStart(l) + k, ""));
			}
		apply(changes, null, EDIT);
	}

	// the selected lines commented with the language's line comment, or
	// uncommented when every one (but blank ones) is
	public function toggleComment() {
		var prefix = language == null ? "//" : language.lineComment();
		if (prefix == null) return;
		var blocks = lineBlocks(), all = true, minIndent = 1 << 30, any = false;
		for (b in blocks)
			for (l in b.first...b.last + 1) {
				var t = line(l), k = 0;
				while (k < t.length && isBlank(StringTools.fastCodeAt(t, k)))
					k++;
				if (k == t.length) continue;
				any = true;
				if (k < minIndent) minIndent = k;
				if (t.substr(k, prefix.length) != prefix) all = false;
			}
		if (!any) return;
		var changes = [];
		for (b in blocks)
			for (l in b.first...b.last + 1) {
				var t = line(l), k = 0;
				while (k < t.length && isBlank(StringTools.fastCodeAt(t, k)))
					k++;
				if (k == t.length) continue;
				var st = lineStart(l);
				if (all) {
					var e = k + prefix.length;
					if (e < t.length && StringTools.fastCodeAt(t, e) == " ".code) e++;
					changes.push(new Change(st + k, st + e, ""));
				} else changes.push(new Change(st + minIndent, st + minIndent, prefix + " "));
			}
		apply(changes, null, EDIT);
	}

	// each selection's lines copied below them (up: above), the selections on the copies
	public function duplicateLines(up = false) {
		var changes = [], moves = [];
		for (b in lineBlocks()) {
			var st = lineStart(b.first), e = lineEnd(b.last);
			var block = rope.substring(st, e);
			// (down: the copy after the block, the selections moved onto it)
			changes.push(up ? new Change(st, st, block + "\n") : new Change(e, e, "\n" + block));
			moves.push({first: b.first, last: b.last, by: up ? 0 : block.length + 1});
		}
		var after = [], delta = 0, k = 0;
		for (s in sels) {
			while (k < moves.length && lineOf(s.from) > moves[k].last)
				delta += changes[k++].text.length;
			var by = k < moves.length ? moves[k].by : 0;
			var ns = new Sel(s.anchor + delta + by, s.head + delta + by);
			after.push(ns);
		}
		apply(changes, after, EDIT);
	}

	// each selection's lines moved a line up (or down), the selections with them; false at the file's edge
	public function moveLines_(down:Bool):Bool {
		var blocks = lineBlocks();
		if (blocks.length == 0) return false;
		if (!down && blocks[0].first == 0 || down && blocks[blocks.length - 1].last >= lineCount - 1) return false;
		var changes = [], shifts = [];
		for (b in blocks) {
			var st = lineStart(b.first), e = lineEnd(b.last), block = rope.substring(st, e);
			if (down) {
				var other = line(b.last + 1), oe = lineEnd(b.last + 1);
				changes.push(new Change(st, oe, other + "\n" + block));
				shifts.push(other.length + 1);
			} else {
				var os = lineStart(b.first - 1), other = line(b.first - 1);
				changes.push(new Change(os, e, block + "\n" + other));
				shifts.push(-(other.length + 1));
			}
		}
		var after = [], k = 0;
		for (s in sels) {
			while (k + 1 < blocks.length && lineOf(s.from) > blocks[k].last)
				k++;
			after.push(new Sel(s.anchor + shifts[k], s.head + shifts[k]));
		}
		apply(changes, after, EDIT);
		return true;
	}

	public inline function moveLinesUp():Bool
		return moveLines_(false);

	public inline function moveLinesDown():Bool
		return moveLines_(true);

	// ---- cursors

	// a cursor on the line above (below) each one, at its column
	public function addCursorVertical(by:Int) {
		var added = [];
		for (s in sels) {
			var l = lineOf(s.head) + by;
			if (l < 0 || l >= lineCount) continue;
			var col = s.goal >= 0 ? s.goal : column(s.head);
			var p = offsetAtColumn(l, col);
			var ns = new Sel(p, p);
			ns.goal = col;
			added.push(ns);
		}
		for (s in added)
			sels.push(s);
		if (added.length > 0) primary = by < 0 ? added[0] : added[added.length - 1];
		normalize();
		version++;
	}

	// Secondary+D: the word at the primary caret selected; then the next
	// occurrence of the selected text added as a selection (from the last
	// one on, around the end); false when there is no other
	public function addNextOccurrence(caseSensitive = true):Bool {
		var p = primary;
		if (p.empty()) {
			var w = wordAt(p.head);
			if (w.end == w.start) return false;
			p.anchor = w.start;
			p.head = w.end;
			normalize();
			version++;
			return true;
		}
		var needle = rope.substring(p.from, p.to);
		var hay = rope.toString();
		if (!caseSensitive) {
			needle = needle.toLowerCase();
			hay = hay.toLowerCase();
		}
		var last = sels[sels.length - 1].to;
		var at = hay.indexOf(needle, last);
		if (at < 0) at = hay.indexOf(needle);
		while (at >= 0) {
			var taken = false;
			for (s in sels)
				if (s.from == at && s.to == at + needle.length) taken = true;
			if (!taken) break;
			at = hay.indexOf(needle, at + 1);
			if (at < 0) break;
		}
		if (at < 0) return false;
		addSel(at, at + needle.length);
		return true;
	}

	// ---- find and replace

	// the matches of query (start, end pairs, in order): plain text (case
	// sensitive or not, whole words or not) or a regular expression
	public function findAll(query:String, caseSensitive = false, wholeWord = false, regex = false):Array<Int> {
		var out = [];
		if (query == "") return out;
		var hay = rope.toString();
		if (regex) {
			var re = try new EReg(query, caseSensitive ? "g" : "gi") catch (e:Dynamic) null;
			if (re == null) return out;
			var at = 0;
			while (at <= hay.length && re.matchSub(hay, at)) {
				var m = re.matchedPos();
				if (m.len == 0) {
					at = m.pos + 1;
					continue;
				}
				if (!wholeWord || isWholeWord(m.pos, m.pos + m.len)) {
					out.push(m.pos);
					out.push(m.pos + m.len);
				}
				at = m.pos + m.len;
			}
			return out;
		}
		var needle = query;
		if (!caseSensitive) {
			hay = hay.toLowerCase();
			needle = needle.toLowerCase();
		}
		var at = hay.indexOf(needle);
		while (at >= 0) {
			if (!wholeWord || isWholeWord(at, at + needle.length)) {
				out.push(at);
				out.push(at + needle.length);
			}
			at = hay.indexOf(needle, at + needle.length);
		}
		return out;
	}

	function isWholeWord(a:Int, b:Int):Bool
		return (a == 0 || !isWordChar(codeAt(a - 1))) && (b >= rope.length || !isWordChar(codeAt(b)));

	// the matches replaced (start, end pairs; one edit, undone as one)
	public function replaceMatches(matches:Array<Int>, with:String):Bool {
		var changes = [], k = 0;
		while (k + 1 < matches.length) {
			changes.push(new Change(matches[k], matches[k + 1], with));
			k += 2;
		}
		return apply(changes, null, EDIT);
	}

	// ---- history

	public function canUndo():Bool
		return undos.length > 0;

	public function canRedo():Bool
		return redos.length > 0;

	public function undo():Bool
		return step(undos, redos, true);

	public function redo():Bool
		return step(redos, undos, false);

	function step(from:Array<Group>, to:Array<Group>, back:Bool):Bool {
		if (readOnly || from.length == 0) return false;
		var g = from.pop();
		g.open = false;
		if (back) {
			var k = g.steps.length;
			while (--k >= 0)
				applyRaw(g.steps[k].inverse);
			restore(g.before);
		} else {
			for (s in g.steps)
				applyRaw(s.changes);
			restore(g.after);
		}
		to.push(g);
		version++;
		return true;
	}

	// (changes applied outside the history: an undo's, a redo's)
	function applyRaw(changes:Array<Change>) {
		var k = changes.length;
		while (--k >= 0)
			replaceLines(changes[k].start, changes[k].end, changes[k].text);
		mapRanges(changes);
		if (onChange != null) onChange(changes);
	}

	// ---- decorations and diagnostics

	// a range drawn another way (Decoration): its id, for removeDecoration
	public function addDecoration(start:Int, end:Int, ?background:Color, ?border:Color, ?underline:Color, wholeLine = false):Int {
		var d = new Decoration(nextDecoration++, clamp(start), clamp(end), background, border, underline, wholeLine);
		decorations.push(d);
		version++;
		return d.id;
	}

	public function removeDecoration(id:Int):Bool {
		for (d in decorations)
			if (d.id == id) {
				decorations.remove(d);
				version++;
				return true;
			}
		return false;
	}

	public function clearDecorations() {
		decorations.resize(0);
		version++;
	}

	// a compiler's messages placed on the text: its lines (from 1) and
	// columns (Haxe's: characters from 1, the end excluded; an empty range
	// one character wide); messages of other files (file given and not
	// ending as theirs) and without a line left out
	public function setDiagnostics(list:Array<helder.compiler.service.Diagnostic>, ?file:String) {
		diagnostics.resize(0);
		for (d in list) {
			if (d.line <= 0) continue;
			if (file != null && d.file != null && !StringTools.endsWith(StringTools.replace(file, "\\", "/"), StringTools.replace(d.file, "\\", "/"))
				&& !StringTools.endsWith(StringTools.replace(d.file, "\\", "/"), StringTools.replace(file, "\\", "/"))) continue;
			var l = d.line - 1;
			if (l >= lineCount) l = lineCount - 1;
			var st = lineStart(l), len = line(l).length;
			var a = d.column > 0 ? d.column - 1 : 0, b = d.endColumn > 0 ? d.endColumn - 1 : len;
			if (a > len) a = len;
			if (b > len) b = len;
			if (b <= a) {
				// (no width: the word there, else a character)
				b = a < len ? a + 1 : a;
				if (a == len && a > 0) a--;
			}
			diagnostics.push(new CodeDiagnostic(st + a, st + b, d.severity, d.message));
		}
		version++;
	}

	// the diagnostics over offset pos (the most severe first)
	public function diagnosticsAt(pos:Int):Array<CodeDiagnostic> {
		var out = [for (d in diagnostics) if (pos >= d.start && pos <= d.end) d];
		out.sort((a, b) -> rank(a.severity) - rank(b.severity));
		return out;
	}

	static function rank(s:String):Int
		return s == "error" ? 0 : s == "warning" ? 1 : 2;
}
