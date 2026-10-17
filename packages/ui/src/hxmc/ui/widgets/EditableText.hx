package hxmc.ui.widgets;

import hxmc.ui.*;

// Text edited in place: what TextField (one line) and TextArea (several)
// share. Focusable, edited with the keyboard (characters, Backspace,
// Delete, Left, Right, Home, End: by grapheme clusters, but Backspace
// takes a letter's marks one at a time, and Left and Right in text with
// right-to-left characters go the way they point; Shift extends the selection; Control or
// Alt (Option) with Left, Right, Backspace and Delete: by words; Command
// with Left and Right: Home and End; Control+A selects all, Control+C, X
// and V copy, cut and paste through Ui.clipboard, Control+Z undoes,
// Control+Shift+Z or Control+Y redoes (Command on macOS: either works))
// and the pointer (a click places the caret, Shift+click extends the
// selection, a drag selects, a double click selects a word, a triple
// click the line). onChange gets each new text. Subclasses lay the
// text out and draw it, find the index under the pointer (indexAt), and
// take the keys that differ (moreKeys: Enter, Up and Down, Home and End).
// An input method's composition shows at the caret, underlined, until its
// commit types it (the selection goes when it starts); the caret's place
// is the input method's (textInputArea).
class EditableText extends TextNode {
	public var placeholder:String = "";
	public var placeholderColor:Color = Color.rgba(0x000000, 0.4);
	public var selectionColor:Color = Color.rgba(0x3B82F6, 0.3);
	public var caretColor:Color = Color.rgb(0x111111);
	public var onChange:Null<String->Void>;
	// the caret (and the selection's other end), UTF-16 indices
	public var caret(default, null) = 0;
	public var anchor(default, null) = 0;

	// an input method's composition (Ui.composition): shown at the caret, not
	// in text until committed; the caret in it
	public var composition(default, null) = "";
	var compositionCaret = 0;
	// the caret as last drawn (window pixels; NaN: not yet)
	var caretX = Math.NaN;
	var caretY = 0.0;
	var caretHeight = 0.0;

	var dragging = false;
	// the undo history: the states before each edit (a run of typing is one), and what was undone
	final undos:Array<{text:String, caret:Int, anchor:Int}> = [];
	final redos:Array<{text:String, caret:Int, anchor:Int}> = [];
	var typing = false;
	// clicks in a row (double, triple) and the last one's time and place
	var clicks = 0;
	var clickAt = -1e9;
	var clickX = 0.0;
	var clickY = 0.0;
	// the time (seconds; tests replace it)
	public static var now:Void->Float = haxe.Timer.stamp;

	public function new(text:String, tag:String) {
		super(text, tag);
		focusable = true;
		caret = anchor = this.text.length;
		style.overflow = Hidden;
		style.cursor = Text;
		onKeyDown = key;
		onTextInput = e -> {
			edit(e.text, true);
		};
		onComposition = e -> compose(e.text, e.caret);
		onPointerDown = e -> {
			var i = indexAt(e.x, e.y), t = now();
			// (a right click: the selection kept when it is inside it, else the caret there; no drag)
			if (e.button == 3) {
				if (i < selectionStart || i > selectionEnd || selectionStart == selectionEnd) select(i, i);
				return;
			}
			clicks = t - clickAt < 0.45 && Math.abs(e.x - clickX) < 5 && Math.abs(e.y - clickY) < 5 ? clicks + 1 : 1;
			clickAt = t;
			clickX = e.x;
			clickY = e.y;
			typing = false;
			if (clicks == 2) {
				anchor = wordStart(i);
				caret = wordEnd(i);
			} else if (clicks >= 3) {
				anchor = lineStart(i);
				caret = lineEnd(i);
			} else {
				caret = i;
				if (e.mods & Key.MOD_SHIFT == 0) anchor = i;
			}
			dragging = clicks == 1;
			changed();
		};
		onPointerMove = e -> if (dragging && pressed) {
			caret = indexAt(e.x, e.y);
			changed();
		};
		onPointerUp = e -> dragging = false;
		onFocus = e -> changed();
		onBlur = e -> {
			// (an input method commits it to the next focus, or drops it)
			if (composition != "") compose("", 0);
			changed();
		};
		semantics = {role: hxmc.ui.access.Role.TextInput};
	}

	override public function accessSetValue(value:String):Bool {
		select(0, text.length);
		replace(value);
		return true;
	}

	override public function takesText():Bool
		return true;

	override public function textInputArea():Null<{x:Float, y:Float, width:Float, height:Float}>
		return focused && !Math.isNaN(caretX) ? {x: caretX, y: caretY, width: 1.0, height: caretHeight} : null;

	// the composition now (empty: none), the caret in it: shown, not typed
	public function compose(s:String, at:Int) {
		if (s == composition && at == compositionCaret) return;
		if (s != "" && composition == "" && selectionStart != selectionEnd) replace("");
		composition = s;
		compositionCaret = at < 0 ? 0 : at > s.length ? s.length : at;
		markDirty();
		changed();
	}

