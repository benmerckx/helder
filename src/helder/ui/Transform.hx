package helder.ui;

import helder.canvas.Matrix;

// A CSS transform (Style.transform): translate(x[, y]), translateX/Y,
// scale(x[, y]), scaleX/Y, rotate(a), skew(x[, y]), skewX/Y and
// matrix(a, b, c, d, e, f), composed left to right as CSS composes them,
// about the transform origin (Style.transformOrigin, CSS's: the box's
// centre by default). Lengths in px or a percentage of the box (translate),
// angles as Gradient's (deg, turn, rad, grad; rotate and skew also take a
// bare number of degrees). A transform moves how a node and its subtree are
// drawn and where the pointer hits them, not their layout.
class Transform {
	// the functions in order: their names and arguments (lengths in pixels,
	// or percentages where percent is set; angles in degrees)
	final names:Array<String>;
	final args:Array<Array<Float>>;
	final percent:Array<Array<Bool>>;

	// the functions as parse reads them, without the text: names (CSS's,
	// any case: "translateX"), arguments, and which are percentages (none
	// when not given): new Transform(["translate"], [[-50, -50]], [[true,
	// true]]) is translate(-50%, -50%)
	public function new(names:Array<String>, args:Array<Array<Float>>, ?percent:Array<Array<Bool>>) {
		if (args.length != names.length || (percent != null && percent.length != names.length))
			throw "Transform: " + names.length + " functions, " + args.length + " argument lists";
		names = [for (n in names) n.toLowerCase()];
		for (k => n in names) {
			var vs = args[k];
			if (!arity(n, vs.length)) throw "Transform: wrong arguments to " + n + ": " + vs;
			if (percent != null && percent[k].length != vs.length) throw "Transform: percentages not one to an argument of " + n;
			for (v in vs)
				if (Math.isNaN(v)) throw "Transform: not a value in " + n;
		}
		this.names = names;
		this.args = args;
		this.percent = percent ?? [for (vs in args) [for (_ in vs) false]];
	}

	// (whether name takes count arguments; throws on a name not CSS's)
	static function arity(name:String, count:Int):Bool
		return switch name {
			case "translate" | "scale" | "skew": count == 1 || count == 2;
			case "translatex" | "translatey" | "scalex" | "scaley" | "rotate" | "skewx" | "skewy": count == 1;
			case "matrix": count == 6;
			case _: throw "Transform: unknown function: " + name;
		}

	public static function parse(css:String):Transform {
		var names = [], args = [], percent = [];
		var s = StringTools.trim(css);
		if (s == "none" || s == "") return new Transform(names, args, percent);
		var i = 0;
		while (i < s.length) {
			var open = s.indexOf("(", i), close = s.indexOf(")", i);
			if (open < 0 || close < open) throw "Transform: not a transform: " + css;
			var name = StringTools.trim(s.substring(i, open)).toLowerCase();
			var raw = s.substring(open + 1, close).split(",").map(StringTools.trim);
			if (raw.length == 1) raw = raw[0].split(" ").filter(x -> x != "");
			var vs = [], ps = [];
			var angle = name.indexOf("rotate") == 0 || name.indexOf("skew") == 0;
			for (r in raw) {
				var v:Null<Float> = if (angle) {
					var a = Gradient.angleOf(r);
					a == null ? Std.parseFloat(r) : a;
				} else if (StringTools.endsWith(r, "%")) Std.parseFloat(r) else Std.parseFloat(StringTools.replace(r, "px", ""));
				if (v == null || Math.isNaN(v)) throw "Transform: not a value: " + r + " in " + css;
				vs.push(v);
				ps.push(!angle && StringTools.endsWith(r, "%"));
			}
			var count = try arity(name, vs.length) catch (e:String) throw e + " in " + css;
			if (!count) throw "Transform: wrong arguments to " + name + " in " + css;
			names.push(name);
			args.push(vs);
			percent.push(ps);
			i = close + 1;
		}
		return new Transform(names, args, percent);
	}

	public static function translate(x:Float, y:Float):Transform
		return new Transform(["translate"], [[x, y]], [[false, false]]);

	public static function scale(x:Float, ?y:Float):Transform
		return new Transform(["scale"], [[x, y == null ? x : y]], [[false, false]]);

