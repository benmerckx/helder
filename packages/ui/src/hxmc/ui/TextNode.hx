package hxmc.ui;

// A run of text: measured and wrapped by the Ui's TextEngine to the width
// its parent gives it (the content box), with the node's inherited font,
// colour and alignment.
class TextNode extends Node {
	public var text(default, set):String;

	// the last layout: its font and width, and the paragraph
	var paragraph:Null<Paragraph>;
	var laidFont:Null<Font>;
	var laidWidth = Math.NaN;
	var laidText:Null<String>;
	// the max-content paragraph (no width), kept apart: the layout asks for
	// it (min-content and max-content sizes) between widths
	var maxParagraph:Null<Paragraph>;
	var maxFont:Null<Font>;
	var maxText:Null<String>;

	public function new(text:String = "", ?tag:String) {
		super(tag == null ? "text" : tag);
		this.text = text;
	}

	function set_text(v:String):String {
		if (v == null) v = "";
		if (v == text) return v;
		text = v;
		markDirty();
		return v;
	}

	override public function hasContent():Bool
		return true;

	override public function measureContent(engine:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):Size {
		var p = layoutText(engine, Math.isNaN(knownWidth) ? availWidth : knownWidth);
		return new Size(p.width, p.height);
	}

	// (from the max-content paragraph, which the layout asks for too)
	override public function minContentWidth(engine:TextEngine):Float
		return layoutText(engine, Math.NaN).minWidth;

	// the paragraph for a width (NaN: unbounded), from the last one when the same
	public function layoutText(engine:TextEngine, maxWidth:Float):Paragraph {
		var f = font();
		// (to 1/64 pixel up: a width measured from this text fits it again)
		var w = Math.isNaN(maxWidth) ? maxWidth : Math.fceil(maxWidth * 64 - 1e-6) / 64;
		var mp = maxParagraph != null && maxText == text && f.equals(maxFont) ? maxParagraph : null;
		// (the unbounded paragraph first: the layout asks for it anyway, and a
		// width it fits in lays it out the same)
		if (mp == null) {
			mp = engine.layout(text, f, Math.NaN);
			maxParagraph = mp;
			maxFont = f;
			maxText = text;
		}
		if (Math.isNaN(w) || (mp.width <= w && mp.lineCount == 1)) {
			paragraph = mp;
			laidFont = f;
			laidWidth = Math.NaN;
			laidText = text;
			return mp;
		}
		if (paragraph != null && laidText == text && f.equals(laidFont) && w == laidWidth) return paragraph;
		paragraph = engine.layout(text, f, w);
		laidFont = f;
		laidWidth = w;
		laidText = text;
		return paragraph;
	}

	// the paragraph as drawn (after Ui.update), or null
	public function laidOut():Null<Paragraph>
		return paragraph;

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (ui == null || text.length == 0) return;
		// (the layout's paragraph: its width was the unrounded one, which
		// rounding the box's edges may have made up to a pixel narrower)
		var p = paragraph != null && laidText == text && font().equals(laidFont)
			&& (Math.abs(laidWidth - width) < 1.5 || (Math.isNaN(laidWidth) && paragraph.width <= width + 1.5)) ? paragraph : layoutText(ui.text, width + 0.5);
		canvas.text(p, x, y, width, textAlign(), textColor());
	}
}
