package hxmc.ui;

import haxe.ds.Vector;
import haxe.io.Bytes;
import hxmc.text.Rasterizer;

// An SVG document for icons and drawings: parsed once (Svg.parse), drawn
// into an Image at any size (render: the viewBox fitted as
// preserveAspectRatio says, xMidYMid meet by default). The static subset
// icon sets use: svg, g, path (all of its data, arcs as cubic curves), rect
// (rounded), circle, ellipse, line, polyline, polygon; fill and stroke (a
// colour: hex, rgb(), rgba(), CSS's names, currentColor: render's color;
// none), their opacities, opacity (a group's composited as one), fill-rule,
// stroke-width, stroke-linecap, stroke-linejoin, stroke-miterlimit,
// transform; presentation attributes, style="" and the inherited ones
// passed down. Not drawn: text, images, gradients and patterns (a url()
// paint draws nothing), clipping, masks, filters, markers, dashes, use;
// defs, title and the like are skipped.
class Svg {
	// the intrinsic size: width and height, else the viewBox's, else 300 by 150
	public final width:Float;
	public final height:Float;

	final viewBox:Null<{x:Float, y:Float, w:Float, h:Float}>;
	// preserveAspectRatio: align (0, 0.5 or 1 on each axis; null: none) and slice
	final alignX:Null<Float>;
	final alignY:Null<Float>;
	final slice:Bool;
	final root:SvgGroup;

	function new(width, height, viewBox, alignX, alignY, slice, root) {
		this.width = width;
		this.height = height;
		this.viewBox = viewBox;
		this.alignX = alignX;
		this.alignY = alignY;
		this.slice = slice;
		this.root = root;
	}

	public static function parse(text:String):Svg {
		var doc = Xml.parse(text);
		var el:Xml = null;
		for (e in doc.elements())
			if (local(e.nodeName) == "svg") el = e;
		if (el == null) throw "Svg: no svg element";
		var vb:Null<{x:Float, y:Float, w:Float, h:Float}> = null;
		var v = el.get("viewBox");
		if (v != null) {
			var n = SvgParse.numbers(v);
			if (n.length == 4 && n[2] > 0 && n[3] > 0) vb = {x: n[0], y: n[1], w: n[2], h: n[3]};
		}
		var w = length(el.get("width")), h = length(el.get("height"));
		if (Math.isNaN(w)) w = vb != null ? (Math.isNaN(h) ? vb.w : h * vb.w / vb.h) : 300;
		if (Math.isNaN(h)) h = vb != null ? w * vb.h / vb.w : 150;
		var ax:Null<Float> = 0.5, ay:Null<Float> = 0.5, slice = false;
		var par = el.get("preserveAspectRatio");
		if (par != null) {
			var p = StringTools.trim(par).split(" ").filter(s -> s != "");
			if (p.length > 0) {
				var a = p[0];
				if (a == "none") {
					ax = null;
					ay = null;
				} else if (a.length == 8) {
					inline function pos(s:String):Float
						return s == "Min" ? 0 : s == "Max" ? 1 : 0.5;
					ax = pos(a.substr(1, 3));
					ay = pos(a.substr(5, 3));
				}
				slice = p.length > 1 && p[1] == "slice";
			}
		}
		var root = SvgParse.root(el);
		return new Svg(w, h, vb, ax, ay, slice, root);
	}

	// an element's name without its namespace prefix
	static function local(name:String):String {
		var i = name.indexOf(":");
		return i < 0 ? name : name.substr(i + 1);
	}

	static function length(s:Null<String>):Float {
		if (s == null) return Math.NaN;
		s = StringTools.trim(s);
		if (StringTools.endsWith(s, "%")) return Math.NaN;
		return Std.parseFloat(s);
	}

	// the drawing at width by height pixels (its intrinsic size by
	// default), currentColor painted color (black)
	public function render(?width:Int, ?height:Int, color:Color = 0xFF000000):Image {
		var w:Int = width != null ? width : Std.int(Math.ceil(this.width)), h:Int = height != null ? height : Std.int(Math.ceil(this.height));
		var canvas = new SvgCanvas(w, h, color);
		// the viewport: the viewBox fitted (or the user units at the intrinsic size)
		var m = Matrix.IDENTITY;
		if (viewBox != null) {
			var sx = w / viewBox.w, sy = h / viewBox.h;
			if (alignX == null) m = new Matrix(sx, 0, 0, sy, -viewBox.x * sx, -viewBox.y * sy) else {
				var s = slice ? Math.max(sx, sy) : Math.min(sx, sy);
				var tx = (w - viewBox.w * s) * alignX, ty = (h - viewBox.h * s) * alignY;
				m = new Matrix(s, 0, 0, s, tx - viewBox.x * s, ty - viewBox.y * s);
			}
		} else
			m = new Matrix(w / this.width, 0, 0, h / this.height, 0, 0);
		canvas.group(root, m);
		return canvas.image();
	}
}

// an affine transform: x' = a x + c y + e, y' = b x + d y + f
class Matrix {
	public static final IDENTITY = new Matrix(1, 0, 0, 1, 0, 0);

	public final a:Float;
	public final b:Float;
	public final c:Float;
	public final d:Float;
	public final e:Float;
	public final f:Float;

	public function new(a, b, c, d, e, f) {
		this.a = a;
		this.b = b;
		this.c = c;
		this.d = d;
		this.e = e;
		this.f = f;
	}

	// this after m (m's points then this one's)
	public function times(m:Matrix):Matrix
		return new Matrix(a * m.a + c * m.b, b * m.a + d * m.b, a * m.c + c * m.d, b * m.c + d * m.d, a * m.e + c * m.f + e, b * m.e + d * m.f + f);

