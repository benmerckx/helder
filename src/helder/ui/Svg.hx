package helder.ui;

import helder.canvas.Matrix;
import helder.image.Image;

// An SVG document for icons and drawings: parsed once (Svg.parse), drawn
// into an Image at any size (the Image's drawing: this, for a writer's vectors; render: the viewBox fitted as
// preserveAspectRatio says, xMidYMid meet by default). The static subset
// icon sets use: svg, g, path (all of its data, arcs as cubic curves), rect
// (rounded), circle, ellipse, line, polyline, polygon; fill and stroke (a
// colour: hex, rgb(), rgba(), CSS's names, currentColor: render's color;
// none; linear and radial gradients: their units, transform, spread and
// stops, href'd ones), their opacities, opacity (a group's composited as
// one), fill-rule, stroke-width, stroke-linecap, stroke-linejoin,
// stroke-miterlimit, stroke-dasharray, stroke-dashoffset, transform; use
// (of an element or a symbol, its viewBox fitted, clipped to its
// viewport, as a nested svg is); clip-path (a clipPath's shapes, in user
// units); presentation attributes, style="" and the inherited ones passed
// down. Not drawn: text, images, patterns (a pattern paint draws
// nothing), masks, filters, markers; defs, title and the like are skipped.
class Svg implements Drawing {
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
		var root = new SvgParse(el, vb != null ? vb.w : w, vb != null ? vb.h : h).root(el);
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
		var m = new Matrix();
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
		var img = canvas.image();
		img.drawing = ({svg: this, color: color} : Drawing.ImageDrawing);
		return img;
	}
}

enum SvgPaint {
	None;
	Rgba(c:Color);
	Current;
	Gradient(g:SvgGradient);
}

// a linear (x1, y1 to x2, y2) or radial gradient (the circle cx, cy, r, its
// focus fx, fy) in the shape's bounding box (0 to 1) or user units, then
// its transform; spread: 0 pad, 1 reflect, 2 repeat; stops at offsets 0 to 1
class SvgGradient {
	public var linear = true;
	public var x1 = 0.0;
	public var y1 = 0.0;
	public var x2 = 1.0;
	public var y2 = 0.0;
	public var cx = 0.5;
	public var cy = 0.5;
	public var r = 0.5;
	public var fx = 0.5;
	public var fy = 0.5;
	public var boundingBox = true;
	public var matrix = new Matrix();
	public var spread = 0;
	public final offsets:Array<Float> = [];
	public final colors:Array<Color> = [];

	public function new() {}

	// the colour at t (spread applied), straight alpha
	public function at(t:Float):Color {
		if (Math.isNaN(t)) t = 0;
		switch spread {
			case 1:
				t = t % 2;
				if (t < 0) t += 2;
				if (t > 1) t = 2 - t;
			case 2:
				t = t % 1;
				if (t < 0) t += 1;
			case _:
		}
		var n = offsets.length;
		if (t <= offsets[0]) return colors[0];
		if (t >= offsets[n - 1]) return colors[n - 1];
		var k = 1;
		while (k < n - 1 && offsets[k] < t)
			k++;
		var a = offsets[k - 1], b = offsets[k];
		return b <= a ? colors[k] : Color.mix(colors[k - 1], colors[k], (t - a) / (b - a));
	}
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
	// the dashes' and gaps' lengths (null: a solid line), from offset along the path
	public var dashes:Null<Array<Float>> = null;
	public var dashOffset = 0.0;
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
		s.dashes = dashes;
		s.dashOffset = dashOffset;
		s.color = color;
		return s;
	}
}

class SvgGroup {
	public final matrix:Matrix;
	public final opacity:Float;
	public final children:Array<Any> = [];
	// what it is clipped to (in its units, after its matrix): shapes' paths
	// and transforms, filled by the first one's rule; null: not clipped
	public var clip:Null<Array<{path:Array<Float>, matrix:Matrix, evenOdd:Bool}>> = null;

	public function new(matrix, opacity) {
		this.matrix = matrix;
		this.opacity = opacity;
	}

