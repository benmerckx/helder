import Board;
import helder.canvas.*;
import helder.canvas.Gradient;
import helder.canvas.Stroke;

// Greybox drawing: flat shapes, a soft glow, a few strokes, and letters
// drawn as lines (no font to load: the same on every platform and the web).
class Sketch {
	static final path = new Path();
	static final pen = new Stroke(1);

	public static function alpha(color:Int, a:Float):Int {
		var k = Std.int(Math.max(0, Math.min(1, a)) * ((color >>> 24) & 0xFF));
		return (k << 24) | (color & 0xFFFFFF);
	}

	public static function mix(a:Int, b:Int, t:Float):Int {
		inline function ch(c:Int, s:Int)
			return (c >>> s) & 0xFF;
		var out = 0;
		for (s in [0, 8, 16, 24])
			out |= Std.int(ch(a, s) + (ch(b, s) - ch(a, s)) * t) << s;
		return out;
	}

	public static function circle(c:Painter, x:Float, y:Float, r:Float, color:Int) {
		path.clear();
		path.arc(x, y, r, 0, Math.PI * 2);
		c.fill(path, Paint.solid(color));
	}

	public static function ring(c:Painter, x:Float, y:Float, r:Float, width:Float, color:Int) {
		path.clear();
		path.arc(x, y, r, 0, Math.PI * 2);
		pen.width = width;
		pen.dash = null;
		c.stroke(path, pen, Paint.solid(color));
	}

	public static function box(c:Painter, x:Float, y:Float, w:Float, h:Float, color:Int, round = 0.0) {
		path.clear();
		if (round > 0) path.roundRect(x, y, w, h, round) else path.rect(x, y, w, h);
		c.fill(path, Paint.solid(color));
	}

	public static function outline(c:Painter, x:Float, y:Float, w:Float, h:Float, width:Float, color:Int, round = 0.0) {
		path.clear();
		if (round > 0) path.roundRect(x, y, w, h, round) else path.rect(x, y, w, h);
		pen.width = width;
		pen.dash = null;
		c.stroke(path, pen, Paint.solid(color));
	}

	public static function poly(c:Painter, points:Array<Float>, color:Int) {
		path.clear();
		path.moveTo(points[0], points[1]);
		var k = 2;
		while (k < points.length) {
			path.lineTo(points[k], points[k + 1]);
			k += 2;
		}
		path.close();
		c.fill(path, Paint.solid(color));
	}

	public static function line(c:Painter, points:Array<Float>, width:Float, color:Int, dash = 0.0, offset = 0.0) {
		path.clear();
		path.moveTo(points[0], points[1]);
		var k = 2;
		while (k < points.length) {
			path.lineTo(points[k], points[k + 1]);
			k += 2;
		}
		pen.width = width;
		pen.cap = Cap.round;
		pen.join = Join.round;
		pen.dash = dash > 0 ? new Dash([dash, dash * 1.2], offset) : null;
		c.stroke(path, pen, Paint.solid(color));
	}

	public static function glow(c:Painter, x:Float, y:Float, r:Float, color:Int) {
		var g = new RadialGradient(x, y, 0, x, y, r);
		g.addStop(0, color).addStop(0.4, alpha(color, 0.35)).addStop(1, alpha(color, 0));
		path.clear();
		path.arc(x, y, r, 0, Math.PI * 2);
		c.fill(path, Paint.shaded(g));
	}

	// letters on a 2 x 4 grid (y down), each a few polylines
	static final LETTERS = [
		"A" => "04 01 10 21 24|02 22", "B" => "00 04|00 10 21 12 02|12 23 14 04", "C" => "20 00 04 24", "D" => "00 04 14 23 21 10 00",
		"E" => "20 00 04 24|02 12", "F" => "20 00 04|02 12", "G" => "20 00 04 24 22 12", "H" => "00 04|20 24|02 22", "I" => "00 20|10 14|04 24",
		"J" => "20 23 14 04 03", "K" => "00 04|20 02 24", "L" => "00 04 24", "M" => "04 00 12 20 24", "N" => "04 00 24 20",
		"O" => "00 20 24 04 00", "P" => "04 00 20 22 02", "Q" => "00 20 24 04 00|13 24", "R" => "04 00 20 22 02|12 24",
		"S" => "20 00 02 22 24 04", "T" => "00 20|10 14", "U" => "00 04 24 20", "V" => "00 14 20", "W" => "00 04 12 24 20",
		"X" => "00 24|20 04", "Y" => "00 12 20|12 14", "Z" => "00 20 04 24", "0" => "00 20 24 04 00", "1" => "01 10 14|04 24",
		"2" => "00 20 22 02 04 24", "3" => "00 20 24 04|02 22", "4" => "00 02 22|20 24", "5" => "20 00 02 22 24 04",
		"6" => "20 00 04 24 22 02", "7" => "00 20 14", "8" => "00 20 24 04 00|02 22", "9" => "22 02 00 20 24 04", "/" => "04 20",
		":" => "11 11|13 13", "-" => "02 22", "." => "14 14", "," => "14 05", "<" => "20 02 24", ">" => "00 22 04", "'" => "10 11"
	];