	public inline function x(px:Float, py:Float):Float
		return a * px + c * py + e;

	public inline function y(px:Float, py:Float):Float
		return b * px + d * py + f;

	// how much it scales lengths (the square root of its area's)
	public function scale():Float
		return Math.sqrt(Math.abs(a * d - b * c));
}

enum SvgPaint {
	None;
	Rgba(c:Color);
	Current;
}

// the painting properties, as inherited
class SvgStyle {
	public var fill:SvgPaint = Rgba(0xFF000000);
	public var stroke:SvgPaint = None;
	public var fillOpacity = 1.0;
	public var strokeOpacity = 1.0;
	public var strokeWidth = 1.0;
	// 0 butt, 1 round, 2 square
	public var cap = 0;
	// 0 miter, 1 round, 2 bevel
	public var join = 0;
	public var miterLimit = 4.0;
	public var evenOdd = false;
	// what currentColor is when the color property sets it (else render's)
	public var color:Null<Color> = null;

	public function new() {}

	public static function initial():SvgStyle
		return new SvgStyle();

	public function copy():SvgStyle {
		var s = new SvgStyle();
		s.fill = fill;
		s.stroke = stroke;
		s.fillOpacity = fillOpacity;
		s.strokeOpacity = strokeOpacity;
		s.strokeWidth = strokeWidth;
		s.cap = cap;
		s.join = join;
		s.miterLimit = miterLimit;
		s.evenOdd = evenOdd;
		s.color = color;
		return s;
	}
}

class SvgGroup {
	public final matrix:Matrix;
	public final opacity:Float;
	public final children:Array<Any> = [];

	public function new(matrix, opacity) {
		this.matrix = matrix;
		this.opacity = opacity;
	}
}

class SvgShape {
	// the path: 0 move (x, y), 1 line (x, y), 2 cubic (c1, c2, to), 3 close
	public final path:Array<Float>;
	public final matrix:Matrix;
	public final style:SvgStyle;
	public final opacity:Float;

	public function new(path, matrix, style, opacity) {
		this.path = path;
		this.matrix = matrix;
		this.style = style;
		this.opacity = opacity;
	}
}

// the parsing: elements into groups and shapes, path data, transforms, colours
class SvgParse {
	static final SKIP = ["defs" => true, "title" => true, "desc" => true, "metadata" => true, "clipPath" => true, "mask" => true, "linearGradient" => true,
		"radialGradient" => true, "pattern" => true, "symbol" => true, "marker" => true, "filter" => true, "style" => true, "script" => true];

	// the outermost svg element's group: its own properties for its children
	public static function root(el:Xml):SvgGroup {
		var props = properties(el), style = SvgStyle.initial();
		apply(style, props);
		var g = new SvgGroup(Matrix.IDENTITY, props.exists("opacity") ? clamp01(Std.parseFloat(props.get("opacity"))) : 1.0);
		children(el, g, style);
		return g;
	}

	public static function children(el:Xml, into:SvgGroup, inherited:SvgStyle) {
		for (c in el.elements()) {
			var name = c.nodeName;
			var i = name.indexOf(":");
			if (i >= 0) name = name.substr(i + 1);
			if (SKIP.exists(name) || c.get("display") == "none") continue;
			var props = properties(c);
			if (props.get("display") == "none") continue;
			var style = inherited.copy();
			apply(style, props);
			var m = c.get("transform") == null ? Matrix.IDENTITY : transform(c.get("transform"));
			var opacity = props.exists("opacity") ? clamp01(Std.parseFloat(props.get("opacity"))) : 1.0;
			switch name {
				case "g" | "svg" | "a":
					if (name == "svg") {
						var x = num(c.get("x")), y = num(c.get("y"));
						if (x != 0 || y != 0) m = new Matrix(1, 0, 0, 1, x, y).times(m);
					}
					var g = new SvgGroup(m, opacity);
					children(c, g, style);
					into.children.push(g);
				case _:
					var path = shape(name, c);
					if (path != null && path.length > 0) into.children.push(new SvgShape(path, m, style, opacity));
			}
		}
	}

	// presentation attributes, then style="" over them
	static function properties(el:Xml):Map<String, String> {
		var p = new Map<String, String>();
		for (a in el.attributes())
			p.set(a, el.get(a));
		var s = el.get("style");
		if (s != null)
			for (decl in s.split(";")) {
				var i = decl.indexOf(":");
				if (i < 0) continue;
				p.set(StringTools.trim(decl.substr(0, i)), StringTools.trim(decl.substr(i + 1)));
			}
		return p;
	}

	static function apply(s:SvgStyle, p:Map<String, String>) {
		// (color first: currentColor in this element's fill is its)
		if (p.exists("color")) {
			var c = color(p.get("color"), s.color);
			if (c != null) s.color = c;
		}
		if (p.exists("fill")) s.fill = paint(p.get("fill"), s);
		if (p.exists("stroke")) s.stroke = paint(p.get("stroke"), s);
		if (p.exists("fill-opacity")) s.fillOpacity = clamp01(Std.parseFloat(p.get("fill-opacity")));
		if (p.exists("stroke-opacity")) s.strokeOpacity = clamp01(Std.parseFloat(p.get("stroke-opacity")));
		if (p.exists("stroke-width")) {
			var w = Std.parseFloat(p.get("stroke-width"));
			if (!Math.isNaN(w) && w >= 0) s.strokeWidth = w;
		}
		if (p.exists("stroke-linecap")) s.cap = switch p.get("stroke-linecap") {
			case "round": 1;
			case "square": 2;
			case "butt": 0;
			case _: s.cap;
		}
		if (p.exists("stroke-linejoin")) s.join = switch p.get("stroke-linejoin") {
			case "round": 1;
			case "bevel": 2;
			case "miter" | "miter-clip" | "arcs": 0;
			case _: s.join;
		}
		if (p.exists("stroke-miterlimit")) {
			var l = Std.parseFloat(p.get("stroke-miterlimit"));
			if (l >= 1) s.miterLimit = l;
		}
		if (p.exists("fill-rule")) s.evenOdd = p.get("fill-rule") == "evenodd";
	}

