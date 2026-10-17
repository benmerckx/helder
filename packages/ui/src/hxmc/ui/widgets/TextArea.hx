package hxmc.ui.widgets;

import hxmc.ui.*;

// Several lines of text edited in place (EditableText's keys and pointer):
// wrapped to its width, rows lines high unless its style says, scrolled
// (the wheel, and to keep the caret in view). Enter types a new line; Up
// and Down move a line keeping the column; Home and End go to the line's
// start and end (with Control: the text's). A composition shows at the
// caret, underlined.
class TextArea extends EditableText {
	// the height in lines when the style gives none
	public var rows = 3;

	var offset = 0.0;
	// the x Up and Down keep (NaN: the caret's)
	var goalX = Math.NaN;

	public function new(text = "") {
		super(text, "textarea");
		semantics.role = MultilineTextInput;
		onWheel = e -> {
			var p = laidAt();
			if (p == null) return;
			var before = offset;
			offset = Math.max(0, Math.min(offset + e.deltaY, p.height - innerHeight()));
			if (offset != before) {
				e.preventDefault();
				changed();
			}
		};
	}

	function innerWidth():Float
		return Math.max(1, width - 2 * style.borderWidth - style.padding.horizontal);

	function innerHeight():Float
		return Math.max(1, height - 2 * style.borderWidth - style.padding.vertical);

	function laidAt():Null<Paragraph>
		return ui == null ? null : layoutText(ui.text, innerWidth());

	function lineHeight():Float
		return font().size * font().lineHeight;

	override function moreKeys(e:Event, shift:Bool, ctrl:Bool):Bool {
		var p = laidAt();
		switch e.key {
			case Key.ENTER:
				goalX = Math.NaN;
				replace("\n");
			case Key.UP | Key.DOWN if (p != null):
				var c = p.caret(caret), lh = lineHeight();
				if (Math.isNaN(goalX)) goalX = c.x;
				var y = c.y + (e.key == Key.UP ? -lh : lh) + lh / 2;
				var i = y < 0 ? 0 : y > p.height ? text.length : p.hit(goalX, y);
				move(i, shift);
				return true;
			case Key.HOME | Key.END if (p != null && !ctrl):
				var c = p.caret(caret);
				move(p.hit(e.key == Key.HOME ? -1 : 1e9, c.y + lineHeight() / 2), shift);
			case _:
				goalX = Math.NaN;
				return false;
		}
		goalX = Math.NaN;
		return true;
	}

	override function indexAt(px:Float, py:Float):Int {
		var p = laidAt();
		if (p == null) return caret;
		var s = style;
		return p.hit(localX(px) - s.borderWidth - s.padding.left, localY(py) - s.borderWidth - s.padding.top + offset);
	}

	// as wide as it is given (its text wrapped to that), rows lines high
	override public function measureContent(engine:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):Size {
		var w = Math.isNaN(knownWidth) ? availWidth : knownWidth;
		var p = layoutText(engine, w);
		if (Math.isNaN(w)) w = p.width;
		var lh = font().size * font().lineHeight;
		return new Size(Math.max(w, 1), Math.isNaN(knownHeight) ? Math.max(rows, 1) * lh : knownHeight);
	}

	override public function minContentWidth(engine:TextEngine):Float
		return 0;

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (ui == null) return;
		var p = layoutText(ui.text, width);
		var lh = lineHeight();
		var c = p.caret(shownCaret());
		// (keep the caret in view)
		if (c.y + lh - offset > height) offset = c.y + lh - height;
		if (c.y < offset) offset = c.y;
		offset = Math.max(0, Math.min(offset, Math.max(0, p.height - height)));
		canvas.pushClip(x, y, width, height, 0);
		var top = y - offset;
		if (focused && selectionStart != selectionEnd && composition == "") {
			var a = p.caret(selectionStart), b = p.caret(selectionEnd);
			if (a.y == b.y) canvas.rect(x + a.x, top + a.y, b.x - a.x, lh, 0, selectionColor, 0, 0) else {
				// (to the end of the first line, whole lines, the start of the last)
				canvas.rect(x + a.x, top + a.y, width - a.x, lh, 0, selectionColor, 0, 0);
				if (b.y - a.y > lh) canvas.rect(x, top + a.y + lh, width, b.y - a.y - lh, 0, selectionColor, 0, 0);
				canvas.rect(x, top + b.y, b.x, lh, 0, selectionColor, 0, 0);
			}
		}
		if (text.length == 0 && composition == "" && placeholder != "") canvas.text(ui.text.layout(placeholder, font(), width), x, y, width, Left, placeholderColor);
		else canvas.text(p, x, top, width, Left, textColor());
		paintComposition(canvas, p, x, top);
		caretX = x + c.x;
		caretY = top + c.y;
		caretHeight = lh;
		if (focused) canvas.rect(x + c.x, top + c.y + 1, Math.max(1, font().size / 14), lh - 2, 0, caretColor, 0, 0);
		canvas.popClip();
	}
}
