package hxmc.ui.widgets;

import hxmc.ui.*;

// A one-line text field: focusable, edited with the keyboard (characters,
// Backspace, Delete, Left, Right, Home, End; Shift extends the selection,
// Control+A selects all, Control+C, X and V copy, cut and paste through
// Ui.clipboard (Command on macOS: either works); Enter submits) and the pointer (a click places
// the caret, a drag selects). Its text scrolls sideways to keep the caret
// in view; the placeholder shows while it is empty. onChange gets each new
// text, onSubmit the text on Enter.
class TextField extends TextNode {
	public var placeholder:String = "";
	public var placeholderColor:Color = Color.rgba(0x000000, 0.4);
	public var selectionColor:Color = Color.rgba(0x3B82F6, 0.3);
	public var caretColor:Color = Color.rgb(0x111111);
	public var onChange:Null<String->Void>;
	public var onSubmit:Null<String->Void>;
	// the caret (and the selection's other end), UTF-16 indices
	public var caret(default, null) = 0;
	public var anchor(default, null) = 0;

	var scroll = 0.0;
	var dragging = false;

	public function new(text = "") {
		super(text, "textfield");
		focusable = true;
		caret = anchor = this.text.length;
		style.overflow = Hidden;
		style.cursor = Text;
		onKeyDown = key;
		onTextInput = e -> typeText(e.text);
		onPointerDown = e -> {
			var i = indexAt(e.x);
			caret = i;
			anchor = i;
			dragging = true;
			changed();
		};
		onPointerMove = e -> if (dragging && pressed) {
			caret = indexAt(e.x);
			changed();
		};
		onPointerUp = e -> dragging = false;
		onFocus = e -> changed();
		onBlur = e -> changed();
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
		switch e.key {
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
			case Key.ENTER:
				if (onSubmit != null) onSubmit(text);
			case "a".code if (ctrl):
				select(0, text.length);
			case "c".code | "x".code if (ctrl):
				if (selectionStart != selectionEnd && ui != null) {
					ui.clipboard.write(text.substring(selectionStart, selectionEnd));
					if (e.key == "x".code) replace("");
				}
			case "v".code if (ctrl):
				// (the text may come later: typed where the selection is then; one line)
				if (ui != null) ui.clipboard.read(t -> if (t != null && t != "") replace(StringTools.replace(StringTools.replace(StringTools.replace(t, "\r\n", " "), "\n", " "), "\r", " ")));
			case _:
				return;
		}
		// (handled: Tab still moves the focus)
		e.stop();
	}

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

	// the index nearest to a window x
	function indexAt(px:Float):Int {
		if (ui == null) return caret;
		var p = layoutText(ui.text, Math.NaN);
		var left = absX + style.borderWidth + style.padding.left - scroll;
		return p.hit(px - left, 0);
	}

	// one line: as wide as it is given (the text scrolls in it), as high as a line
	override public function measureContent(engine:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):Size {
		var p = layoutText(engine, Math.NaN);
		var w = Math.isNaN(knownWidth) ? (Math.isNaN(availWidth) ? p.width : Math.min(p.width, availWidth)) : knownWidth;
		return new Size(Math.max(w, 1), Math.max(p.height, font().size * font().lineHeight));
	}

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (ui == null) return;
		var p = layoutText(ui.text, Math.NaN);
		var cx = p.caret(caret).x;
		// (keep the caret in view)
		if (cx - scroll > width - 1) scroll = cx - width + 1;
		if (cx - scroll < 0) scroll = cx;
		if (p.width - scroll < width - 1 && scroll > 0) scroll = Math.max(0, p.width - width + 1);
		var lh = font().size * font().lineHeight;
		canvas.pushClip(x, y, width, height, 0);
		if (focused && selectionStart != selectionEnd) {
			var a = p.caret(selectionStart).x, b = p.caret(selectionEnd).x;
			canvas.rect(x + a - scroll, y, b - a, lh, 0, selectionColor, 0, 0);
		}
		if (text.length == 0 && placeholder != "") canvas.text(ui.text.layout(placeholder, font(), Math.NaN), x, y, width, Left, placeholderColor);
		else canvas.text(p, x - scroll, y, p.width, Left, textColor());
		if (focused) canvas.rect(x + cx - scroll, y + 1, Math.max(1, font().size / 14), lh - 2, 0, caretColor, 0, 0);
		canvas.popClip();
	}
}
