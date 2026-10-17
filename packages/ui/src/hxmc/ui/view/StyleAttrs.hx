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

	static function gridColumn(style:Style, v:Dynamic)
		style.gridColumn = Std.isOfType(v, String) ? Grid.GridPlacement.parse(v) : Std.isOfType(v, Int) ? new Grid.GridPlacement(v, 0, 1) : v;

	static function gridRow(style:Style, v:Dynamic)
		style.gridRow = Std.isOfType(v, String) ? Grid.GridPlacement.parse(v) : Std.isOfType(v, Int) ? new Grid.GridPlacement(v, 0, 1) : v;

	// (kebab-case names converted once each)
	static final camels = new Map<String, String>();

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