	// clockwise, in degrees
	public static function rotate(degrees:Float):Transform
		return new Transform(["rotate"], [[degrees]], [[false]]);

	public static function matrix(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float):Transform
		return new Transform(["matrix"], [[a, b, c, d, e, f]], [[false, false, false, false, false, false]]);

	// this transform, then other (CSS's "this other")
	public function then(other:Transform):Transform
		return new Transform(names.concat(other.names), args.concat(other.args), percent.concat(other.percent));

	public function isIdentity():Bool
		return names.length == 0;

	// the matrix for a box of w by h pixels, about its top left (x' = a x +
	// c y + e, y' = b x + d y + f)
	public function toMatrix(w:Float, h:Float):Matrix {
		var m = new Matrix();
		for (i in 0...names.length) {
			var v = args[i], p = percent[i];
			inline function len(k:Int, base:Float):Float
				return k >= v.length ? 0 : p[k] ? v[k] / 100 * base : v[k];
			inline function tan(k:Int):Float
				return k >= v.length ? 0 : Math.tan(v[k] * Math.PI / 180);
			switch names[i] {
				case "translate": m.translate(len(0, w), len(1, h));
				case "translatex": m.translate(len(0, w), 0);
				case "translatey": m.translate(0, len(0, h));
				case "scale": m.scale(v[0], v.length > 1 ? v[1] : v[0]);
				case "scalex": m.scale(v[0], 1);
				case "scaley": m.scale(1, v[0]);
				case "rotate": m.rotate(v[0] * Math.PI / 180);
				case "skew": m.transform(1, tan(1), tan(0), 1, 0, 0);
				case "skewx": m.transform(1, 0, tan(0), 1, 0, 0);
				case "skewy": m.transform(1, tan(0), 0, 1, 0, 0);
				case _: m.transform(v[0], v[1], v[2], v[3], v[4], v[5]); // matrix
			}
		}
		return m;
	}

	// a transform origin as CSS writes it ("left top", "50% 0", "10px 20px"):
	// its x and y (one value: the other is the centre)
	public static function origin(css:String):Array<Dim> {
		var p = Gradient.position(StringTools.trim(css));
		return [Dim.parse(p.x), Dim.parse(p.y)];
	}

	// a transform a fraction k of the way from a to b (null: none), as CSS
	// interpolates them: function by function where both have the same
	// ones, none against the other's functions at their identity; else
	// their matrices' entries (a box's pixels: a percentage translation as
	// it is at k's end)
	public static function between(a:Null<Transform>, b:Null<Transform>, k:Float):Null<Transform> {
		if (a == null && b == null) return null;
		if (a == null || a.names.length == 0) a = b.identity();
		if (b == null || b.names.length == 0) b = a.identity();
		var same = a.names.length == b.names.length;
		if (same)
			for (i in 0...a.names.length)
				if (a.names[i] != b.names[i] || a.args[i].length != b.args[i].length || a.percent[i].join(",") != b.percent[i].join(",")) same = false;
		if (!same) {
			var m = a.toMatrix(0, 0), n = b.toMatrix(0, 0);
			return matrix(m.a + (n.a - m.a) * k, m.b + (n.b - m.b) * k, m.c + (n.c - m.c) * k, m.d + (n.d - m.d) * k, m.e + (n.e - m.e) * k,
				m.f + (n.f - m.f) * k);
		}
		return new Transform(a.names.copy(), [for (i in 0...a.args.length) [for (j in 0...a.args[i].length) a.args[i][j] + (b.args[i][j] - a.args[i][j]) * k]],
			[for (p in a.percent) p.copy()]);
	}

	// (its functions at their identities: no translation, scale 1, no turn or skew)
	function identity():Transform
		return new Transform(names.copy(), [
			for (i in 0...names.length)
				[for (j in 0...args[i].length) names[i] == "matrix" ? (j == 0 || j == 3 ? 1.0 : 0.0) : StringTools.startsWith(names[i], "scale") ? 1.0 : 0.0]
		], [for (p in percent) p.copy()]);

	public function toString():String
		return [for (i in 0...names.length) names[i] + "(" + [for (k in 0...args[i].length) args[i][k] + (percent[i][k] ? "%" : "")].join(", ") + ")"].join(" ");
}
