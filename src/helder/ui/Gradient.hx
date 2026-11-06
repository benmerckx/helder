package helder.ui;

import helder.image.Image;

// A CSS gradient for a node's background (Style.backgroundImage):
// linear-gradient([angle | to side or corner,] stops) and
// radial-gradient([circle | ellipse] [size] [at position], stops), and
// their repeating- forms. Angles in deg, turn, rad or grad; sizes
// closest-side, farthest-side, closest-corner, farthest-corner (the
// default) or lengths; positions as keywords, percentages or pixels.
// Stops: a colour (Color.parse's), at a length or percentage or two (a
// band); positions left out spread evenly, going back clamped, as CSS
// says. Colours are mixed with their alpha premultiplied. Drawn into an
// Image the size of the box in the window's pixels (render).
class Gradient {
	public final linear:Bool;
	public final repeating:Bool;
	// linear: the direction, in degrees clockwise from up
	final angle:Float;
	// (to a corner: the angle follows the box's shape)
	final corner:Null<{x:Int, y:Int}>;
	// radial
	final circle:Bool;
	final size:String;
	final sizeX:Null<String>;
	final sizeY:Null<String>;
	final atX:String;
	final atY:String;
	final colors:Array<Color>;
	// each stop's position as written (null: to be spread), a length or a percentage
	final positions:Array<Null<String>>;

	function new(linear, repeating, angle, corner, circle, size, sizeX, sizeY, atX, atY, colors, positions) {
		this.linear = linear;
		this.repeating = repeating;
		this.angle = angle;
		this.corner = corner;
		this.circle = circle;
		this.size = size;
		this.sizeX = sizeX;
		this.sizeY = sizeY;
		this.atX = atX;
		this.atY = atY;
		this.colors = colors;
		this.positions = positions;
	}

	// whether a style value is a gradient
	public static function isGradient(s:String):Bool
		return s.indexOf("gradient(") >= 0;

	public static function parse(css:String):Gradient {
		var s = StringTools.trim(css);
		var open = s.indexOf("("), close = s.lastIndexOf(")");
		if (open < 0 || close < open) throw "Gradient: not a gradient: " + css;
		var fn = StringTools.trim(s.substr(0, open)).toLowerCase();
		var repeating = StringTools.startsWith(fn, "repeating-");
		if (repeating) fn = fn.substr(10);
		if (fn != "linear-gradient" && fn != "radial-gradient") throw "Gradient: not a gradient: " + css;
		var args = split(s.substring(open + 1, close));
		if (args.length == 0) throw "Gradient: no stops: " + css;
		var linear = fn == "linear-gradient";
		var angle = 180.0, corner:Null<{x:Int, y:Int}> = null;
		var circle = false, size = "farthest-corner", sizeX:Null<String> = null, sizeY:Null<String> = null, atX = "50%", atY = "50%";
		var first = args[0].toLowerCase(), stopsFrom = 0;
		if (linear) {
			if (StringTools.startsWith(first, "to ")) {
				var x = 0, y = 0;
				for (w in first.substr(3).split(" "))
					switch w {
						case "left": x = -1;
						case "right": x = 1;
						case "top": y = -1;
						case "bottom": y = 1;
						case "": continue;
						case _: throw "Gradient: a direction: " + first;
					}
				if (x != 0 && y != 0) corner = {x: x, y: y} else angle = x == 1 ? 90 : x == -1 ? 270 : y == -1 ? 0 : 180;
				stopsFrom = 1;
			} else {
				var a = angleOf(first);
				if (a != null) {
					angle = a;
					stopsFrom = 1;
				}
			}
		} else {
			// (the shape, size and position, when the first argument is not a stop)
			if (Color.tryParse(first.split(" ")[0]) == null) {
				var at = first.indexOf("at "), shape = at >= 0 ? first.substr(0, at) : first;
				var lengths:Array<String> = [];
				for (w in shape.split(" "))
					switch w {
						case "": continue;
						case "circle": circle = true;
						case "ellipse": circle = false;
						case "closest-side" | "farthest-side" | "closest-corner" | "farthest-corner": size = w;
						case _: lengths.push(w);
					}
				if (lengths.length == 1) {
					circle = true;
					size = "length";
					sizeX = sizeY = lengths[0];
				} else if (lengths.length == 2) {
					size = "length";
					sizeX = lengths[0];
					sizeY = lengths[1];
				}
				if (at >= 0) {
					var p = position(first.substr(at + 3));
					atX = p.x;
					atY = p.y;
				}
				stopsFrom = 1;
			}
		}
		var colors:Array<Color> = [], positions:Array<Null<String>> = [];
		for (k in stopsFrom...args.length) {
			// (a colour, then up to two positions; the colour may hold spaces: rgb(1 2 3))
			var a = args[k], cut = a.lastIndexOf(")");
			var colorPart = cut >= 0 ? a.substr(0, cut + 1) : a.split(" ")[0];
			var rest = StringTools.trim(a.substr(colorPart.length)).split(" ").filter(x -> x != "");
			var c = Color.tryParse(colorPart);
			if (c == null) throw "Gradient: a stop: " + a;
			colors.push(c);
			positions.push(rest.length > 0 ? rest[0] : null);
			if (rest.length > 1) {
				colors.push(c);
				positions.push(rest[1]);
			}
		}
		if (colors.length == 0) throw "Gradient: no stops: " + css;
		return new Gradient(linear, repeating, angle, corner, circle, size, sizeX, sizeY, atX, atY, colors, positions);
	}