	static function paint(v:String, s:SvgStyle):SvgPaint {
		v = StringTools.trim(v);
		if (v == "none") return None;
		if (v == "currentColor" || v == "currentcolor") return s.color != null ? Rgba(s.color) : Current;
		// (a gradient or pattern: not drawn)
		if (StringTools.startsWith(v, "url(")) return None;
		var c = color(v, s.color);
		return c == null ? None : Rgba(c);
	}

	static inline function clamp01(f:Float):Float
		return Math.isNaN(f) ? 1 : f < 0 ? 0 : f > 1 ? 1 : f;

	static function num(s:Null<String>):Float {
		if (s == null) return 0;
		var f = Std.parseFloat(s);
		return Math.isNaN(f) ? 0 : f;
	}

	// a shape element's path (null: not one)
	static function shape(name:String, el:Xml):Null<Array<Float>> {
		var p:Array<Float> = [];
		switch name {
			case "path":
				var d = el.get("d");
				return d == null ? null : pathData(d);
			case "rect":
				var x = num(el.get("x")), y = num(el.get("y")), w = num(el.get("width")), h = num(el.get("height"));
				if (w <= 0 || h <= 0) return null;
				var rx = el.get("rx") == null ? Math.NaN : num(el.get("rx")), ry = el.get("ry") == null ? Math.NaN : num(el.get("ry"));
				if (Math.isNaN(rx)) rx = Math.isNaN(ry) ? 0 : ry;
				if (Math.isNaN(ry)) ry = rx;
				rx = Math.min(Math.max(rx, 0), w / 2);
				ry = Math.min(Math.max(ry, 0), h / 2);
				if (rx == 0 || ry == 0) {
					p.push(0); p.push(x); p.push(y);
					p.push(1); p.push(x + w); p.push(y);
					p.push(1); p.push(x + w); p.push(y + h);
					p.push(1); p.push(x); p.push(y + h);
					p.push(3);
				} else {
					var k = 0.5522847498307936, kx = rx * k, ky = ry * k;
					p.push(0); p.push(x + rx); p.push(y);
					p.push(1); p.push(x + w - rx); p.push(y);
					cubic(p, x + w - rx + kx, y, x + w, y + ry - ky, x + w, y + ry);
					p.push(1); p.push(x + w); p.push(y + h - ry);
					cubic(p, x + w, y + h - ry + ky, x + w - rx + kx, y + h, x + w - rx, y + h);
					p.push(1); p.push(x + rx); p.push(y + h);
					cubic(p, x + rx - kx, y + h, x, y + h - ry + ky, x, y + h - ry);
					p.push(1); p.push(x); p.push(y + ry);
					cubic(p, x, y + ry - ky, x + rx - kx, y, x + rx, y);
					p.push(3);
				}
			case "circle" | "ellipse":
				var cx = num(el.get("cx")), cy = num(el.get("cy"));
				var rx = name == "circle" ? num(el.get("r")) : num(el.get("rx")), ry = name == "circle" ? rx : num(el.get("ry"));
				if (name == "ellipse") {
					if (el.get("rx") == null) rx = ry;
					if (el.get("ry") == null) ry = rx;
				}
				if (rx <= 0 || ry <= 0) return null;
				ellipse(p, cx, cy, rx, ry);
			case "line":
				p.push(0); p.push(num(el.get("x1"))); p.push(num(el.get("y1")));
				p.push(1); p.push(num(el.get("x2"))); p.push(num(el.get("y2")));
			case "polyline" | "polygon":
				var n = numbers(el.get("points") ?? "");
				if (n.length < 2) return null;
				var i = 0;
				while (i + 1 < n.length) {
					p.push(i == 0 ? 0 : 1);
					p.push(n[i]);
					p.push(n[i + 1]);
					i += 2;
				}
				if (name == "polygon") p.push(3);
			case _:
				return null;
		}
		return p;
	}

	static inline function cubic(p:Array<Float>, x1:Float, y1:Float, x2:Float, y2:Float, x:Float, y:Float) {
		p.push(2);
		p.push(x1);
		p.push(y1);
		p.push(x2);
		p.push(y2);
		p.push(x);
		p.push(y);
	}

	// an ellipse from its right point, through its bottom (positive y) first, closed
	public static function ellipse(p:Array<Float>, cx:Float, cy:Float, rx:Float, ry:Float) {
		var k = 0.5522847498307936, kx = rx * k, ky = ry * k;
		p.push(0); p.push(cx + rx); p.push(cy);
		cubic(p, cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry);
		cubic(p, cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy);
		cubic(p, cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry);
		cubic(p, cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy);
		p.push(3);
	}

