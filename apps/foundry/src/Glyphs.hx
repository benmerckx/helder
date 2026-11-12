import Model;
import helder.text.FontEncoder.FontPoint;
import helder.ui.Path;

class Glyphs {
	// contours in font units as a path in pixels, the font's origin at (ox, base), y up
	public static function path(contours:Array<Array<FontPoint>>, scale:Float, ox:Float, base:Float):Path {
		var p = new Path();
		for (c in contours) {
			var n = c.length, start = 0;
			while (start < n && !c[start].on)
				start++;
			if (start == n) continue;
			inline function x(i:Int)
				return ox + c[i % n].x * scale;
			inline function y(i:Int)
				return base - c[i % n].y * scale;
			p.moveTo(x(start), y(start));
			var i = 1;
			while (i <= n) {
				var k = (start + i) % n;
				if (c[k].on) {
					p.lineTo(x(k), y(k));
					i++;
				} else {
					var next = (k + 1) % n;
					if (c[next].on) {
						p.quadTo(x(k), y(k), x(next), y(next));
						i += 2;
					} else {
						p.quadTo(x(k), y(k), (x(k) + x(next)) / 2, (y(k) + y(next)) / 2);
						i++;
					}
				}
			}
			p.close();
		}
		return p;
	}
}
