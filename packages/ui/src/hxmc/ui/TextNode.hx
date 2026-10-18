package hxmc.ui;

// A run of text: measured and wrapped by the Ui's TextEngine to the width
// its parent gives it (the content box), with the node's inherited font,
// colour and alignment. Its children, when it has some, are spans: TextNodes
// whose texts (or their own spans) make the paragraph instead of its own
// text, each in its style (inheriting this one's): bold, a colour, a size.
// They are not laid out as boxes; a pointer over one's text hits it.
class TextNode extends Node {
	public var text(default, set):String;

	// the last layout: its font and width, and the paragraph
	var paragraph:Null<Paragraph>;
	var laidFont:Null<Font>;
	var laidWidth = Math.NaN;
	var laidCut = Math.NaN;
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
	// (not wrapped: as wide as its longest line)
	override public function minContentWidth(engine:TextEngine):Float {
		var p = layoutText(engine, Math.NaN);
		return wraps() ? p.minWidth : p.width;
	}

	// the text laid out and drawn (EditableText: with its composition; with spans: theirs)
	function shownText():String
		return children.length > 0 ? spanned().text : transformed(text);

	// the whole text, as shown: its own, or its spans'
	public function allText():String
		return children.length > 0 ? spanned().text : transformed(text);

	// its text as its textTransform shows it (letter for letter: the indices kept)
	function transformed(s:String):String
		return switch textTransform() {
			case Uppercase: s.toUpperCase();
			case Lowercase: s.toLowerCase();
			case Capitalize:
				var b = new StringBuf(), start = true;
				for (i in 0...s.length) {
					var c = s.charAt(i);
					b.add(start ? c.toUpperCase() : c);
					start = c == " " || c == "\n" || c == "\t";
				}
				b.toString();
			case _: s;
		}

	// (spans: the text, each span's place, font and colour, and a key of them all)
	function spanned():{text:String, spans:Array<TextSpan>, colors:Array<Color>, key:String} {
		var b = new StringBuf(), spans:Array<TextSpan> = [], colors:Array<Color> = [], key = new StringBuf(), pos = 0;
		function walk(n:Node) {
			for (c in n.children) {
				if (!Std.isOfType(c, TextNode) || c.style.display == None) continue;
				var t:TextNode = cast c;
				if (t.children.length > 0) {
					walk(t);
					continue;
				}
				var s = t.transformed(t.text), f = t.font();
				if (s.length == 0) continue;
				b.add(s);
				spans.push(new TextSpan(pos, pos + s.length, f));
				colors.push(t.textColor());
				key.add(pos + ":" + f.family + "/" + f.size + "/" + f.weight + "/" + f.italic + "/" + f.lineHeight + "/" + f.letterSpacing + "/" + f.wordSpacing + "/" + f.features + ";");
				pos += s.length;
			}
		}
		walk(this);
		return {text: b.toString(), spans: spans, colors: colors, key: key.toString()};
	}

	// the span whose text is at index i (null: none, or no spans)
	public function spanAt(i:Int):Null<TextNode> {
		var pos = 0, found:Null<TextNode> = null;
		function walk(n:Node) {
			for (c in n.children) {
				if (found != null || !Std.isOfType(c, TextNode) || c.style.display == None) continue;
				var t:TextNode = cast c;
				if (t.children.length > 0) {
					walk(t);
					continue;
				}
				if (i >= pos && i < pos + t.text.length) found = t;
				pos += t.text.length;
			}
		}
		walk(this);
		return found;
	}

	// (laid out as content: its spans are not boxes)
	override public function contentOwnsChildren():Bool
		return true;

	// whether its text can be selected: a drag, a double click (a word), a
	// triple click (all of it); Ui.textSelection holds it, Mod+C copies it
	public var selectable(default, set) = false;

	function set_selectable(v:Bool):Bool {
		selectable = v;
		if (v && style.cursor == Auto) style.cursor = Text;
		return v;
	}

	// the character index nearest to a point in the window (its lines' alignment taken off)
	public function textIndexAt(px:Float, py:Float):Int {
		if (paragraph == null) return 0;
		var s = style, x = localX(px, py) - s.borderEdges.left - s.padding.left, y = localY(px, py) - s.borderEdges.top - s.padding.top;
		return paragraph.hit(x - alignOffset(paragraph, y, contentBoxWidth()), y);
	}

	inline function contentBoxWidth():Float
		return Math.max(0, width - style.borderEdges.horizontal - style.padding.left - style.padding.right);

	// where the line at y starts in a box width wide, as the text is drawn aligned
	function alignOffset(p:Paragraph, y:Float, width:Float):Float {
		var a = textAlign();
		return a == Center ? (width - p.lineWidth(y)) / 2 : a == Right ? width - p.lineWidth(y) : 0.0;
	}