	public static function width(text:String, size:Float):Float
		return text.length * size * 0.75 - size * 0.25;

	// text whose letters are size tall, centred on x, its middle at y
	public static function text(c:Painter, text:String, x:Float, y:Float, size:Float, color:Int, weight = 0.12) {
		var u = size / 4, left = x - width(text, size) / 2, top = y - size / 2;
		path.clear();
		for (k in 0...text.length) {
			var shape = LETTERS.get(text.charAt(k).toUpperCase());
			if (shape == null) continue;
			var ox = left + k * size * 0.75;
			for (stroke in shape.split("|")) {
				var points = stroke.split(" ");
				for (n in 0...points.length) {
					var px = ox + Std.parseInt(points[n].charAt(0)) * u, py = top + Std.parseInt(points[n].charAt(1)) * u;
					if (n == 0) path.moveTo(px, py) else path.lineTo(px, py);
				}
				if (points.length == 1) path.lineTo(ox + Std.parseInt(points[0].charAt(0)) * u + 0.01, top + Std.parseInt(points[0].charAt(1)) * u);
			}
		}
		pen.width = size * weight;
		pen.cap = Cap.round;
		pen.join = Join.round;
		pen.dash = null;
		c.stroke(path, pen, Paint.solid(color));
	}

	// the moth as a few shapes, in world units (y up): a pale body, two
	// wings beating by its flight's phase or folded back at rest, antennae
	public static function moth(c:Painter, f:Flight, t:Float) {
		var x = f.x, y = f.y, face = f.turn, k = 1.3;
		glow(c, x, y, 1.2, 0x60B07CFF);
		var rest = 1 - f.fly;
		function wing(lag:Float, length:Float, color:Int) {
			var b = Math.sin(f.phase - lag);
			// (folded: lying back over the body; flying: from over the back to below it)
			var a = rest * (Math.PI - 0.3 + Math.sin(t * 1.3 + lag) * 0.05) + f.fly * (Math.PI + b * 1.25);
			var rx = x + 0.03 * face, ry = y + 0.04, l = length * k;
			poly(c, [
				rx, ry,
				rx + Math.cos(a) * l * face, ry + Math.sin(a) * l,
				rx + Math.cos(a + 0.6) * l * 0.75 * face, ry + Math.sin(a + 0.6) * l * 0.75
			], color);
		}
		wing(0.5, 0.4, 0xFFA9A1C4);
		path.clear();
		path.ellipse(x - 0.03 * face, y, 0.22 * k, 0.08 * k, -f.tilt * face, 0, Math.PI * 2);
		c.fill(path, Paint.solid(0xFFCDC3E8));
		circle(c, x + 0.24 * face, y + 0.03, 0.08, 0xFFE4DCF7);
		circle(c, x + 0.27 * face, y + 0.05, 0.025, 0xFF201C2E);
		line(c, [x + 0.27 * face, y + 0.1, x + 0.38 * face, y + 0.3, x + 0.46 * face, y + 0.33], 0.03, 0xFFE8E2F0);
		line(c, [x + 0.24 * face, y + 0.1, x + 0.31 * face, y + 0.32, x + 0.38 * face, y + 0.36], 0.025, 0xAAE8E2F0);
		wing(0, 0.46, 0xFFFFFFFF);
	}

	// the board's ground and its stone, a lighter lip where something can stand
	public static function stones(c:Painter, board:Board) {
		box(c, 0, 0, board.cols, board.rows, 0xFF161927);
		for (j in 0...board.rows)
			for (i in 0...board.cols)
				if (board.stone(i, j)) {
					box(c, i + 0.02, j + 0.02, 0.96, 0.96, 0xFF454A61, 0.06);
					if (!board.stone(i, j + 1) && j + 1 < board.rows) box(c, i + 0.02, j + 0.88, 0.96, 0.1, 0xFF5D637C, 0.04);
				}
	}
}