	// the arguments, split at the commas outside parentheses
	static function split(s:String):Array<String> {
		var out = [], depth = 0, start = 0;
		for (i in 0...s.length) {
			var c = s.charAt(i);
			if (c == "(") depth++ else if (c == ")") depth-- else if (c == "," && depth == 0) {
				out.push(StringTools.trim(s.substring(start, i)));
				start = i + 1;
			}
		}
		var last = StringTools.trim(s.substr(start));
		if (last != "") out.push(last);
		return out;
	}

	@:allow(helder.ui.Transform) static function angleOf(s:String):Null<Float> {
		// (grad before rad: it ends the same)
		for (u in [{unit: "deg", k: 1.0}, {unit: "grad", k: 0.9}, {unit: "rad", k: 180 / Math.PI}, {unit: "turn", k: 360.0}])
			if (StringTools.endsWith(s, u.unit)) {
				var v = Std.parseFloat(s.substr(0, s.length - u.unit.length));
				return Math.isNaN(v) ? null : v * u.k;
			}
		return s == "0" ? 0 : null;
	}

	// a position: one or two keywords, percentages or lengths
	@:allow(helder.ui.Transform) static function position(s:String):{x:String, y:String} {
		var w = s.split(" ").filter(x -> x != "");
		var x = "50%", y = "50%";
		function kw(v:String):String
			return switch v {
				case "left" | "top": "0%";
				case "right" | "bottom": "100%";
				case "center": "50%";
				case _: v;
			}
		if (w.length == 1) {
			if (w[0] == "top" || w[0] == "bottom") y = kw(w[0]) else x = kw(w[0]);
		} else if (w.length >= 2) {
			// (keywords in either order)
			if (w[0] == "top" || w[0] == "bottom" || w[1] == "left" || w[1] == "right") {
				x = kw(w[1]);
				y = kw(w[0]);
			} else {
				x = kw(w[0]);
				y = kw(w[1]);
			}
		}
		return {x: x, y: y};
	}

	// a length or percentage of base, in the box's pixels at scale k
	static function len(v:String, base:Float, k:Float):Float {
		if (StringTools.endsWith(v, "%")) return Std.parseFloat(v) / 100 * base;
		var f = Std.parseFloat(StringTools.replace(v, "px", ""));
		return Math.isNaN(f) ? 0 : f * k;
	}

	// the gradient over a box of w by h pixels (k: the window's pixels per
	// UI pixel, for lengths in px): its shader's rows (not a whole canvas:
	// an app with a gradient keeps no rasterizer for it), straight
	public function render(w:Int, h:Int, k:Float = 1):Image {
		var img = new Image(w, h), px = img.pixels, g = shader(w, h, k), row = new haxe.ds.Vector<Float>(w * 4);
		if (!g.begin(helder.canvas.Matrix.IDENTITY)) return img;
		for (y in 0...h) {
			g.shade(0, y, w, row);
			for (x in 0...w) {
				var s = x * 4, o = (y * w + x) * 4, a = row[s + 3];
				if (!(a > 0)) continue;
				// (premultiplied: no channel over its alpha)
				var k = 255 / a;
				px.set(o, Std.int(row[s] * k + 0.5));
				px.set(o + 1, Std.int(row[s + 1] * k + 0.5));
				px.set(o + 2, Std.int(row[s + 2] * k + 0.5));
				px.set(o + 3, Std.int(a * 255 + 0.5));
			}
		}
		return img;
	}