	override function shownText():String
		return composition == "" ? text : text.substr(0, caret) + composition + text.substr(caret);

	// the caret in the text shown (in the composition while there is one)
	function shownCaret():Int
		return composition == "" ? caret : caret + compositionCaret;

	// the composition's underline, line by line, in p (drawn at x, y)
	function paintComposition(canvas:Canvas, p:Paragraph, x:Float, y:Float) {
		if (composition == "") return;
		var lh = font().size * font().lineHeight, t = Math.max(1, Math.round(font().size / 14));
		var start = p.caret(caret), last = start;
		for (i in caret + 1...caret + composition.length + 1) {
			var c = p.caret(i);
			if (c.y != start.y) {
				canvas.rect(x + start.x, y + start.y + lh - t, last.x - start.x, t, 0, textColor(), 0, 0);
				start = c;
			}
			last = c;
		}
		canvas.rect(x + start.x, y + start.y + lh - t, last.x - start.x, t, 0, textColor(), 0, 0);
	}

	// sets the text from outside (the caret clamped)
	public function setText(s:String) {
		if (s == text) return;
		text = s;
		if (caret > text.length) caret = text.length;
		if (anchor > text.length) anchor = text.length;
	}

	public function select(start:Int, end:Int) {
		anchor = clampIndex(start);
		caret = clampIndex(end);
		changed();
	}

	public var selectionStart(get, never):Int;
	public var selectionEnd(get, never):Int;

	inline function get_selectionStart()
		return caret < anchor ? caret : anchor;

	inline function get_selectionEnd()
		return caret < anchor ? anchor : caret;

	function key(e:Event) {
		var shift = e.mods & Key.MOD_SHIFT != 0, ctrl = e.mods & (Key.MOD_CONTROL | Key.MOD_META) != 0;
		// (by words: Control, or Alt as macOS's Option; Command+Left and Right: the line's ends)
		var word = e.mods & (Key.MOD_CONTROL | Key.MOD_ALT) != 0, edge = e.mods & Key.MOD_META != 0;
		if (!moreKeys(e, shift, ctrl)) switch e.key {
			case Key.LEFT if (edge): move(lineStart(caret), shift);
			case Key.RIGHT if (edge): move(lineEnd(caret), shift);
			case Key.LEFT if (word): move(prevWord(caret), shift);
			case Key.RIGHT if (word): move(nextWord(caret), shift);
			case Key.LEFT: move(selectionStart != selectionEnd && !shift ? selectionStart : visualStep(caret, false), shift);
			case Key.RIGHT: move(selectionStart != selectionEnd && !shift ? selectionEnd : visualStep(caret, true), shift);
			case Key.HOME: move(0, shift);
			case Key.END: move(text.length, shift);
			case Key.BACKSPACE:
				if (selectionStart == selectionEnd) anchor = word ? prevWord(caret) : backspaced(caret);
				replace("");
			case Key.DELETE:
				if (selectionStart == selectionEnd) anchor = word ? nextWord(caret) : next(caret);
				replace("");
			case "z".code if (ctrl && shift):
				redo();
			case "z".code if (ctrl):
				undo();
			case "y".code if (ctrl):
				redo();
			case "a".code if (ctrl):
				selectAll();
			case "c".code if (ctrl):
				copy();
			case "x".code if (ctrl):
				cut();
			case "v".code if (ctrl):
				paste();
			case _:
				return;
		}
		// (handled: Tab still moves the focus)
		e.stop();
	}

	// the selection to the clipboard, and out of the text
	public function cut() {
		if (selectionStart == selectionEnd || ui == null) return;
		ui.clipboard.write(text.substring(selectionStart, selectionEnd));
		replace("");
	}

	// the selection to the clipboard
	public function copy()
		if (selectionStart != selectionEnd && ui != null) ui.clipboard.write(text.substring(selectionStart, selectionEnd));

	// the clipboard's text over the selection (it may come later: typed where the selection is then)
	public function paste()
		if (ui != null) ui.clipboard.read(t -> if (t != null && t != "") replace(pasted(t)));

	public function selectAll()
		select(0, text.length);

	// the keys a subclass takes before the common ones: true when handled
	function moreKeys(e:Event, shift:Bool, ctrl:Bool):Bool
		return false;

	// pasted text as typed (TextField: on one line)
	function pasted(t:String):String
		return StringTools.replace(StringTools.replace(t, "\r\n", "\n"), "\r", "\n");

	// the index nearest to a window position
	function indexAt(px:Float, py:Float):Int
		return caret;

	function move(i:Int, extend:Bool) {
		typing = false;
		caret = clampIndex(i);
		if (!extend) anchor = caret;
		changed();
	}

	// types s over the selection
	public function typeText(s:String)
		edit(s, true);