	// a point over a span's text: that span (its handlers, its cursor)
	override public function hitTest(px:Float, py:Float):Null<Node> {
		var own = super.hitTest(px, py);
		if (own != this || children.length == 0 || paragraph == null) return own;
		var s = style, x = localX(px, py) - s.borderEdges.left - s.padding.left, y = localY(px, py) - s.borderEdges.top - s.padding.top;
		var i = paragraph.hit(x - alignOffset(paragraph, y, contentBoxWidth()), y);
		var c = paragraph.caret(i);
		// (the hit's character: before the caret it gave when that is right of the point)
		var at = c.x > x && i > 0 ? i - 1 : i;
		var span = spanAt(at);
		return span != null ? span : this;
	}

	// the paragraph for a width (NaN: unbounded), from the last one when the same
	public function layoutText(engine:TextEngine, maxWidth:Float):Paragraph {
		var f = font(), text = shownText();
		var rich = children.length > 0 ? spanned() : null;
		var shown = rich != null ? rich.text : text, spans = rich != null ? rich.spans : null, clamp = style.maxLines;
		// (spans: their fonts in the key; and the lines' limit)
		var justify = textAlign() == Justify;
		// (a direction set: its paragraphs in it)
		var d = dir(), base = d == null ? -1 : d == Rtl ? 1 : 0;
		text = paragraphKey(text, rich, justify, d);
		// (to 1/64 pixel up: a width measured from this text fits it again; not wrapped: none)
		var box = Math.isNaN(maxWidth) ? Math.NaN : Math.fceil(maxWidth * 64 - 1e-6) / 64;
		var w = wraps() ? box : Math.NaN;
		// (text-overflow: ellipsis: each line wider than the box cut there)
		var cut = style.textOverflow == Ellipsis ? box : Math.NaN;
		var mp = maxParagraph != null && maxText == text && f.equals(maxFont) ? maxParagraph : null;
		// (the unbounded paragraph first: the layout asks for it anyway, and a
		// width it fits in lays it out the same)
		if (mp == null) {
			mp = engine.layout(shown, f, Math.NaN, spans, clamp, false, base);
			maxParagraph = mp;
			maxFont = f;
			maxText = text;
		}
		if ((Math.isNaN(w) || (mp.width <= w && mp.lineCount == 1)) && (Math.isNaN(cut) || mp.width <= cut)) {
			paragraph = mp;
			laidFont = f;
			laidWidth = laidCut = Math.NaN;
			laidText = text;
			return mp;
		}
		inline function same(a:Float, b:Float):Bool
			return a == b || (Math.isNaN(a) && Math.isNaN(b));
		if (paragraph != null && laidText == text && f.equals(laidFont) && same(w, laidWidth) && same(cut, laidCut)) return paragraph;
		paragraph = engine.layout(shown, f, w, spans, clamp, justify, base, Math.isNaN(cut) ? -1 : cut);
		// (balanced: two to six lines at the narrowest width, to 1/64 pixel, that keeps their number, as Chromium's)
		var n = paragraph.lineCount;
		if (n > 1 && n <= 6 && clamp <= 0 && !Math.isNaN(w) && textWrap() == Balance) {
			var lo = Math.ffloor(Math.max(paragraph.minWidth, mp.width / n) * 64), hi = Math.fceil(w * 64);
			while (hi - lo > 1) {
				var mid = Math.ffloor((lo + hi) / 2), p = engine.layout(shown, f, mid / 64, spans, clamp, justify, base, Math.isNaN(cut) ? -1 : cut);
				if (p.lineCount <= n) {
					hi = mid;
					paragraph = p;
				} else lo = mid;
			}
		}
		laidFont = f;
		laidWidth = w;
		laidCut = cut;
		laidText = text;
		return paragraph;
	}

	// the paragraph as drawn (after Ui.update), or null
	public function laidOut():Null<Paragraph>
		return paragraph;

	// (its first line's, in its content box)
	override public function firstBaseline():Float
		return paragraph == null ? Math.NaN : style.borderEdges.top + style.padding.top + paragraph.baseline;

	override public function contentInk():Null<Size>
		return paragraph == null ? null : {width: paragraph.width, height: paragraph.height};

