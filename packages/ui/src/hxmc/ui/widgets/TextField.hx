package hxmc.ui.widgets;

import hxmc.ui.*;

// A one-line text field (EditableText's keys and pointer; Enter submits):
// its text scrolls sideways to keep the caret in view, and while it fits
// it is aligned as the style says (else the start side: right to left, on
// the right); the placeholder shows while it is empty; a paste goes on one
// line. onSubmit gets the text on Enter. A composition shows at the caret,
// underlined. Its line is centred in a taller box, as a browser's input's.
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
		var left = localX(px, py) - style.borderEdges.left - style.padding.left + scroll - aligned(p, innerWidth());
		return p.hit(left, 0);
	}

	// the text's offset for its alignment while it fits (scrolled: none)
	inline function aligned(p:Paragraph, width:Float):Float
		return scroll > 0 ? 0 : alignShift(p.width, width);

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
		var ox = x - scroll + aligned(p, width);
		var lh = font().size * font().lineHeight;
		canvas.pushClip(x, y, width, height, 0);
		y += Math.max(0, (height - lh) / 2);
		if (focused && selectionStart != selectionEnd && composition == "") {
			for (r in p.selection(selectionStart, selectionEnd))
				canvas.rect(ox + r.x, y, r.width, lh, 0, selectionColor, 0, 0);
		}
		// (its text shadows under it, the placeholder's too)
		if (text.length == 0 && composition == "" && placeholder != "") {
			var pp = placeholderParagraph(ui.text, Math.NaN);
			paintTextShadows(canvas, pp, x, y, width, fieldAlign(), placeholderColor);
			canvas.text(pp, x, y, width, fieldAlign(), placeholderColor);
		} else {
			paintTextShadows(canvas, p, ox, y, p.width, Left, textColor());
			canvas.text(p, ox, y, p.width, Left, textColor());
		}
		paintComposition(canvas, p, ox, y);
		caretX = ox + cx;
		caretY = y;
		caretHeight = lh;
		if (focused) canvas.rect(ox + cx, y + 1, Math.max(1, font().size / 14), lh - 2, 0, caretColor ?? textColor(), 0, 0);
		canvas.popClip();
	}
}