	// the numbers in a list: "1,2 3-4.5e2.5" (separators, signs and dots split them)
	public static function numbers(s:String):Array<Float> {
		var out:Array<Float> = [], i = 0, n = s.length;
		while (i < n) {
			var c = s.charCodeAt(i);
			if (c == " ".code || c == ",".code || c == "\t".code || c == "\n".code || c == "\r".code) {
				i++;
				continue;
			}
			var start = i;
			if (c == "+".code || c == "-".code) i++;
			var dot = false, digits = false;
			while (i < n) {
				var d = s.charCodeAt(i);
				if (d >= "0".code && d <= "9".code) {
					digits = true;
					i++;
				} else if (d == ".".code && !dot) {
					dot = true;
					i++;
				} else
					break;
			}
			if (i < n && digits && (s.charCodeAt(i) == "e".code || s.charCodeAt(i) == "E".code)) {
				var j = i + 1;
				if (j < n && (s.charCodeAt(j) == "+".code || s.charCodeAt(j) == "-".code)) j++;
				if (j < n && s.charCodeAt(j) >= "0".code && s.charCodeAt(j) <= "9".code) {
					i = j;
					while (i < n && s.charCodeAt(i) >= "0".code && s.charCodeAt(i) <= "9".code)
						i++;
				}
			}
			if (!digits) {
				// (not a number: the list ends)
				break;
			}
			out.push(Std.parseFloat(s.substring(start, i)));
		}
		return out;
	}

	// path data into moves, lines, cubic curves (quadratic ones and arcs
	// made cubic) and closes; an error ends it, what came before kept (as SVG says)
	public static function pathData(d:String):Array<Float> {
		var p:Array<Float> = [];
		var i = 0, n = d.length;
		var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
		// the last control point (for S and T) and what the last command was
		var cx = 0.0, cy = 0.0, last = " ".code;
		function skip()
			while (i < n && (d.charCodeAt(i) == " ".code || d.charCodeAt(i) == ",".code || d.charCodeAt(i) == "\t".code || d.charCodeAt(i) == "\n".code
				|| d.charCodeAt(i) == "\r".code))
				i++;
		// a number, NaN when there is none
		function number():Float {
			skip();
			var start = i;
			if (i < n && (d.charCodeAt(i) == "+".code || d.charCodeAt(i) == "-".code)) i++;
			var dot = false, digits = false;
			while (i < n) {
				var c = d.charCodeAt(i);
				if (c >= "0".code && c <= "9".code) {
					digits = true;
					i++;
				} else if (c == ".".code && !dot) {
					dot = true;
					i++;
				} else
					break;
			}
			if (!digits) {
				i = start;
				return Math.NaN;
			}
			if (i < n && (d.charCodeAt(i) == "e".code || d.charCodeAt(i) == "E".code)) {
				var j = i + 1;
				if (j < n && (d.charCodeAt(j) == "+".code || d.charCodeAt(j) == "-".code)) j++;
				if (j < n && d.charCodeAt(j) >= "0".code && d.charCodeAt(j) <= "9".code) {
					i = j;
					while (i < n && d.charCodeAt(i) >= "0".code && d.charCodeAt(i) <= "9".code)
						i++;
				}
			}
			return Std.parseFloat(d.substring(start, i));
		}
		// an arc's flag: a single 0 or 1
		function flag():Float {
			skip();
			if (i < n && (d.charCodeAt(i) == "0".code || d.charCodeAt(i) == "1".code)) return d.charCodeAt(i++) - "0".code;
			return Math.NaN;
		}
		var cmd = 0;
		while (true) {
			skip();
			if (i >= n) break;
			var c = d.charCodeAt(i);
			var isCmd = (c >= "A".code && c <= "Z".code) || (c >= "a".code && c <= "z".code);
			if (isCmd) {
				cmd = c;
				i++;
			} else if (cmd == 0) break;
			// (numbers after a move: lines)
			else if (cmd == "M".code) cmd = "L".code;
			else if (cmd == "m".code) cmd = "l".code;
			else if (cmd == "Z".code || cmd == "z".code) break;
			var rel = cmd >= "a".code;
			var ox = rel ? x : 0.0, oy = rel ? y : 0.0;
			switch cmd {
				case "M".code | "m".code:
					var a = number(), b = number();
					if (Math.isNaN(b)) break;
					x = sx = ox + a;
					y = sy = oy + b;
					p.push(0); p.push(x); p.push(y);
				case "L".code | "l".code:
					var a = number(), b = number();
					if (Math.isNaN(b)) break;
					x = ox + a;
					y = oy + b;
					p.push(1); p.push(x); p.push(y);
				case "H".code | "h".code:
					var a = number();
					if (Math.isNaN(a)) break;
					x = ox + a;
					p.push(1); p.push(x); p.push(y);
				case "V".code | "v".code:
					var a = number();
					if (Math.isNaN(a)) break;
					y = oy + a;
					p.push(1); p.push(x); p.push(y);
				case "C".code | "c".code | "S".code | "s".code:
					var x1, y1;
					if (cmd == "S".code || cmd == "s".code) {
						var smooth = last == "C".code || last == "c".code || last == "S".code || last == "s".code;
						x1 = smooth ? 2 * x - cx : x;
						y1 = smooth ? 2 * y - cy : y;
					} else {
						x1 = ox + number();
						y1 = oy + number();
					}
					var x2 = ox + number(), y2 = oy + number(), ex = ox + number(), ey = oy + number();
					if (Math.isNaN(x1 + y1 + x2 + y2 + ex + ey)) break;
					cubic(p, x1, y1, x2, y2, ex, ey);
					cx = x2;
					cy = y2;
					x = ex;
					y = ey;
				case "Q".code | "q".code | "T".code | "t".code:
					var qx, qy;
					if (cmd == "T".code || cmd == "t".code) {
						var smooth = last == "Q".code || last == "q".code || last == "T".code || last == "t".code;
						qx = smooth ? 2 * x - cx : x;
						qy = smooth ? 2 * y - cy : y;
					} else {
						qx = ox + number();
						qy = oy + number();
					}
					var ex = ox + number(), ey = oy + number();
					if (Math.isNaN(qx + qy + ex + ey)) break;
					cubic(p, x + 2 / 3 * (qx - x), y + 2 / 3 * (qy - y), ex + 2 / 3 * (qx - ex), ey + 2 / 3 * (qy - ey), ex, ey);
					cx = qx;
					cy = qy;
					x = ex;
					y = ey;
				case "A".code | "a".code:
					var rx = number(), ry = number(), angle = number(), large = flag(), sweep = flag(), ex = ox + number(), ey = oy + number();
					if (Math.isNaN(rx + ry + angle + large + sweep + ex + ey)) break;
					arc(p, x, y, rx, ry, angle, large == 1, sweep == 1, ex, ey);
					x = ex;
					y = ey;
				case "Z".code | "z".code:
					p.push(3);
					x = sx;
					y = sy;
				case _:
					break;
			}
			last = cmd;
		}
		return p;
	}