	// a rectangle as a clip
	public static function box(x:Float, y:Float, w:Float, h:Float):Array<{path:Array<Float>, matrix:Matrix, evenOdd:Bool}>
		return [{path: [0, x, y, 1, x + w, y, 1, x + w, y + h, 1, x, y + h, 3], matrix: new Matrix(), evenOdd: false}];
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
	// the elements not drawn where they are (a switch: no static to be initialized first)
	static function skipped(name:String):Bool
		return switch name {
			case "defs" | "title" | "desc" | "metadata" | "clipPath" | "mask" | "linearGradient" | "radialGradient" | "pattern" | "symbol" | "marker" | "filter"
				| "style" | "script": true;
			case _: false;
		}

	// the elements by id (use, gradients), the viewport's size in user units
	final ids = new Map<String, Xml>();
	final viewW:Float;
	final viewH:Float;
	// how deep uses are (a use of its own ancestor would never end)
	var depth = 0;

	public function new(doc:Xml, viewW:Float, viewH:Float) {
		this.viewW = viewW;
		this.viewH = viewH;
		index(doc);
	}

	function index(el:Xml) {
		for (c in el.elements()) {
			var id = c.get("id");
			if (id != null && !ids.exists(id)) ids.set(id, c);
			index(c);
		}
	}

	// the outermost svg element's group: its own properties for its children
	public function root(el:Xml):SvgGroup {
		var props = properties(el), style = SvgStyle.initial();
		apply(style, props);
		var g = new SvgGroup(new Matrix(), props.exists("opacity") ? clamp01(Std.parseFloat(props.get("opacity"))) : 1.0);
		children(el, g, style);
		return g;
	}

	public function children(el:Xml, into:SvgGroup, inherited:SvgStyle) {
		for (c in el.elements())
			element(c, into, inherited, false);
	}

	// an element into a group; used: drawn by a use (a symbol then drawn)
	function element(c:Xml, into:SvgGroup, inherited:SvgStyle, used:Bool) {
		var name = c.nodeName;
		var i = name.indexOf(":");
		if (i >= 0) name = name.substr(i + 1);
		if ((skipped(name) && !(used && name == "symbol")) || c.get("display") == "none") return;
		var props = properties(c);
		if (props.get("display") == "none") return;
		var style = inherited.copy();
		apply(style, props);
		var m = c.get("transform") == null ? new Matrix() : transform(c.get("transform"));
		var opacity = props.exists("opacity") ? clamp01(Std.parseFloat(props.get("opacity"))) : 1.0;
		// (clipped: drawn into a group of its transform with the clip, itself untransformed)
		var clip = props.exists("clip-path") ? clipPath(props.get("clip-path")) : null;
		if (clip != null) {
			var g = new SvgGroup(m, 1);
			g.clip = clip;
			into.children.push(g);
			into = g;
			m = new Matrix();
		}
		switch name {
			case "g" | "svg" | "a" | "symbol":
				var g = new SvgGroup(m, opacity);
				if (name == "svg") {
					// (a nested viewport: at x, y, clipped to its size, its viewBox fitted)
					var x = num(c.get("x")), y = num(c.get("y"));
					var w = c.get("width") == null ? viewW : num(c.get("width")), h = c.get("height") == null ? viewH : num(c.get("height"));
					g = new SvgGroup(m.clone().translate(x, y), opacity);
					g.clip = SvgGroup.box(0, 0, w, h);
					var vb = c.get("viewBox") == null ? [] : numbers(c.get("viewBox"));
					if (vb.length == 4 && vb[2] > 0 && vb[3] > 0) {
						var inner = new SvgGroup(fit(vb, w, h), 1);
						g.children.push(inner);
						into.children.push(g);
						children(c, inner, style);
						return;
					}
				}
				children(c, g, style);
				into.children.push(g);
			case "use":
				var href = c.get("href") ?? c.get("xlink:href");
				var target = href != null && StringTools.startsWith(href, "#") ? ids.get(href.substr(1)) : null;
				if (target == null || depth > 16) return;
				var x = num(c.get("x")), y = num(c.get("y"));
				m.translate(x, y);
				var g = new SvgGroup(m, opacity), inner = g;
				var tname = target.nodeName.substr(target.nodeName.indexOf(":") + 1);
				if (tname == "symbol") {
					// (a symbol: a viewport of the use's size (the outer one's by default), clipped, its viewBox fitted)
					var w = c.get("width") == null ? viewW : num(c.get("width")), h = c.get("height") == null ? viewH : num(c.get("height"));
					g.clip = SvgGroup.box(0, 0, w, h);
					var vb = target.get("viewBox") == null ? [] : numbers(target.get("viewBox"));
					if (vb.length == 4 && vb[2] > 0 && vb[3] > 0) {
						inner = new SvgGroup(fit(vb, w, h), 1);
						g.children.push(inner);
					}
				}
				depth++;
				element(target, inner, style, true);
				depth--;
				into.children.push(g);
			case _:
				var path = shape(name, c);
				if (path != null && path.length > 0) into.children.push(new SvgShape(path, m, style, opacity));
		}
	}

