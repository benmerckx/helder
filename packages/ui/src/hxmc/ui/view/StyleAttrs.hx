package hxmc.ui.view;

import hxmc.ui.*;

// Markup attributes as Style properties (NodeRenderer): an attribute named
// as a property (or in kebab-case: "align-items") sets it from the value as
// markup gives it: numbers, strings as CSS writes them ("50%", "#3b82f6",
// "space-between", "8 12"), Bool, or the property's own type. apply is
// generated from Style's properties (AttrMacro); the functions below named
// as a property convert the values CSS writes its own way.
@:build(hxmc.ui.view.AttrMacro.build())
class StyleAttrs {
	public static function isStyle(name:String):Bool
		return NAMES.exists(camel(name));

	// several values: each side's
	static function borderWidth(style:Style, v:Dynamic) {
		if (Std.isOfType(v, String) && StringTools.trim(v).indexOf(" ") > 0 || Std.isOfType(v, Array)) style.borders = edges(v) else {
			style.borders = null;
			style.borderWidth = float(v);
		}
	}

	// a gradient: the image over no colour, as CSS's shorthand sets both
	static function background(style:Style, v:Dynamic) {
		if (Std.isOfType(v, String) && Gradient.isGradient(v)) {
			style.background = Color.TRANSPARENT;
			style.backgroundImage = Gradient.parse(v);
		} else {
			style.background = colorOf(v);
			style.backgroundImage = null;
		}
	}

	static function transform(style:Style, v:Dynamic)
		style.transform = v == null || v == "none" ? null : Std.isOfType(v, String) ? Transform.parse(v) : (v : Transform);

	static function transformOrigin(style:Style, v:Dynamic)
		style.transformOrigin = v == null ? null : Std.isOfType(v, String) ? Transform.origin(v) : (v : Array<Dim>);

	// several values: each corner's, as CSS's border-radius
	static function radius(style:Style, v:Dynamic) {
		if (Std.isOfType(v, String) && StringTools.trim(v).indexOf(" ") > 0) style.corners = CornersValue.parse(v) else if (Std.isOfType(v, Array))
			style.corners = (v : Array<Float>) else {
			style.corners = null;
			style.radius = float(v);
		}
	}

	static function corners(style:Style, v:Dynamic)
		style.corners = v == null ? null : Std.isOfType(v, String) ? CornersValue.parse(v) : Std.isOfType(v, Array) ? (v : Array<Float>) : (v : Corners);

	// CSS's shorthand: a width, "solid" and a colour, any order ("2px solid
	// red", "3 #0ea5e9"; the colour the text's when left out), or "none"
	static function outline(style:Style, v:Dynamic) {
		if (v == null || v == "none") {
			style.outlineWidth = 0;
			return;
		}
		var width = 3.0, color:Null<Color> = null;
		for (p in StringTools.trim(Std.string(v)).split(" ")) {
			if (p == "" || p == "solid") continue;
			var f = Std.parseFloat(StringTools.replace(p, "px", ""));
			if (!Math.isNaN(f) && ~/^-?[0-9.]+(px)?$/.match(p)) {
				width = f;
				continue;
			}
			var c = Color.tryParse(p);
			if (c == null) throw "outline: " + v + " (a width, solid and a colour)";
			color = c;
		}
		style.outlineWidth = width;
		style.outlineColor = color;
	}

	static function letterSpacing(style:Style, v:Dynamic)
		style.letterSpacing = v == "normal" ? 0 : float(v);

	static function wordSpacing(style:Style, v:Dynamic)
		style.wordSpacing = v == "normal" ? 0 : float(v);

	// "underline", "line-through", "overline", several, "none" (or the flags)
	static function textDecoration(style:Style, v:Dynamic) {
		if (v == null || !Std.isOfType(v, String)) {
			style.textDecoration = v == null ? 0 : Std.int(v);
			return;
		}
		var flags = 0;
		for (w in StringTools.trim((v : String).toLowerCase()).split(" "))
			flags |= switch w {
				case "underline": (TextDecoration.Underline : Int);
				case "line-through": (TextDecoration.LineThrough : Int);
				case "overline": (TextDecoration.Overline : Int);
				case "none" | "": 0;
				case _: throw "hxmc.ui: not a text decoration: " + w;
			}
		style.textDecoration = flags;
	}

	static function gridTemplateColumns(style:Style, v:Dynamic)
		style.gridTemplateColumns = Std.isOfType(v, String) ? Grid.tracks(v) : v;

	static function gridTemplateRows(style:Style, v:Dynamic)
		style.gridTemplateRows = Std.isOfType(v, String) ? Grid.tracks(v) : v;

	static function gridAutoColumns(style:Style, v:Dynamic)
		style.gridAutoColumns = Std.isOfType(v, String) ? Grid.tracks(v)[0] : v;

	static function gridAutoRows(style:Style, v:Dynamic)
		style.gridAutoRows = Std.isOfType(v, String) ? Grid.tracks(v)[0] : v;