	// an elliptical arc as cubic curves (SVG's endpoint parameters, F.6)
	static function arc(p:Array<Float>, x1:Float, y1:Float, rx:Float, ry:Float, angle:Float, large:Bool, sweep:Bool, x2:Float, y2:Float) {
		if (x1 == x2 && y1 == y2) return;
		rx = Math.abs(rx);
		ry = Math.abs(ry);
		if (rx == 0 || ry == 0) {
			p.push(1); p.push(x2); p.push(y2);
			return;
		}
		var phi = angle * Math.PI / 180, cos = Math.cos(phi), sin = Math.sin(phi);
		var dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
		var x1p = cos * dx + sin * dy, y1p = -sin * dx + cos * dy;
		var lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
		if (lambda > 1) {
			var s = Math.sqrt(lambda);
			rx *= s;
			ry *= s;
		}
		var num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
		var den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
		var co = Math.sqrt(Math.max(0, num / den)) * (large == sweep ? -1 : 1);
		var cxp = co * rx * y1p / ry, cyp = -co * ry * x1p / rx;
		var cx = cos * cxp - sin * cyp + (x1 + x2) / 2, cy = sin * cxp + cos * cyp + (y1 + y2) / 2;
		function ang(ux:Float, uy:Float, vx:Float, vy:Float):Float {
			var a = Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
			return a;
		}
		var t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
		var dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry);
		if (!sweep && dt > 0) dt -= 2 * Math.PI;
		if (sweep && dt < 0) dt += 2 * Math.PI;
		// (pieces of at most a quarter turn)
		var pieces = Std.int(Math.ceil(Math.abs(dt) / (Math.PI / 2) - 1e-9));
		if (pieces < 1) pieces = 1;
		var step = dt / pieces, k = 4 / 3 * Math.tan(step / 4);
		var t = t1;
		for (_ in 0...pieces) {
			var c1 = Math.cos(t), s1 = Math.sin(t), c2 = Math.cos(t + step), s2 = Math.sin(t + step);
			// (on the unit circle, then scaled, rotated, moved)
			var ax = c1 - k * s1, ay = s1 + k * c1, bx = c2 + k * s2, by = s2 - k * c2;
			inline function px(u:Float, v:Float):Float
				return cos * rx * u - sin * ry * v + cx;
			inline function py(u:Float, v:Float):Float
				return sin * rx * u + cos * ry * v + cy;
			cubic(p, px(ax, ay), py(ax, ay), px(bx, by), py(bx, by), px(c2, s2), py(c2, s2));
			t += step;
		}
		// (the end exactly where it was asked)
		p[p.length - 2] = x2;
		p[p.length - 1] = y2;
	}

	// a transform list: matrix, translate, scale, rotate, skewX, skewY
	public static function transform(s:String):Matrix {
		var m = Matrix.IDENTITY;
		var re = ~/([a-zA-Z]+)\s*\(([^)]*)\)/;
		var rest = s;
		while (re.match(rest)) {
			var a = numbers(re.matched(2));
			inline function arg(i:Int, def:Float):Float
				return i < a.length ? a[i] : def;
			var t = switch re.matched(1) {
				case "matrix" if (a.length == 6): new Matrix(a[0], a[1], a[2], a[3], a[4], a[5]);
				case "translate": new Matrix(1, 0, 0, 1, arg(0, 0), arg(1, 0));
				case "scale": new Matrix(arg(0, 1), 0, 0, arg(1, arg(0, 1)), 0, 0);
				case "rotate":
					var r = arg(0, 0) * Math.PI / 180, c = Math.cos(r), sn = Math.sin(r), x = arg(1, 0), y = arg(2, 0);
					new Matrix(1, 0, 0, 1, x, y).times(new Matrix(c, sn, -sn, c, 0, 0)).times(new Matrix(1, 0, 0, 1, -x, -y));
				case "skewX": new Matrix(1, 0, Math.tan(arg(0, 0) * Math.PI / 180), 1, 0, 0);
				case "skewY": new Matrix(1, Math.tan(arg(0, 0) * Math.PI / 180), 0, 1, 0, 0);
				case _: Matrix.IDENTITY;
			}
			m = m.times(t);
			rest = re.matchedRight();
		}
		return m;
	}

	// a CSS colour: #rgb, #rgba, #rrggbb, #rrggbbaa, rgb(), rgba(), a name, transparent
	public static function color(v:String, current:Null<Color>):Null<Color> {
		v = StringTools.trim(v).toLowerCase();
		if (v == "transparent") return 0;
		if (v == "currentcolor") return current;
		if (StringTools.startsWith(v, "#")) {
			var h = v.substr(1);
			if (h.length == 3 || h.length == 4) {
				var b = new StringBuf();
				for (k in 0...h.length) {
					b.add(h.charAt(k));
					b.add(h.charAt(k));
				}
				h = b.toString();
			}
			var n = Std.parseInt("0x" + h);
			if (n == null) return null;
			if (h.length == 6) return 0xFF000000 | n;
			if (h.length == 8) return ((n & 0xFF) << 24) | (n >>> 8);
			return null;
		}
		if (StringTools.startsWith(v, "rgb")) {
			var open = v.indexOf("("), close = v.indexOf(")");
			if (open < 0 || close < open) return null;
			var parts = ~/[\s,\/]+/g.split(StringTools.trim(v.substring(open + 1, close))).filter(x -> x != "");
			if (parts.length < 3) return null;
			function channel(s:String):Int {
				var f = StringTools.endsWith(s, "%") ? Std.parseFloat(s) * 2.55 : Std.parseFloat(s);
				return Std.int(Math.max(0, Math.min(255, Math.round(f))));
			}
			var alpha = 1.0;
			if (parts.length > 3) alpha = StringTools.endsWith(parts[3], "%") ? Std.parseFloat(parts[3]) / 100 : Std.parseFloat(parts[3]);
			var a = Std.int(Math.round(Math.max(0, Math.min(1, alpha)) * 255));
			return (a << 24) | (channel(parts[0]) << 16) | (channel(parts[1]) << 8) | channel(parts[2]);
		}
		var n = SvgColors.NAMES.get(v);
		return n == null ? null : 0xFF000000 | n;
	}
}