	// a viewBox fitted to w by h (xMidYMid meet)
	static function fit(vb:Array<Float>, w:Float, h:Float):Matrix {
		var k = Math.min(w / vb[2], h / vb[3]);
		return new Matrix(k, 0, 0, k, (w - vb[2] * k) / 2 - vb[0] * k, (h - vb[3] * k) / 2 - vb[1] * k);
	}

	// a clip-path's clip: url(#id) of a clipPath, its shapes (null: none)
	function clipPath(v:String):Null<Array<{path:Array<Float>, matrix:Matrix, evenOdd:Bool}>> {
		v = StringTools.trim(v);
		if (!StringTools.startsWith(v, "url(")) return null;
		var ref = StringTools.trim(v.substring(4, v.indexOf(")") < 0 ? v.length : v.indexOf(")")));
		if (StringTools.startsWith(ref, "'") || StringTools.startsWith(ref, '"')) ref = ref.substr(1, ref.length - 2);
		var el = StringTools.startsWith(ref, "#") ? ids.get(ref.substr(1)) : null;
		if (el == null || el.nodeName.substr(el.nodeName.indexOf(":") + 1) != "clipPath") return null;
		var base = el.get("transform") == null ? new Matrix() : transform(el.get("transform"));
		var out = [];
		for (c in el.elements()) {
			var name = c.nodeName.substr(c.nodeName.indexOf(":") + 1);
			var p = properties(c);
			if (p.get("display") == "none") continue;
			var path = shape(name, c);
			if (path == null || path.length == 0) continue;
			var m = c.get("transform") == null ? base : base.clone().multiply(transform(c.get("transform")));
			out.push({path: path, matrix: m, evenOdd: (p.get("clip-rule") ?? el.get("clip-rule")) == "evenodd"});
		}
		// (a clipPath with nothing in it clips everything away)
		if (out.length == 0) out.push({path: [0, 0, 0, 3], matrix: base, evenOdd: false});
		return out;
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

	function apply(s:SvgStyle, p:Map<String, String>) {
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
		if (p.exists("stroke-dasharray")) {
			var v = StringTools.trim(p.get("stroke-dasharray"));
			var d = v == "none" ? [] : numbers(v);
			// (none, a negative length or all zero: solid; an odd count repeated)
			var sum = 0.0, bad = false;
			for (x in d) {
				if (x < 0) bad = true;
				sum += x;
			}
			s.dashes = d.length == 0 || bad || sum <= 0 ? null : d.length % 2 == 1 ? d.concat(d) : d;
		}
		if (p.exists("stroke-dashoffset")) {
			var o = Std.parseFloat(p.get("stroke-dashoffset"));
			if (!Math.isNaN(o)) s.dashOffset = o;
		}
	}

	function paint(v:String, s:SvgStyle):SvgPaint {
		v = StringTools.trim(v);
		if (v == "none") return None;
		if (v == "currentColor" || v == "currentcolor") return s.color != null ? Rgba(s.color) : Current;
		if (StringTools.startsWith(v, "url(")) {
			// (a gradient; else the fallback colour after it, or nothing: a pattern is not drawn)
			var close = v.indexOf(")");
			var ref = StringTools.trim(v.substring(4, close < 0 ? v.length : close));
			if (StringTools.startsWith(ref, "'") || StringTools.startsWith(ref, '"')) ref = ref.substr(1, ref.length - 2);
			var g = StringTools.startsWith(ref, "#") ? gradient(ref.substr(1), s) : null;
			if (g != null) return g;
			var rest = close < 0 ? "" : StringTools.trim(v.substr(close + 1));
			return rest == "" ? None : paint(rest, s);
		}
		var c = color(v, s.color);
		return c == null ? None : Rgba(c);
	}

	// a gradient by id: its attributes and stops, from the gradients it
	// href's where it has none; one stop: that colour; none: no paint
	function gradient(id:String, s:SvgStyle):Null<SvgPaint> {
		var el = ids.get(id);
		if (el == null) return null;
		var name = el.nodeName.substr(el.nodeName.indexOf(":") + 1);
		if (name != "linearGradient" && name != "radialGradient") return null;
		var chain = [el];
		while (chain.length < 16) {
			var href = chain[chain.length - 1].get("href") ?? chain[chain.length - 1].get("xlink:href");
			var next = href != null && StringTools.startsWith(href, "#") ? ids.get(href.substr(1)) : null;
			if (next == null || chain.contains(next)) break;
			chain.push(next);
		}
		function attr(a:String):Null<String> {
			for (e in chain)
				if (e.get(a) != null) return e.get(a);
			return null;
		}
		var g = new SvgGradient();
		g.linear = name == "linearGradient";
		g.boundingBox = attr("gradientUnits") != "userSpaceOnUse";
		if (attr("gradientTransform") != null) g.matrix = transform(attr("gradientTransform"));
		g.spread = switch attr("spreadMethod") {
			case "reflect": 1;
			case "repeat": 2;
			case _: 0;
		}
		// (a coordinate: a fraction of the box, or of the viewport in user units)
		var diag = Math.sqrt((viewW * viewW + viewH * viewH) / 2);
		function coord(a:String, def:Float, size:Float):Float {
			var v = attr(a);
			if (v == null) return def;
			v = StringTools.trim(v);
			var pct = StringTools.endsWith(v, "%"), f = Std.parseFloat(v);
			if (Math.isNaN(f)) return def;
			return pct ? f / 100 * (g.boundingBox ? 1 : size) : f;
		}
		if (g.linear) {
			g.x1 = coord("x1", 0, viewW);
			g.y1 = coord("y1", 0, viewH);
			g.x2 = coord("x2", g.boundingBox ? 1 : viewW, viewW);
			g.y2 = coord("y2", 0, viewH);
		} else {
			g.cx = coord("cx", g.boundingBox ? 0.5 : viewW / 2, viewW);
			g.cy = coord("cy", g.boundingBox ? 0.5 : viewH / 2, viewH);
			g.r = coord("r", g.boundingBox ? 0.5 : diag / 2, diag);
			g.fx = coord("fx", g.cx, viewW);
			g.fy = coord("fy", g.cy, viewH);
		}
		var stops:Array<Xml> = [];
		for (e in chain) {
			for (c in e.elements())
				if (c.nodeName.substr(c.nodeName.indexOf(":") + 1) == "stop") stops.push(c);
			if (stops.length > 0) break;
		}
		var last = 0.0;
		for (st in stops) {
			var p = properties(st);
			var o = p.get("offset") ?? "0", off = StringTools.endsWith(StringTools.trim(o), "%") ? Std.parseFloat(o) / 100 : Std.parseFloat(o);
			if (Math.isNaN(off)) off = 0;
			// (offsets clamped, never going back)
			off = Math.max(last, Math.min(1, Math.max(0, off)));
			last = off;
			var c:Null<Color> = p.exists("stop-color") ? color(p.get("stop-color"), s.color != null ? s.color : null) : 0xFF000000;
			if (p.get("stop-color") == "currentColor" && s.color == null) c = null;
			if (c == null) c = 0xFF000000;
			var a = p.exists("stop-opacity") ? clamp01(Std.parseFloat(p.get("stop-opacity"))) : 1.0;
			g.offsets.push(off);
			g.colors.push((Std.int(Math.round((c : Color).a * a)) << 24) | ((c : Int) & 0xFFFFFF));
		}
		if (g.offsets.length == 0) return None;
		if (g.offsets.length == 1) return Rgba(g.colors[0]);
		return Gradient(g);
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
	public static function arc(p:Array<Float>, x1:Float, y1:Float, rx:Float, ry:Float, angle:Float, large:Bool, sweep:Bool, x2:Float, y2:Float) {
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
		var m = new Matrix();
		// (each name, spaces maybe, and its arguments in parentheses; anything else skipped)
		var i = 0, n = s.length;
		inline function letter(k:Int):Bool {
			var c = k < n ? StringTools.fastCodeAt(s, k) | 32 : 0;
			return c >= "a".code && c <= "z".code;
		}
		while (i < n) {
			if (!letter(i)) {
				i++;
				continue;
			}
			var start = i;
			while (letter(i))
				i++;
			var name = s.substring(start, i);
			while (i < n && StringTools.isSpace(s, i))
				i++;
			if (i >= n || StringTools.fastCodeAt(s, i) != "(".code) continue;
			var close = s.indexOf(")", i);
			if (close < 0) break;
			var a = numbers(s.substring(i + 1, close));
			i = close + 1;
			inline function arg(i:Int, def:Float):Float
				return i < a.length ? a[i] : def;
			switch name {
				case "matrix" if (a.length == 6): m.transform(a[0], a[1], a[2], a[3], a[4], a[5]);
				case "translate": m.translate(arg(0, 0), arg(1, 0));
				case "scale": m.scale(arg(0, 1), arg(1, arg(0, 1)));
				case "rotate": m.translate(arg(1, 0), arg(2, 0)).rotate(arg(0, 0) * Math.PI / 180).translate(-arg(1, 0), -arg(2, 0));
				case "skewX": m.transform(1, 0, Math.tan(arg(0, 0) * Math.PI / 180), 1, 0, 0);
				case "skewY": m.transform(1, Math.tan(arg(0, 0) * Math.PI / 180), 0, 1, 0, 0);
				case _:
			}
		}
		return m;
	}

	// a CSS colour (Color.parse's), currentColor: current
	public static function color(v:String, current:Null<Color>):Null<Color> {
		var t = StringTools.trim(v).toLowerCase();
		return t == "currentcolor" ? current : Color.tryParse(t);
	}
}

// A drawing's groups and shapes on helder.canvas (its CPU rasterizer:
// analytic coverage, strokes as outlines, gradients, clips as masks, a
// group's or a shape's opacity as a layer)
class SvgCanvas {
	final canvas:helder.canvas.Canvas;
	final current:Color;
	final path = new helder.canvas.Path();
	final paint = new helder.canvas.Paint();
	final line = new helder.canvas.Stroke();

	public function new(width:Int, height:Int, current:Color) {
		canvas = new helder.canvas.Canvas(width, height);
		this.current = current;
	}

	static inline function into(p:Array<Float>, out:helder.canvas.Path):helder.canvas.Path
		return Path.into(p, out);

	// a stroke's style: its width, cap and join (0 butt or miter, 1 round, 2 square or bevel), dashes
	public static function strokeStyle(out:helder.canvas.Stroke, width:Float, cap:Int, join:Int, miterLimit:Float, dashes:Null<Array<Float>>, dashOffset:Float) {
		out.width = width;
		out.cap = cap == 1 ? helder.canvas.Stroke.Cap.round : cap == 2 ? helder.canvas.Stroke.Cap.square : helder.canvas.Stroke.Cap.butt;
		out.join = join == 1 ? helder.canvas.Stroke.Join.round : join == 2 ? helder.canvas.Stroke.Join.bevel : helder.canvas.Stroke.Join.miter;
		out.miterLimit = miterLimit;
		out.dash = dashes == null ? null : new helder.canvas.Stroke.Dash(dashes, dashOffset);
	}

	public function group(g:SvgGroup, m:Matrix) {
		var mm = m.clone().multiply(g.matrix);
		if (g.opacity <= 0) return;
		canvas.save();
		if (g.clip != null) {
			// (the clip's shapes in one path, by the first one's rule)
			var clip = new helder.canvas.Path(), one = new helder.canvas.Path();
			for (c in g.clip)
				clip.addPath(into(c.path, one), mm.clone().multiply(c.matrix));
			canvas.resetTransform();
			canvas.clip(clip, g.clip[0].evenOdd);
		}
		if (g.opacity < 1) canvas.saveLayer(g.opacity);
		for (c in g.children) {
			if (Std.isOfType(c, SvgGroup)) group(cast c, mm) else shape(cast c, mm);
		}
		if (g.opacity < 1) canvas.restore();
		canvas.restore();
	}

	function shape(s:SvgShape, m:Matrix) {
		var mm = m.clone().multiply(s.matrix), st = s.style;
		if (s.opacity <= 0) return;
		var fill = st.fill, stroke = st.strokeWidth > 0 ? st.stroke : None;
		if (fill == None && stroke == None) return;
		// (both, at an opacity: composited as one)
		var own = s.opacity < 1 && fill != None && stroke != None;
		var alpha = own ? 1.0 : s.opacity;
		if (own) canvas.saveLayer(s.opacity);
		canvas.setTransform(mm.a, mm.b, mm.c, mm.d, mm.e, mm.f);
		into(s.path, path);
		if (fill != None && paintWith(fill, st.fillOpacity * alpha, s.path)) canvas.fill(path, paint, st.evenOdd);
		if (stroke != None && paintWith(stroke, st.strokeOpacity * alpha, s.path)) {
			SvgCanvas.strokeStyle(line, st.strokeWidth, st.cap, st.join, st.miterLimit, st.dashes, st.dashOffset);
			canvas.stroke(path, line, paint);
		}
		if (own) canvas.restore();
	}

	// the paint set to p at opacity (false: it draws nothing)
	function paintWith(p:SvgPaint, opacity:Float, shapePath:Array<Float>):Bool {
		paint.alpha = opacity;
		paint.shader = null;
		switch p {
			case None:
				return false;
			case Rgba(c):
				paint.color = c;
			case Current:
				paint.color = current;
			case Gradient(g):
				var gr:helder.canvas.Gradient;
				if (g.linear) gr = new helder.canvas.Gradient.LinearGradient(g.x1, g.y1, g.x2, g.y2) else {
					// (a focus outside the circle: moved onto it, just inside)
					var fx = g.fx, fy = g.fy, ex = fx - g.cx, ey = fy - g.cy, el = Math.sqrt(ex * ex + ey * ey);
					if (el > g.r * 0.999) {
						fx = g.cx + ex / el * g.r * 0.999;
						fy = g.cy + ey / el * g.r * 0.999;
					}
					gr = new helder.canvas.Gradient.RadialGradient(fx, fy, 0, g.cx, g.cy, g.r);
				}
				for (k in 0...g.offsets.length)
					gr.addStop(g.offsets[k], g.colors[k]);
				gr.spread = g.spread;
				// (the gradient's space: the user units' (or the box's), then its transform)
				var gm = new Matrix();
				if (g.boundingBox) {
					var b = bounds(shapePath);
					if (b[2] <= b[0] || b[3] <= b[1]) return false;
					gm = new Matrix(b[2] - b[0], 0, 0, b[3] - b[1], b[0], b[1]);
				}
				gm.multiply(g.matrix);
				gr.matrix.copyFrom(gm);
				paint.color = 0xFF000000;
				paint.shader = gr;
		}
		return true;
	}

	// a path's bounds in its units: x0, y0, x1, y1 (curves sampled)
	static function bounds(p:Array<Float>):Array<Float> {
		var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
		var lx = 0.0, ly = 0.0, i = 0;
		inline function add(x:Float, y:Float) {
			if (x < x0) x0 = x;
			if (y < y0) y0 = y;
			if (x > x1) x1 = x;
			if (y > y1) y1 = y;
		}
		while (i < p.length) {
			switch Std.int(p[i]) {
				case 0 | 1:
					lx = p[i + 1];
					ly = p[i + 2];
					add(lx, ly);
					i += 3;
				case 2:
					for (k in 1...33) {
						var t = k / 32, u = 1 - t, a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
						add(a * lx + b * p[i + 1] + c * p[i + 3] + d * p[i + 5], a * ly + b * p[i + 2] + c * p[i + 4] + d * p[i + 6]);
					}
					lx = p[i + 5];
					ly = p[i + 6];
					i += 7;
				case _:
					i++;
			}
		}
		return [x0, y0, x1, y1];
	}

	// straight RGBA8
	public function image():Image
		return canvas.bitmap.toImage();
}