	// as helder.canvas's shader over a box of w by h pixels from the origin
	// (k as render's): a linear gradient along the gradient line, or a
	// radial one whose matrix makes its circles the ellipse; the stops
	// interpolated premultiplied, as CSS's, from the first to the last (a
	// repeating gradient repeats them)
	public function shader(w:Float, h:Float, k:Float = 1):helder.canvas.Gradient {
		// the gradient line: its length; its start (t 0) and direction, or the centre and radii
		var length:Float, ox:Float, oy:Float, dx = 0.0, dy = 0.0, rx = 0.0, ry = 0.0;
		if (linear) {
			var a = angle;
			if (corner != null) {
				// (to a corner: perpendicular to the diagonal through the other two
				// corners, toward it: (x h, y w) in the box's pixels)
				a = Math.atan2(corner.x * h, -corner.y * w) * 180 / Math.PI;
			}
			var r = a * Math.PI / 180;
			dx = Math.sin(r);
			dy = -Math.cos(r);
			length = Math.abs(w * dx) + Math.abs(h * dy);
			ox = w / 2 - dx * length / 2;
			oy = h / 2 - dy * length / 2;
		} else {
			ox = len(atX, w, k);
			oy = len(atY, h, k);
			var left = ox, right = w - ox, top = oy, bottom = h - oy;
			switch size {
				case "length":
					rx = len(sizeX, w, k);
					ry = circle ? rx : len(sizeY, h, k);
				case "closest-side" | "farthest-side":
					var near = size == "closest-side";
					rx = near ? Math.min(left, right) : Math.max(left, right);
					ry = near ? Math.min(top, bottom) : Math.max(top, bottom);
					if (circle) rx = ry = near ? Math.min(rx, ry) : Math.max(rx, ry);
				case _:
					// (to a corner: the closest or farthest; an ellipse keeps the sides' ratio)
					var near = size == "closest-corner";
					inline function corner(a:Float, b:Float):Float
						return (near ? b * b < a * a : b * b > a * a) ? b : a;
					var bx = corner(left, right), by = corner(top, bottom);
					if (circle) rx = ry = Math.sqrt(bx * bx + by * by) else {
						var sx = near ? Math.min(left, right) : Math.max(left, right), sy = near ? Math.min(top, bottom) : Math.max(top, bottom);
						var ratio = sx > 0 ? sy / sx : 1;
						rx = ratio > 0 ? Math.sqrt(bx * bx + by * by / (ratio * ratio)) : bx;
						ry = rx * ratio;
					}
			}
			length = rx;
		}
		// the stops along the line (0 to 1): as written, the missing spread evenly, never going back
		var n = colors.length, at:Array<Float> = [];
		for (i in 0...n)
			at.push(positions[i] == null ? Math.NaN : len(positions[i], length, k) / (length > 0 ? length : 1));
		if (Math.isNaN(at[0])) at[0] = 0;
		if (Math.isNaN(at[n - 1])) at[n - 1] = n == 1 ? 0 : 1;
		var last = at[0];
		for (i in 1...n) {
			if (!Math.isNaN(at[i])) {
				if (at[i] < last) at[i] = last;
				last = at[i];
			}
		}
		var i = 1;
		while (i < n) {
			if (Math.isNaN(at[i])) {
				var j = i;
				while (Math.isNaN(at[j]))
					j++;
				for (q in i...j)
					at[q] = at[i - 1] + (at[j] - at[i - 1]) * (q - i + 1) / (j - i + 1);
				i = j;
			}
			i++;
		}
		// (the shader's 0 to 1: the first stop to the last, else a unit from the first)
		var t0 = at[0], span = at[n - 1] - t0;
		var repeat = repeating && span > 0;
		if (!(span > 0)) span = 1;
		var g:helder.canvas.Gradient;
		if (linear) {
			var l = length > 0 ? length : 1;
			g = new helder.canvas.Gradient.LinearGradient(ox + dx * l * t0, oy + dy * l * t0, ox + dx * l * (t0 + span), oy + dy * l * (t0 + span));
		} else {
			// (the ellipse the unit circle; one of no width a sliver, as CSS draws it)
			g = new helder.canvas.Gradient.RadialGradient(0, 0, t0, 0, 0, t0 + span);
			g.matrix.set(Math.max(rx, 1e-6), 0, 0, rx > 0 ? Math.max(ry, 1e-6) : 1e6, ox, oy);
		}
		g.premultiplied = true;
		for (q in 0...n)
			g.addStop((at[q] - t0) / span, colors[q]);
		if (repeat) g.spread = helder.canvas.Gradient.REPEAT;
		return g;
	}
}