// RGBA in floats, premultiplied, drawn into by shapes and groups
class SvgCanvas {
	final width:Int;
	final height:Int;
	final current:Color;
	var layer:Vector<Float>;
	final raster:Rasterizer;
	final coverage:Bytes;

	public function new(width:Int, height:Int, current:Color) {
		this.width = width;
		this.height = height;
		this.current = current;
		layer = blank();
		raster = new Rasterizer(width, height);
		coverage = Bytes.alloc(width * height);
	}

	function blank():Vector<Float> {
		var v = new Vector<Float>(width * height * 4);
		for (i in 0...v.length)
			v[i] = 0;
		return v;
	}

	public function group(g:SvgGroup, m:Matrix) {
		var mm = m.times(g.matrix);
		if (g.opacity <= 0) return;
		var saved = layer;
		if (g.opacity < 1) layer = blank();
		for (c in g.children) {
			if (Std.isOfType(c, SvgGroup)) group(cast c, mm) else shape(cast c, mm);
		}
		if (g.opacity < 1) {
			var own = layer;
			layer = saved;
			composite(own, g.opacity);
		}
	}

	// over the layer: another, its alpha times opacity
	function composite(src:Vector<Float>, opacity:Float) {
		var i = 0;
		while (i < src.length) {
			var a = src[i + 3] * opacity;
			if (a > 0) {
				var k = 1 - a;
				layer[i] = src[i] * opacity + layer[i] * k;
				layer[i + 1] = src[i + 1] * opacity + layer[i + 1] * k;
				layer[i + 2] = src[i + 2] * opacity + layer[i + 2] * k;
				layer[i + 3] = a + layer[i + 3] * k;
			}
			i += 4;
		}
	}

	function shape(s:SvgShape, m:Matrix) {
		var mm = m.times(s.matrix), st = s.style;
		if (s.opacity <= 0) return;
		var fill = colorOf(st.fill), stroke = st.strokeWidth > 0 ? colorOf(st.stroke) : null;
		if (fill == null && stroke == null) return;
		// (both, at an opacity: composited as one)
		var own = s.opacity < 1 && fill != null && stroke != null;
		var saved = layer, alpha = own ? 1.0 : s.opacity;
		if (own) layer = blank();
		if (fill != null) {
			raster.clear();
			fillPath(s.path, mm);
			raster.writeTo(coverage, 0, width, st.evenOdd);
			paint(fill, st.fillOpacity * alpha);
		}
		if (stroke != null) {
			raster.clear();
			new SvgStroker(raster, mm, st.strokeWidth / 2, st.cap, st.join, st.miterLimit).path(s.path);
			raster.writeTo(coverage, 0, width);
			paint(stroke, st.strokeOpacity * alpha);
		}
		if (own) {
			var mine = layer;
			layer = saved;
			composite(mine, s.opacity);
		}
	}

	function colorOf(p:SvgPaint):Null<Color>
		return switch p {
			case None: null;
			case Rgba(c): c;
			case Current: current;
		}

	// the path's subpaths into the rasterizer, each closed (a fill closes them)
	function fillPath(p:Array<Float>, m:Matrix) {
		var i = 0, open = false;
		while (i < p.length) {
			switch Std.int(p[i]) {
				case 0:
					if (open) raster.close();
					raster.moveTo(m.x(p[i + 1], p[i + 2]), m.y(p[i + 1], p[i + 2]));
					open = true;
					i += 3;
				case 1:
					raster.lineTo(m.x(p[i + 1], p[i + 2]), m.y(p[i + 1], p[i + 2]));
					i += 3;
				case 2:
					raster.cubicTo(m.x(p[i + 1], p[i + 2]), m.y(p[i + 1], p[i + 2]), m.x(p[i + 3], p[i + 4]), m.y(p[i + 3], p[i + 4]), m.x(p[i + 5], p[i + 6]),
						m.y(p[i + 5], p[i + 6]));
					i += 7;
				case _:
					raster.close();
					i++;
			}
		}
		if (open) raster.close();
	}