	// (what the laid out paragraph depends on besides its font and width:
	// the text, its spans' fonts, the lines' limit, justification, direction)
	function paragraphKey(text:String, rich:Null<{text:String, spans:Array<TextSpan>, colors:Array<Color>, key:String}>, justify:Bool, d:Null<Dir>):String {
		if (rich != null) text = rich.text + "\u0000" + rich.key;
		if (style.maxLines > 0) text += "\u0001" + style.maxLines;
		if (justify) text += "\u0002";
		if (d != null) text += "\u0003" + (d == Rtl ? 1 : 0);
		return text;
	}

	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		var text = shownText();
		if (ui == null || text.length == 0) return;
		var rich = children.length > 0 ? spanned() : null, align = textAlign(), length = text.length;
		text = paragraphKey(text, rich, align == Justify, dir());
		// (the layout's paragraph: its width was the unrounded one, which
		// rounding the box's edges may have made up to a pixel narrower)
		// (unbounded: wider only when not wrapped and not cut; cut: at this width)
		var fits = Math.isNaN(laidWidth) ? paragraph != null && (paragraph.width <= width + 1.5 || !wraps() && style.textOverflow != Ellipsis) : Math.abs(laidWidth - width) < 1.5;
		if (!Math.isNaN(laidCut)) fits = Math.abs(laidCut - width) < 1.5;
		var p = paragraph != null && laidText == text && font().equals(laidFont) && fits ? paragraph : layoutText(ui.text, width + 0.5);
		// decorations: its ancestors' and its own over all of it, its spans' over theirs;
		// underlines and overlines under the glyphs, line-throughs over them
		var decos = decorations(rich != null ? rich.text.length : length);
		function draw(through:Bool)
			for (d in decos)
				if ((d.kind == LineThrough) == through)
					for (r in p.decoration(d.start, d.end, d.kind, ui.scale, d.thickness, d.offset)) {
						var lx = align == Center ? (width - r.lineWidth) / 2 : align == Right ? width - r.lineWidth : 0.0;
						canvas.rect(x + lx + r.x, y + r.y, r.width, r.height, 0, d.color, 0, 0);
					}
		// (the selection under it all: each line's run, as high as its line)
		var sel = ui.textSelection;
		if (sel != null && sel.node == this && sel.anchor != sel.caret) {
			var rs = p.selection(Std.int(Math.min(sel.anchor, sel.caret)), Std.int(Math.max(sel.anchor, sel.caret)));
			for (k in 0...rs.length) {
				var r = rs[k], bottom = p.height;
				for (q in rs)
					if (q.y > r.y && q.y < bottom) bottom = q.y;
				canvas.rect(x + alignOffset(p, r.y, width) + r.x, y + r.y, r.width, bottom - r.y, 0, ui.selectionColor, 0, 0);
			}
		}
		// (its text shadows under it all, the last first: the glyphs' and
		// the decorations'; without a colour, the text's, or each span's)
		var shadows = textShadow();
		if (shadows != null)
			for (sh in shadows.painted()) {
				for (d in decos)
					for (r in p.decoration(d.start, d.end, d.kind, ui.scale, d.thickness, d.offset)) {
						var lx = align == Center ? (width - r.lineWidth) / 2 : align == Right ? width - r.lineWidth : 0.0;
						var c = sh.currentColor ? d.color : sh.color, rx = x + lx + r.x + sh.x, ry = y + r.y + sh.y;
						if (sh.blur > 0) canvas.shadow(rx, ry, r.width, r.height, 0, c, sh.blur) else canvas.rect(rx, ry, r.width, r.height, 0, c, 0, 0);
					}
				canvas.textShadow(p, x + sh.x, y + sh.y, width, align, sh.currentColor ? textColor() : sh.color, sh.blur,
					sh.currentColor && rich != null ? rich.colors : null);
			}
		draw(false);
		canvas.text(p, x, y, width, align, textColor(), rich != null ? rich.colors : null);
		draw(true);
	}

	// the decorations to draw: each range of the text, its line, its colour,
	// its thickness and an underline's offset (pixels; NaN: auto)
	function decorations(length:Int):Array<{start:Int, end:Int, kind:TextDecoration, color:Color, thickness:Float, offset:Float}> {
		var out = [];
		function add(n:Node, start:Int, end:Int) {
			var f = n.style.textDecoration;
			if (f == 0) return;
			// (the thickness the node's own, its percentage of its font size; the offset inherited)
			var size = n.font().size, thickness = n.style.textDecorationThickness.resolve(size), offset = Math.NaN, o:Null<Node> = n;
			while (o != null && Math.isNaN(offset)) {
				offset = o.style.textUnderlineOffset.resolve(size);
				o = o.parent;
			}
			for (k in [TextDecoration.Underline, TextDecoration.Overline, TextDecoration.LineThrough])
				if (f & (k : Int) != 0)
					out.push({start: start, end: end, kind: k, color: n.style.textDecorationColor ?? n.textColor(), thickness: thickness, offset: offset});
		}
		var n:Node = this;
		while (n != null) {
			add(n, 0, length);
			n = n.parent;
		}
		// (the spans', at their places in the text)
		var pos = 0;
		function walk(n:Node) {
			for (c in n.children) {
				if (!Std.isOfType(c, TextNode) || c.style.display == None) continue;
				var t:TextNode = cast c, start = pos;
				if (t.children.length > 0) walk(t) else pos += t.text.length;
				add(t, start, pos);
			}
		}
		if (children.length > 0) walk(this);
		return out;
	}
}