	// s over the selection (an edit: undone as one); typed: a run of typing joins into one edit
	function edit(s:String, typed:Bool) {
		if (!(typed && typing)) {
			undos.push({text: text, caret: caret, anchor: anchor});
			if (undos.length > 200) undos.shift();
		}
		redos.resize(0);
		var a = selectionStart, b = selectionEnd;
		var t = text.substr(0, a) + s + text.substr(b);
		text = t;
		caret = anchor = a + s.length;
		// (a space or a line ends a run of typing)
		typing = typed && s != " " && s != "\n";
		changed();
		if (onChange != null) onChange(t);
	}

	function replace(s:String)
		edit(s, false);

	// the last edit undone (redo: done again)
	public function undo()
		step(undos, redos);

	public function redo()
		step(redos, undos);

	function step(from:Array<{text:String, caret:Int, anchor:Int}>, to:Array<{text:String, caret:Int, anchor:Int}>) {
		if (from.length == 0) return;
		to.push({text: text, caret: caret, anchor: anchor});
		var s = from.pop();
		text = s.text;
		caret = clampIndex(s.caret);
		anchor = clampIndex(s.anchor);
		typing = false;
		changed();
		if (onChange != null) onChange(text);
	}

	// (by grapheme clusters: a letter and its marks, an emoji sequence, a flag)
	inline function prev(i:Int):Int
		return hxmc.text.Grapheme.prev(text, i);

	inline function next(i:Int):Int
		return hxmc.text.Grapheme.next(text, i);

	// the text laid out as it is painted (subclasses: at their width)
	function laid():Null<Paragraph>
		return null;

	// Left and Right: with right-to-left text, to the nearest caret place
	// left or right of the caret on its line (the caret moves as it looks;
	// at the line's edge it stays), else a cluster back or forward
	function visualStep(i:Int, right:Bool):Int {
		var p = laid();
		if (p == null || !hxmc.text.Bidi.hasRtl([for (c in new haxe.iterators.StringIteratorUnicode(text)) c])) return right ? next(i) : prev(i);
		var at = p.caret(i);
		var best = i, bestX = at.x, j = 0;
		while (true) {
			if (j != i) {
				var c = p.caret(j);
				if (Math.abs(c.y - at.y) < 0.5 && (right ? c.x > at.x + 1e-6 : c.x < at.x - 1e-6)
					&& (best == i || (right ? c.x < bestX : c.x > bestX))) {
					best = j;
					bestX = c.x;
				}
			}
			if (j >= text.length) break;
			j = next(j);
		}
		return best;
	}

	// where Backspace deletes back to: a cluster, but a letter's marks one at a time (as browsers do)
	function backspaced(i:Int):Int {
		var start = prev(i);
		if (i <= 0) return 0;
		var c = StringTools.fastCodeAt(text, i - 1);
		var surrogate = c >= 0xDC00 && c < 0xE000 && i >= 2;
		var last = surrogate ? i - 2 : i - 1;
		if (last > start && !surrogate && c >= 0x300 && c != 0x200D && !(c >= 0xFE00 && c <= 0xFE0F) && !(c >= 0x20D0 && c <= 0x20F0)
			&& hxmc.text.Bidi.classOf(c) == hxmc.text.Bidi.NSM)
			return last;
		return start;
	}

	// words: letters, digits, _ and every non-ASCII character but spaces
	function isWord(i:Int):Bool {
		var c = StringTools.fastCodeAt(text, i);
		return c >= "0".code && c <= "9".code || c >= "a".code && c <= "z".code || c >= "A".code && c <= "Z".code || c == "_".code
			|| c > 127 && c != 0xA0 && c != 0x3000 && c != 0x2028;
	}

	// the start of the word before i (over the spaces first)
	function prevWord(i:Int):Int {
		while (i > 0 && !isWord(i - 1))
			i--;
		while (i > 0 && isWord(i - 1))
			i--;
		return i;
	}

	// the end of the word after i (over the spaces first)
	function nextWord(i:Int):Int {
		while (i < text.length && !isWord(i))
			i++;
		while (i < text.length && isWord(i))
			i++;
		return i;
	}

	// the word (or run of other characters) around i
	function wordStart(i:Int):Int {
		if (i >= text.length && i > 0) i--;
		if (text.length == 0) return 0;
		var w = isWord(i);
		while (i > 0 && isWord(i - 1) == w)
			i--;
		return i;
	}

	function wordEnd(i:Int):Int {
		if (text.length == 0) return 0;
		if (i >= text.length) return text.length;
		var w = isWord(i);
		while (i < text.length && isWord(i) == w)
			i++;
		return i;
	}

	// the line around i (between "\n"s)
	function lineStart(i:Int):Int {
		while (i > 0 && StringTools.fastCodeAt(text, i - 1) != "\n".code)
			i--;
		return i;
	}

	function lineEnd(i:Int):Int {
		while (i < text.length && StringTools.fastCodeAt(text, i) != "\n".code)
			i++;
		return i;
	}

	inline function clampIndex(i:Int):Int
		return i < 0 ? 0 : i > text.length ? text.length : i;

	function changed()
		if (ui != null) ui.requestFrame();
}