	// "row", "column", "dense", "row dense", "column dense" (or the GridFlow)
	static function gridAutoFlow(style:Style, v:Dynamic) {
		if (!Std.isOfType(v, String)) {
			style.gridAutoFlow = v;
			return;
		}
		var words = StringTools.trim(v).split(" ").filter(w -> w != "");
		var column = words.indexOf("column") >= 0, dense = words.indexOf("dense") >= 0;
		style.gridAutoFlow = column ? (dense ? ColumnDense : Column) : (dense ? RowDense : Row);
	}

	static function gridColumn(style:Style, v:Dynamic)
		style.gridColumn = Std.isOfType(v, String) ? Grid.GridPlacement.parse(v) : Std.isOfType(v, Int) ? new Grid.GridPlacement(v, 0, 1) : v;

	static function gridRow(style:Style, v:Dynamic)
		style.gridRow = Std.isOfType(v, String) ? Grid.GridPlacement.parse(v) : Std.isOfType(v, Int) ? new Grid.GridPlacement(v, 0, 1) : v;

	// (kebab-case names converted once each)
	static final camels = new Map<String, String>();

	// (the shorthands' other forms: two gaps; one to four offsets; flex's keywords and values)
	static function gap(style:Style, v:Dynamic) {
		var p = Std.isOfType(v, String) ? [for (x in StringTools.trim(v).split(" ")) if (x != "") x] : null;
		if (p != null && p.length == 2) {
			style.rowGap = float(StringTools.replace(p[0], "px", ""));
			style.columnGap = float(StringTools.replace(p[1], "px", ""));
		} else style.gap = float(Std.isOfType(v, String) ? StringTools.replace(v, "px", "") : v);
	}

	static function inset(style:Style, v:Dynamic) {
		var p:Array<Dynamic> = Std.isOfType(v, String) ? [for (x in StringTools.trim(v).split(" ")) if (x != "") x] : Std.isOfType(v, Array) ? v : [v];
		var d = [for (x in p) dim(x)];
		switch d.length {
			case 1: style.inset = d[0];
			case 2: style.top = style.bottom = d[0]; style.left = style.right = d[1];
			case 3: style.top = d[0]; style.left = style.right = d[1]; style.bottom = d[2];
			case 4: style.top = d[0]; style.right = d[1]; style.bottom = d[2]; style.left = d[3];
			case _: throw "inset: 1 to 4 values";
		}
	}

	static function flex(style:Style, v:Dynamic) {
		if (!Std.isOfType(v, String)) {
			style.flex = (v : Float);
			return;
		}
		var p = [for (x in StringTools.trim(v).split(" ")) if (x != "") x];
		switch p {
			case ["none"]: style.grow = 0; style.shrink = 0; style.basis = DimValue.Auto;
			case ["auto"]: style.grow = 1; style.shrink = 1; style.basis = DimValue.Auto;
			case ["initial"]: style.grow = 0; style.shrink = 1; style.basis = DimValue.Auto;
			case [g]: style.flex = float(g);
			// (CSS's: a second number is the shrink factor, else the basis)
			case [g, b]: if (Math.isNaN(Std.parseFloat(b)) || StringTools.endsWith(b, "%") || StringTools.endsWith(b, "px")) {
					style.flex = float(g);
					style.basis = dim(b);
				} else {
					style.flex = float(g);
					style.shrink = float(b);
				}
			case [g, s, b]: style.grow = float(g); style.shrink = float(s); style.basis = dim(b);
			case _: throw "flex: " + v;
		}
	}

	static function camel(n:String):String {
		if (n.indexOf("-") < 0) return n;
		var c = camels.get(n);
		if (c != null) return c;
		var parts = n.split("-");
		c = parts[0] + [for (p in parts.slice(1)) p.charAt(0).toUpperCase() + p.substr(1)].join("");
		camels.set(n, c);
		return c;
	}

	static function key(v:Dynamic):String {
		var s = Std.string(v);
		if (s.indexOf("-") >= 0) s = StringTools.replace(s, "-", "");
		if (s.indexOf("_") >= 0) s = StringTools.replace(s, "_", "");
		return s.toLowerCase();
	}

	static function float(v:Dynamic):Float
		return Std.isOfType(v, String) ? Std.parseFloat(v) : (v : Float);

	static function dim(v:Dynamic):Dim
		return Std.isOfType(v, String) ? Dim.parse(v) : Std.isOfType(v, DimValue) ? (v : DimValue) : DimValue.Px((v : Float));

	// an Int without alpha (0xRRGGBB) is opaque; a string as CSS writes it
	static function colorOf(v:Dynamic):Null<Color> {
		if (v == null) return null;
		if (Std.isOfType(v, String)) return Color.parse(v);
		var i:Int = v;
		return (i >>> 24) == 0 ? Color.rgb(i) : i;
	}

	static function edges(v:Dynamic):EdgesValue {
		if (Std.isOfType(v, String)) return [for (p in StringTools.trim(v).split(" ")) if (p != "") Std.parseFloat(StringTools.replace(p, "px", ""))];
		if (Std.isOfType(v, Array)) return [for (x in (v : Array<Dynamic>)) (x : Float)];
		if (Std.isOfType(v, Edges)) return (v : Edges);
		return (v : Float);
	}
}
