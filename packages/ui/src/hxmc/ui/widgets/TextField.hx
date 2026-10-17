package hxmc.ui.widgets;

import hxmc.ui.*;

// A one-line text field (EditableText's keys and pointer; Enter submits):
// its text scrolls sideways to keep the caret in view; the placeholder
// shows while it is empty; a paste goes on one line. onSubmit gets the
// text on Enter. A composition shows at the caret, underlined.
class TextField extends EditableText {
	public var onSubmit:Null<String->Void>;

	var scroll = 0.0;

	public function new(text = "")
		super(text, "textfield");

	override function moreKeys(e:Event, shift:Bool, ctrl:Bool):Bool {
		if (e.key != Key.ENTER) return false;
		if (onSubmit != null) onSubmit(text);
		return true;
	}

	override function pasted(t:String):String
		return StringTools.replace(StringTools.replace(StringTools.replace(t, "\r\n", " "), "\n", " "), "\r", " ");

	override function laid():Null<Paragraph>
		return ui == null ? null : layoutText(ui.text, Math.NaN);

	override function indexAt(px:Float, py:Float):Int {
		if (ui == null) return caret;
		var p = layoutText(ui.text, Math.NaN);
		var left = localX(px) - style.borderWidth - style.padding.left + scroll;
		return p.hit(left, 0);
	}

	// (a field shrinks: its text scrolls)
	override public function minContentWidth(engine:TextEngine):Float
		return 1;

	// one line: as wide as it is given (the text scrolls in it), as high as a line
	override public function measureContent(engine:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):Size {
		var p = layoutText(engine, Math.NaN);
		var w = Math.isNaN(knownWidth) ? (Math.isNaN(availWidth) ? p.width : Math.min(p.width, availWidth)) : knownWidth;
		return new Size(Math.max(w, 1), Math.max(p.height, font().size * font().lineHeight));
	}

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (ui == null) return;
		var p = layoutText(ui.text, Math.NaN);
		var cx = p.caret(shownCaret()).x;
		// (keep the caret in view)
		if (cx - scroll > width - 1) scroll = cx - width + 1;
		if (cx - scroll < 0) scroll = cx;
		if (p.width - scroll < width - 1 && scroll > 0) scroll = Math.max(0, p.width - width + 1);
		var lh = font().size * font().lineHeight;
		canvas.pushClip(x, y, width, height, 0);
		if (focused && selectionStart != selectionEnd && composition == "") {
			for (r in p.selection(selectionStart, selectionEnd))
				canvas.rect(x + r.x - scroll, y, r.width, lh, 0, selectionColor, 0, 0);
		}
		if (text.length == 0 && composition == "" && placeholder != "") canvas.text(ui.text.layout(placeholder, font(), Math.NaN), x, y, width, Left, placeholderColor);
		else canvas.text(p, x - scroll, y, p.width, Left, textColor());
		paintComposition(canvas, p, x - scroll, y);
		caretX = x + cx - scroll;
		caretY = y;
		caretHeight = lh;
		if (focused) canvas.rect(x + cx - scroll, y + 1, Math.max(1, font().size / 14), lh - 2, 0, caretColor, 0, 0);
		canvas.popClip();
	}
}
