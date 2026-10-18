package hxmc.ui.widgets;

import hxmc.ui.*;

// Several lines of text edited in place (EditableText's keys and pointer):
// wrapped to its width, rows lines high unless its style says (a height;
// fieldSizing Content: as tall as its lines), scrolled
// (the wheel, and to keep the caret in view). Enter types a new line; Up
// and Down move a line keeping the column; Home and End go to the line's
// start and end (with Control: the text's). A composition shows at the
// caret, underlined. Its lines are aligned as the style says (else the
// start side: right to left, on the right).
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

	function innerHeight():Float
		return Math.max(1, height - style.borderEdges.vertical - style.padding.vertical);

	// (always wrapped, whatever it inherits: as a textarea's own pre-wrap)
	override public function textWrap():TextWrap
		return Wrap;

	function laidAt():Null<Paragraph>
		return ui == null ? null : layoutText(ui.text, innerWidth());

	override function laid():Null<Paragraph>
		return laidAt();

	function lineHeight():Float
		return font().size * font().lineHeight;

	// the offset of the line at y for the text's alignment
	inline function lineShift(p:Paragraph, y:Float):Float
		return alignShift(p.lineWidth(y), innerWidth());

	override function moreKeys(e:Event, shift:Bool, ctrl:Bool):Bool {
		var p = laidAt();
		switch e.key {
			case Key.ENTER:
				goalX = Math.NaN;
				replace("\n");
			case Key.UP | Key.DOWN if (p != null):
				var c = p.caret(caret), lh = lineHeight();
				if (Math.isNaN(goalX)) goalX = c.x + lineShift(p, c.y);
				var y = c.y + (e.key == Key.UP ? -lh : lh) + lh / 2;
				var i = y < 0 ? 0 : y > p.height ? text.length : p.hit(goalX - lineShift(p, y), y);
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
		var y = localY(px, py) - s.borderEdges.top - s.padding.top + offset;
		return p.hit(localX(px, py) - s.borderEdges.left - s.padding.left - lineShift(p, y), y);
	}

	// as wide as it is given (its text wrapped to that), rows lines high (or its lines', at least one)
	override public function measureContent(engine:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):Size {
		var w = Math.isNaN(knownWidth) ? availWidth : knownWidth;
		var p = layoutText(engine, w);
		if (Math.isNaN(w)) w = p.width;
		var lh = font().size * font().lineHeight;
		var h = style.fieldSizing == Content ? Math.max(p.height, lh) : Math.max(rows, 1) * lh;
		return new Size(Math.max(w, 1), Math.isNaN(knownHeight) ? h : knownHeight);
	}

	override public function minContentWidth(engine:TextEngine):Float
		return 0;

	override function hostKind():String
		return "text-area";

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (ui == null || !drawsText()) return;
		var p = layoutText(ui.text, width);
		var lh = lineHeight();
		var c = p.caret(shownCaret());
		// (keep the caret in view)
		if (c.y + lh - offset > height) offset = c.y + lh - height;
		if (c.y < offset) offset = c.y;
		offset = Math.max(0, Math.min(offset, Math.max(0, p.height - height)));
		canvas.pushClip(x, y, width, height, 0);
		var top = y - offset;
		// (the lines aligned as lineShift has them: right, short of the caret's pixel)
		var align = fieldAlign(), aw = align == Right ? width - 1 : width, cs = lineShift(p, c.y);
		if (focused && selectionStart != selectionEnd && composition == "") {
			// (each line's runs; a line the selection goes past reaches the right edge, an empty one is filled)
			var runs = p.selection(selectionStart, selectionEnd);
			var first = p.caret(selectionStart).y, last = p.caret(selectionEnd).y;
			var ly = first, k = 0;
			while (ly <= last + 1e-6) {
				var mine = [];
				while (k < runs.length && runs[k].y < ly + lh / 2) {
					if (runs[k].y > ly - lh / 2) mine.push(runs[k]);
					k++;
				}
				var through = ly < last - 1e-6;
				if (mine.length == 0 && through) canvas.rect(x, top + ly, width, lh, 0, selectionColor, 0, 0);
				// (right to left, the line's end is its left)
				var sx = lineShift(p, ly), back = rtl();
				for (i in 0...mine.length) {
					var r = mine[i], rx = sx + r.x;
					if (through && !back && i == mine.length - 1) canvas.rect(x + rx, top + ly, width - rx, lh, 0, selectionColor, 0, 0);
					else if (through && back && i == 0) canvas.rect(x, top + ly, rx + r.width, lh, 0, selectionColor, 0, 0);
					else canvas.rect(x + rx, top + ly, r.width, lh, 0, selectionColor, 0, 0);
				}
				ly += lh;
			}
		}
		if (text.length == 0 && composition == "" && placeholder != "") {
			var pp = placeholderParagraph(ui.text, width);
			paintTextShadows(canvas, pp, x, y, aw, align, placeholderColor);
			canvas.text(pp, x, y, aw, align, placeholderColor);
		} else {
			paintTextShadows(canvas, p, x, top, aw, align, textColor());
			canvas.text(p, x, top, aw, align, textColor());
		}
		paintComposition(canvas, p, x + cs, top);
		caretX = x + cs + c.x;
		caretY = top + c.y;
		caretHeight = lh;
		if (focused) canvas.rect(x + cs + c.x, top + c.y + 1, Math.max(1, font().size / 14), lh - 2, 0, caretColor ?? textColor(), 0, 0);
		canvas.popClip();
	}
}
