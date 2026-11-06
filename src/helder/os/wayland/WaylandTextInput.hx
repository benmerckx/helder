package helder.os.wayland;

import helder.os.Event;
import helder.os.wayland.protocol.TextInputUnstableV3Protocol;
import hxmc.unsafe.*;

// Wayland's text-input-unstable-v3 for a seat (WaylandWindow's): the input
// method's connection to the window where text is typed. While a window
// takes text (Window.startTextInput) and the compositor has entered the
// text input into its surface, it is enabled with the field's state: the
// text around the caret (set_surrounding_text: UTF-8, at most 4000 bytes,
// a window of the field's text around the selection when it is longer;
// none for a password), the content type (multiline, a password's purpose
// and hints) and the caret's rectangle (set_cursor_rectangle, in the
// surface's points), each change committed. The input method's events are
// double-buffered until done, then applied in the protocol's order: the
// composition shown before replaced, the text around the caret deleted
// (delete_surrounding_text: TextReplace events of the field's text, after
// the selection then before it), the committed text typed (TextInput), the
// new composition shown (preedit_string: TextEditing, its caret in UTF-16).
// Requests and events go through Proxy (its recorder in the tests:
// WaylandTextInput.test.hx).
class WaylandTextInput {
	public final input:ZwpTextInputV3;
	// a window event: kind, text, x, y, the surface it is for
	final emit:(kind:EventKind, text:String, x:Int, y:Int) -> Void;
	// the listener's slot (tests deliver events to it)
	public final slot:Int;
	// the surface the compositor entered it into (nil: none)
	public var entered(default, null) = Ptr.nil();
	// whether it is enabled (the program's text input on, in the entered surface)
	public var enabled(default, null) = false;
	// the surface the program types into (nil: text input off), its caret's rectangle (points)
	var wanted = Ptr.nil();
	var rx = 0;
	var ry = 0;
	var rw = 0;
	var rh = 0;
	// the field's text and selection (UTF-16), its kind; null: none given
	var text:Null<String> = null;
	var start = 0;
	var end = 0;
	var multiline = false;
	var secret = false;
	// the window of the text sent (its first UTF-16 index)
	var sentFrom = 0;
	var sent = "";
	// commits made (done's serial)
	public var commits(default, null) = 0;
	// the events' pending state until done
	var preedit = "";
	var preeditBegin = -1;
	var commitText:Null<String> = null;
	var deleteBefore = 0;
	var deleteAfter = 0;
	// the composition shown
	var shown = "";
	var shownCaret = 0;

	public function new(input:ZwpTextInputV3, emit:(kind:EventKind, text:String, x:Int, y:Int) -> Void) {
		this.input = input;
		this.emit = emit;
		var e = new ZwpTextInputV3Events();
		e.enter = s -> {
			entered = s;
			if (wanted == s) enable();
		};
		e.leave = s -> {
			if (entered == s) entered = Ptr.nil();
			// (the compositor disabled it; the composition gone)
			enabled = false;
			endComposition();
		};
		e.preeditString = (t, b, _) -> {
			preedit = t ?? "";
			preeditBegin = b;
		};
		e.commitString = t -> commitText = t ?? "";
		e.deleteSurroundingText = (b, a) -> {
			deleteBefore = b;
			deleteAfter = a;
		};
		e.done = serial -> apply();
		slot = input.listen(e);
	}

	public function dispose() {
		Proxy.forget(slot);
		input.destroy();
	}

	// text typed into surface s at the caret (x, y, width, height: its points)
	public function begin(s:Ptr, x:Int, y:Int, width:Int, height:Int) {
		var moved = x != rx || y != ry || width != rw || height != rh;
		rx = x;
		ry = y;
		rw = width;
		rh = height;
		if (wanted != s) {
			if (enabled) stop();
			wanted = s;
			text = null;
		}
		if (entered != s) return;
		if (!enabled) enable() else if (moved) {
			input.setCursorRectangle(rx, ry, rw, rh);
			commit();
		}
	}

	// the field's text and selection, its kind
	public function context(t:String, s:Int, e:Int, multi:Bool, pass:Bool) {
		text = t;
		start = s < e ? s : e;
		end = s < e ? e : s;
		if (start < 0) start = 0;
		if (end > t.length) end = t.length;
		multiline = multi;
		secret = pass;
		if (!enabled) return;
		surrounding();
		contentType();
		commit();
	}

	public function stop() {
		wanted = Ptr.nil();
		text = null;
		if (enabled) {
			enabled = false;
			input.disable();
			commit();
		}
		shown = "";
		shownCaret = 0;
	}

	function enable() {
		enabled = true;
		input.enable();
		surrounding();
		contentType();
		input.setCursorRectangle(rx, ry, rw, rh);
		commit();
	}