	// the coverage painted in a colour over the layer
	function paint(c:Color, opacity:Float) {
		var a = c.a / 255 * opacity;
		if (a <= 0) return;
		var r = c.r / 255, g = c.g / 255, b = c.b / 255;
		for (i in 0...width * height) {
			var cov = coverage.get(i);
			if (cov == 0) continue;
			var sa = a * cov / 255, k = 1 - sa, o = i * 4;
			layer[o] = r * sa + layer[o] * k;
			layer[o + 1] = g * sa + layer[o + 1] * k;
			layer[o + 2] = b * sa + layer[o + 2] * k;
			layer[o + 3] = sa + layer[o + 3] * k;
		}
	}

	// straight RGBA8
	public function image():Image {
		var img = new Image(width, height), px = img.pixels;
		for (i in 0...width * height) {
			var o = i * 4, a = layer[o + 3];
			if (a <= 0) continue;
			inline function ch(v:Float):Int
				return Std.int(Math.max(0, Math.min(255, Math.round(v / a * 255))));
			px.set(o, ch(layer[o]));
			px.set(o + 1, ch(layer[o + 1]));
			px.set(o + 2, ch(layer[o + 2]));
			px.set(o + 3, Std.int(Math.round(Math.min(1, a) * 255)));
		}
		return img;
	}
}

// a stroke's outline, as one path a subpath (two for a closed one: its
// sides as loops wound against each other): each side offset by half the
// width, joined on the outer side of a turn (miter, bevel, round arc) and
// through the point on the inner side (the overlap wound the same way, so
// the nonzero rule fills it once), the open ends capped; made in user units
// (curves flattened finely enough for the transform), drawn through it
class SvgStroker {
	final raster:Rasterizer;
	final m:Matrix;
	final hw:Float;
	final cap:Int;
	final join:Int;
	final miterLimit:Float;
	// the flattening tolerance in user units
	final tolerance:Float;
	// the outline being made
	var ox:Array<Float> = [];
	var oy:Array<Float> = [];

	public function new(raster, m, hw, cap, join, miterLimit) {
		this.raster = raster;
		this.m = m;
		this.hw = hw;
		this.cap = cap;
		this.join = join;
		this.miterLimit = miterLimit;
		var s = m.scale();
		tolerance = 0.1 / (s > 0 ? s : 1);
	}

	public function path(p:Array<Float>) {
		var xs:Array<Float> = [], ys:Array<Float> = [];
		var i = 0, closed = false;
		function flush() {
			if (xs.length > 0) subpath(xs, ys, closed);
			xs = [];
			ys = [];
			closed = false;
		}
		while (i < p.length) {
			switch Std.int(p[i]) {
				case 0:
					flush();
					xs.push(p[i + 1]);
					ys.push(p[i + 2]);
					i += 3;
				case 1:
					xs.push(p[i + 1]);
					ys.push(p[i + 2]);
					i += 3;
				case 2:
					var x0 = xs[xs.length - 1], y0 = ys[ys.length - 1];
					var x1 = p[i + 1], y1 = p[i + 2], x2 = p[i + 3], y2 = p[i + 4], x3 = p[i + 5], y3 = p[i + 6];
					var ax = x0 - 2 * x1 + x2, ay = y0 - 2 * y1 + y2, bx = x1 - 2 * x2 + x3, by = y1 - 2 * y2 + y3;
					var dev = Math.sqrt(Math.max(ax * ax + ay * ay, bx * bx + by * by));
					var n = 1 + Math.floor(Math.sqrt(dev * 0.75 / tolerance));
					for (k in 1...n + 1) {
						var t = k / n, u = 1 - t;
						var a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
						xs.push(a * x0 + b * x1 + c * x2 + d * x3);
						ys.push(a * y0 + b * y1 + c * y2 + d * y3);
					}
					i += 7;
				case _:
					closed = true;
					var sx = xs.length > 0 ? xs[0] : 0.0, sy = ys.length > 0 ? ys[0] : 0.0;
					flush();
					// (drawing on after a close: from where the subpath began)
					xs.push(sx);
					ys.push(sy);
					i++;
					// (a move next replaces that start)
					if (i < p.length && Std.int(p[i]) == 0) {
						xs = [];
						ys = [];
					}
			}
		}
		// (a lone point left by a close is no subpath)
		if (xs.length > 1 || closed) flush();
	}

