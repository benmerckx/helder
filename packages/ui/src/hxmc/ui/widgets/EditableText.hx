package hxmc.ui.widgets;

import hxmc.ui.*;

// Text edited in place: what TextField (one line) and TextArea (several)
// share. Focusable, edited with the keyboard (characters, Backspace,
// Delete, Left, Right, Home, End; Shift extends the selection, Control+A
// selects all, Control+C, X and V copy, cut and paste through Ui.clipboard
// (Command on macOS: either works)) and the pointer (a click places the
// caret, a drag selects). onChange gets each new text. Subclasses lay the
// text out and draw it, find the index under the pointer (indexAt), and
// take the keys that differ (moreKeys: Enter, Up and Down, Home and End).
class EditableText extends TextNode {
	public var placeholder:String = "";
	public var placeholderColor:Color = Color.rgba(0x000000, 0.4);
	public var selectionColor:Color = Color.rgba(0x3B82F6, 0.3);
	public var caretColor:Color = Color.rgb(0x111111);
	public var onChange:Null<String->Void>;
	// the caret (and the selection's other end), UTF-16 indices
	public var caret(default, null) = 0;
	public var anchor(default, null) = 0;

	var dragging = false;

	public function new(text:String, tag:String) {
		super(text, tag);
		focusable = true;
		caret = anchor = this.text.length;
		style.overflow = Hidden;
		style.cursor = Text;
		onKeyDown = key;
		onTextInput = e -> typeText(e.text);
		onPointerDown = e -> {
			var i = indexAt(e.x, e.y);
			caret = i;
			anchor = i;
			dragging = true;
			changed();
		};
		onPointerMove = e -> if (dragging && pressed) {
			caret = indexAt(e.x, e.y);
			changed();
		};
		onPointerUp = e -> dragging = false;
		onFocus = e -> changed();
		onBlur = e -> changed();
		semantics = {role: hxmc.ui.access.Role.TextInput};
	}

	override public function accessSetValue(value:String):Bool {
		select(0, text.length);
		replace(value);
		return true;
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
		if (!moreKeys(e, shift, ctrl)) switch e.key {
			case Key.LEFT: move(selectionStart != selectionEnd && !shift ? selectionStart : prev(caret), shift);
			case Key.RIGHT: move(selectionStart != selectionEnd && !shift ? selectionEnd : next(caret), shift);
			case Key.HOME: move(0, shift);
			case Key.END: move(text.length, shift);
			case Key.BACKSPACE:
				if (selectionStart == selectionEnd) anchor = prev(caret);
				replace("");
			case Key.DELETE:
				if (selectionStart == selectionEnd) anchor = next(caret);
				replace("");
			case "a".code if (ctrl):
				select(0, text.length);
			case "c".code | "x".code if (ctrl):
				if (selectionStart != selectionEnd && ui != null) {
					ui.clipboard.write(text.substring(selectionStart, selectionEnd));
					if (e.key == "x".code) replace("");
				}
			case "v".code if (ctrl):
				// (the text may come later: typed where the selection is then)
				if (ui != null) ui.clipboard.read(t -> if (t != null && t != "") replace(pasted(t)));
			case _:
				return;
		}
		// (handled: Tab still moves the focus)
		e.stop();
	}

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
		caret = clampIndex(i);
		if (!extend) anchor = caret;
		changed();
	}

	// types s over the selection
	public function typeText(s:String)
		replace(s);

	function replace(s:String) {
		var a = selectionStart, b = selectionEnd;
		var t = text.substr(0, a) + s + text.substr(b);
		text = t;
		caret = anchor = a + s.length;
		changed();
		if (onChange != null) onChange(t);
	}

	// (surrogate pairs move as one character)
	function prev(i:Int):Int {
		if (i <= 0) return 0;
		var c = StringTools.fastCodeAt(text, i - 1);
		return c >= 0xDC00 && c < 0xE000 && i >= 2 ? i - 2 : i - 1;
	}

	function next(i:Int):Int {
		if (i >= text.length) return text.length;
		var c = StringTools.fastCodeAt(text, i);
		return c >= 0xD800 && c < 0xDC00 && i + 2 <= text.length ? i + 2 : i + 1;
	}

	inline function clampIndex(i:Int):Int
		return i < 0 ? 0 : i > text.length ? text.length : i;

	function changed()
		if (ui != null) ui.requestFrame();
}
