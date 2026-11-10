import Model;
import helder.ui.*;
import helder.ui.widgets.Theme;

// A glyph's ink small (the grid's cells, the first letters' chips): fitted
// to the cell's height by the face's whole range, centred on its advance;
// borrowed ink a step quieter than drawn.
class Thumb extends Node {
	final ws:Workshop;
	public var char(default, set):String;

	public function new(ws:Workshop, char:String) {
		super("thumb");
		this.ws = ws;
		this.char = char;
		style.pointerEvents = None;
	}

	function set_char(c:String):String {
		char = c;
		if (ui != null) ui.requestFrame();
		return c;
	}

	override public function hasContent():Bool
		return true;

	// (its path kept while its shape and box are the same: the renderer
	// keeps a path's pixels while it is given the same one)
	var drawn:Null<{shape:Ink.Shape, x:Float, y:Float, w:Float, h:Float, path:Path}> = null;

	override public function paintContent(c:Canvas, x:Float, y:Float, w:Float, h:Float) {
		var f = ws.value(), s = Ink.shape(f, char);
		if (s.contours.length == 0) return;
		var d = drawn;
		if (d == null || d.shape != s || d.x != x || d.y != y || d.w != w || d.h != h) {
			var m = f.metrics, top = Math.max(m.ascender, m.capHeight) + 60, bottom = m.descender - 40;
			var scale = Math.min(h / (top - bottom), w * 0.9 / Math.max(s.advance, 1));
			var ox = x + (w - s.advance * scale) / 2, base = y + (h - (top - bottom) * scale) / 2 + top * scale;
			drawn = d = {shape: s, x: x, y: y, w: w, h: h, path: Glyphs.path(s.contours, scale, ox, base)};
		}
		c.path(d.path, Model.drawn(f, char) ? Theme.c("fg") : Theme.c("fg3"));
	}
}