	function subpath(xs0:Array<Float>, ys0:Array<Float>, closed:Bool) {
		// (points that repeat dropped)
		var xs = [xs0[0]], ys = [ys0[0]];
		for (k in 1...xs0.length)
			if (Math.abs(xs0[k] - xs[xs.length - 1]) > 1e-9 || Math.abs(ys0[k] - ys[ys.length - 1]) > 1e-9) {
				xs.push(xs0[k]);
				ys.push(ys0[k]);
			}
		if (closed && xs.length > 1 && Math.abs(xs[0] - xs[xs.length - 1]) <= 1e-9 && Math.abs(ys[0] - ys[ys.length - 1]) <= 1e-9) {
			xs.pop();
			ys.pop();
		}
		var n = xs.length;
		if (n == 1) {
			// a zero length subpath: a dot for round and square caps
			if (cap == 1) {
				arc(xs[0], ys[0], 0, 2 * Math.PI);
				emit();
			} else if (cap == 2) {
				point(xs[0] - hw, ys[0] - hw);
				point(xs[0] + hw, ys[0] - hw);
				point(xs[0] + hw, ys[0] + hw);
				point(xs[0] - hw, ys[0] + hw);
				emit();
			}
			return;
		}
		if (closed && n == 2) closed = false;
		// the segments' directions
		var segs = closed ? n : n - 1;
		var dx = [], dy = [], len = [];
		for (k in 0...segs) {
			var b = (k + 1) % n, ex = xs[b] - xs[k], ey = ys[b] - ys[k], l = Math.sqrt(ex * ex + ey * ey);
			dx.push(ex / l);
			dy.push(ey / l);
			len.push(l);
		}
		// (the normal of a direction: it turned a quarter, (-dy, dx))
		if (closed) {
			for (s in [1.0, -1.0]) {
				for (k in 0...n)
					joinAt(xs[k], ys[k], dx[(k + n - 1) % n], dy[(k + n - 1) % n], dx[k], dy[k], s, len[(k + n - 1) % n], len[k]);
				// (the right side backwards: the loops wound against each other)
				if (s < 0) {
					ox.reverse();
					oy.reverse();
				}
				emit();
			}
			return;
		}
		// left side forwards, the end's cap, right side backwards, the start's cap
		point(xs[0] - dy[0] * hw, ys[0] + dx[0] * hw);
		for (k in 1...n - 1)
			joinAt(xs[k], ys[k], dx[k - 1], dy[k - 1], dx[k], dy[k], 1, len[k - 1], len[k]);
		capAt(xs[n - 1], ys[n - 1], dx[segs - 1], dy[segs - 1]);
		var k = n - 2;
		while (k >= 1) {
			// (backwards: the directions reversed, the side still the right one)
			joinAt(xs[k], ys[k], -dx[k], -dy[k], -dx[k - 1], -dy[k - 1], 1, len[k], len[k - 1]);
			k--;
		}
		capAt(xs[0], ys[0], -dx[0], -dy[0]);
		emit();
	}

	inline function point(x:Float, y:Float) {
		ox.push(x);
		oy.push(y);
	}

	// the outline so far, closed, into the rasterizer
	function emit() {
		if (ox.length > 2) {
			raster.moveTo(m.x(ox[0], oy[0]), m.y(ox[0], oy[0]));
			for (k in 1...ox.length)
				raster.lineTo(m.x(ox[k], oy[k]), m.y(ox[k], oy[k]));
			raster.close();
		}
		ox = [];
		oy = [];
	}

	// the side s (1: left, -1: right) at (x, y) between the directions in and
	// out, of segments lenIn and lenOut long
	function joinAt(x:Float, y:Float, ix:Float, iy:Float, jx:Float, jy:Float, s:Float, lenIn:Float, lenOut:Float) {
		var ax = x - iy * hw * s, ay = y + ix * hw * s, bx = x - jy * hw * s, by = y + jx * hw * s;
		var cross = ix * jy - iy * jx, dot = ix * jx + iy * jy;
		if (Math.abs(cross) < 1e-9 && dot > 0) {
			point(ax, ay);
			return;
		}
		// (a turn toward this side: the inner one; where the sides cross when
		// that is within both segments, else through the point)
		if (cross * s > 0) {
			var cosHalf = Math.sqrt(Math.max(0, (1 + dot) / 2)), sinHalf = Math.sqrt(Math.max(0, (1 - dot) / 2));
			if (cosHalf > 1e-9 && hw * sinHalf / cosHalf <= Math.min(lenIn, lenOut)) {
				var mx = -iy - jy, my = ix + jx, ml = Math.sqrt(mx * mx + my * my);
				var l = hw / cosHalf;
				point(x + mx / ml * l * s, y + my / ml * l * s);
				return;
			}
			point(ax, ay);
			point(x, y);
			point(bx, by);
			return;
		}
		point(ax, ay);
		switch join {
			case 1:
				var from = Math.atan2(ay - y, ax - x), turn = Math.atan2(cross, dot);
				arcPoints(x, y, from, turn);
			case 0:
				// (the miter's length over the stroke's width: 1 / sin(half the angle between the segments))
				var cosHalf = Math.sqrt(Math.max(0, (1 + dot) / 2));
				if (cosHalf > 1e-9 && 1 / cosHalf <= miterLimit) {
					var mx = -iy - jy, my = ix + jx, ml = Math.sqrt(mx * mx + my * my);
					if (ml > 1e-12) {
						var len = hw / cosHalf;
						point(x + mx / ml * len * s, y + my / ml * len * s);
					}
				}
			case _:
		}
		point(bx, by);
	}

	// the cap at the end (x, y), the path heading (dx, dy) there: from the
	// left side's end to the right side's
	function capAt(x:Float, y:Float, dx:Float, dy:Float) {
		var lx = x - dy * hw, ly = y + dx * hw, rx = x + dy * hw, ry = y - dx * hw;
		point(lx, ly);
		switch cap {
			case 1:
				arcPoints(x, y, Math.atan2(ly - y, lx - x), -Math.PI);
			case 2:
				point(lx + dx * hw, ly + dy * hw);
				point(rx + dx * hw, ry + dy * hw);
			case _:
		}
		point(rx, ry);
	}

	// the points of an arc of the stroke's radius around (x, y), from the
	// angle from, turning by turn (its ends not included)
	function arcPoints(x:Float, y:Float, from:Float, turn:Float) {
		var step = hw > tolerance ? 2 * Math.acos(1 - tolerance / hw) : Math.PI / 2;
		var steps = Std.int(Math.ceil(Math.abs(turn) / step));
		for (k in 1...steps) {
			var t = from + turn * k / steps;
			point(x + Math.cos(t) * hw, y + Math.sin(t) * hw);
		}
	}

	// a whole circle's points
	function arc(x:Float, y:Float, from:Float, turn:Float) {
		point(x + Math.cos(from) * hw, y + Math.sin(from) * hw);
		arcPoints(x, y, from, turn);
	}
}
