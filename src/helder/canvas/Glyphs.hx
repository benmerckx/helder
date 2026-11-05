package helder.canvas;

import helder.text.FontFile;
import helder.text.TextLayout;

// Text on a canvas: a helder.text layout's glyphs (shaped by helder's
// engine or the platform's, Shaping) as their outlines, added to a path
// then filled or stroked like any other. A class apart from Canvas, so an
// executable that draws no text keeps none of helder.text. Its path and
// buffers are kept: drawing a laid out text allocates nothing.
//
//   var layout = new TextLayout("Hello", new FontSet(face, 24), 1.2, Math.POSITIVE_INFINITY);
//   Glyphs.fill(canvas, layout, 10, 40, Paint.solid(0xFF000000));
final class Glyphs implements helder.text.Outline {
	static var shared:Null<Glyphs> = null;

	public final path = new Path();
	final transform:Array<Float> = [1, 0, 0, 1, 0, 0];

	public function new() {}

	static function get():Glyphs {
		if (shared == null) shared = new Glyphs();
		return shared;
	}

	// the layout's glyphs filled, its first line's baseline at (x, y)
	public static function fill(canvas:Painter, layout:TextLayout, x:Float, y:Float, paint:Paint) {
		var g = get();
		g.path.clear();
		g.add(layout, x, y);
		canvas.fill(g.path, paint);
	}

	public static function stroke(canvas:Painter, layout:TextLayout, x:Float, y:Float, style:Stroke, paint:Paint) {
		var g = get();
		g.path.clear();
		g.add(layout, x, y);
		canvas.stroke(g.path, style, paint);
	}

	// the layout's outlines added to path, its first line's baseline at (x, y);
	// scaleX squeezes the line horizontally from x (fillText's maxWidth)
	public function add(layout:TextLayout, x:Float, y:Float, scaleX = 1.0) {
		var lines = layout.lines;
		if (lines.length == 0) return;
		var first = lines[0];
		for (line in lines) {
			var by = y + line.top + line.baseline - (first.top + first.baseline);
			for (i in line.glyphStart...line.glyphEnd) {
				if (layout.glyphHidden(i)) continue;
				var face:FontFile = layout.glyphFont(i);
				var set = layout.glyphFontSet(i), s = set.scale(face);
				var gx = x + (layout.glyphX(i) + layout.glyphOffsetX(i)) * scaleX, gy = by + layout.glyphOffsetY(i);
				transform[0] = s * scaleX;
				transform[1] = 0;
				transform[2] = set.oblique ? 0.25 * s * scaleX : 0;
				transform[3] = -s;
				transform[4] = gx;
				transform[5] = gy;
				face.outline(layout.glyphId(i), this, transform);
			}
		}
	}

	public function moveTo(x:Float, y:Float)
		path.moveTo(x, y);

	public function lineTo(x:Float, y:Float)
		path.lineTo(x, y);

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float)
		path.quadTo(cx, cy, x, y);

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float)
		path.cubicTo(c1x, c1y, c2x, c2y, x, y);

	public function close()
		path.close();
}