	inline function commit() {
		input.commit();
		commits++;
	}

	// (the text around the selection, at most 4000 bytes: the whole when it fits)
	function surrounding() {
		if (text == null || secret) return;
		var t:String = text;
		var from = 0, to = t.length, span = 2000;
		while (bytes(t.substring(from, to)) > 4000) {
			from = start - span < 0 ? 0 : start - span;
			to = end + span > t.length ? t.length : end + span;
			// (the selection itself too long: the caret's end of it alone)
			if (span == 0) {
				from = to = end;
				break;
			}
			span = span >> 1;
			if (span < 16) span = 0;
			from = surrogateSafe(t, from);
			to = surrogateSafe(t, to);
		}
		sentFrom = from;
		sent = t.substring(from, to);
		var a = start < from ? 0 : start > to ? to - from : start - from;
		var b = end < from ? 0 : end > to ? to - from : end - from;
		// (the cursor the selection's end, the anchor its start)
		input.setSurroundingText(sent, bytes(sent.substr(0, b)), bytes(sent.substr(0, a)));
	}

	// (an index moved off the second half of a surrogate pair)
	static function surrogateSafe(t:String, i:Int):Int {
		if (i > 0 && i < t.length) {
			var c = StringTools.fastCodeAt(t, i);
			if (c >= 0xDC00 && c < 0xE000) return i - 1;
		}
		return i;
	}

	function contentType() {
		// (hint multiline 0x200; a password: hidden text, sensitive data, its purpose 8)
		var hint = (multiline ? 0x200 : 0) | (secret ? 0x40 | 0x80 : 0);
		input.setContentType(hint, secret ? 8 : 0);
	}

	// UTF-8's length of s
	public static function bytes(s:String):Int {
		var n = 0, i = 0;
		while (i < s.length) {
			var c = StringTools.fastCodeAt(s, i++);
			if (c < 0x80) n += 1 else if (c < 0x800) n += 2 else if (c >= 0xD800 && c < 0xDC00 && i < s.length) {
				n += 4;
				i++;
			} else n += 3;
		}
		return n;
	}

	// UTF-16 units of the first n bytes of s (from its start)
	public static function unitsOf(s:String, n:Int):Int {
		var i = 0, b = 0;
		while (i < s.length && b < n) {
			var c = StringTools.fastCodeAt(s, i);
			if (c < 0x80) b += 1 else if (c < 0x800) b += 2 else if (c >= 0xD800 && c < 0xDC00 && i + 1 < s.length) {
				b += 4;
				i++;
			} else b += 3;
			i++;
		}
		return i;
	}

	// UTF-16 units of the last n bytes before index i of s
	static function unitsBefore(s:String, i:Int, n:Int):Int {
		var k = i, b = 0;
		while (k > 0 && b < n) {
			var c = StringTools.fastCodeAt(s, k - 1);
			if (c >= 0xDC00 && c < 0xE000 && k >= 2) {
				b += 4;
				k -= 2;
			} else {
				b += c < 0x80 ? 1 : c < 0x800 ? 2 : 3;
				k--;
			}
		}
		return i - k;
	}

	function endComposition() {
		if (shown == "") return;
		shown = "";
		shownCaret = 0;
		emit(TextEditing, "", 0, 0);
	}

	// done: the pending state applied, in the protocol's order
	function apply() {
		var p = preedit, pb = preeditBegin, c = commitText, before = deleteBefore, after = deleteAfter;
		preedit = "";
		preeditBegin = -1;
		commitText = null;
		deleteBefore = deleteAfter = 0;
		var caret = pb < 0 ? p.length : unitsOf(p, pb);
		// 1. the composition before: gone when replaced, ended or committed
		if (shown != "" && (p == "" || c != null || before > 0 || after > 0)) endComposition();
		// 2. the text around the selection deleted (after it first: the indices before stay)
		if ((before > 0 || after > 0) && text != null) {
			var t:String = text;
			if (after > 0) {
				var n = unitsOf(t.substr(end), after);
				emit(TextReplace, "", end, end + n);
				t = t.substr(0, end) + t.substr(end + n);
			}
			if (before > 0) {
				var n = unitsBefore(t, start, before);
				emit(TextReplace, "", start - n, start);
				t = t.substr(0, start - n) + t.substr(start);
				start -= n;
				end -= n;
			}
			text = t;
		}
		// 3. the commit typed over the selection
		if (c != null && c != "") {
			emit(TextInput, c, 0, 0);
			if (text != null) {
				var t:String = text;
				text = t.substr(0, start) + c + t.substr(end);
				start = end = start + c.length;
			}
		}
		// 4. the new composition, its caret
		if (p != "" && (p != shown || caret != shownCaret)) {
			shown = p;
			shownCaret = caret;
			emit(TextEditing, p, caret, 0);
		}
	}
}
