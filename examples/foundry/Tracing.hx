import Model;
import helder.text.FontFile;
import helder.text.Outline;
import helder.text.SystemFonts;
import helder.ui.Path;
import helder.ui.widgets.Theme;

// The letter to trace on the board: the interface's font's (Hanken
// Grotesk), its x-height (or cap height) made the face's, centred where
// the glyph is.
class Tracing {
	public static function path(char:String, face:Face, cx:Float, scale:Float, ox:Float, base:Float):Null<Path> {
		var f = SystemFonts.get().match(Theme.UI);
		if (f == null) return null;
		var cp = Charset.code(char);
		if (cp < 0) return null;
		var g = f.glyph(cp);
		if (g == 0) return null;
		var caps = char.toUpperCase() == char && char.toLowerCase() != char || Charset.tall(char);
		var ref = f.bounds(f.glyph(caps ? 72 : 120));
		if (ref == null || ref[3] <= 0) return null;
		var k = (caps ? face.metrics.capHeight : face.metrics.xHeight) / ref[3];
		var b = f.bounds(g);
		var mid = b == null ? f.advance(g) / 2 : (b[0] + b[2]) / 2;
		var out = new Collect(new Path(), x -> ox + (cx + (x - mid) * k) * scale, y -> base - y * k * scale);
		f.outline(g, out);
		return out.path;
	}
}

private class Collect implements Outline {
	public final path:Path;
	final fx:Float->Float;
	final fy:Float->Float;

	public function new(path, fx, fy) {
		this.path = path;
		this.fx = fx;
		this.fy = fy;
	}

	public function moveTo(x:Float, y:Float)
		path.moveTo(fx(x), fy(y));

	public function lineTo(x:Float, y:Float)
		path.lineTo(fx(x), fy(y));

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float)
		path.quadTo(fx(cx), fy(cy), fx(x), fy(y));

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float)
		path.cubicTo(fx(c1x), fy(c1y), fx(c2x), fy(c2y), fx(x), fy(y));

	public function close()
		path.close();
}
