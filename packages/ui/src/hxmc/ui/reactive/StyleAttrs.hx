package hxmc.ui.reactive;

import hxmc.ui.*;

// Markup attributes as Style properties (Render): an attribute named as a
// property (or in kebab-case: flex-direction aside, "align-items") sets it
// from the value as markup gives it: numbers, strings as CSS writes them
// ("50%", "#3b82f6", "space-between", "8 12"), Bool, or the property's own
// type. Generated from Style's properties.
class StyleAttrs {
	// sets the property; false when name is not one
	public static function apply(style:Style, name:String, v:Dynamic):Bool {
		switch camel(name) {
			case "display": style.display = displayValue(v);
			case "position": style.position = positionValue(v);
			case "direction": style.direction = directionValue(v);
			case "wrap": style.wrap = v == true || v == "true";
			case "justify": style.justify = justifyValue(v);
			case "alignItems": style.alignItems = alignItemsValue(v);
			case "alignSelf": style.alignSelf = alignSelfValue(v);
			case "alignContent": style.alignContent = alignContentValue(v);
			case "grow": style.grow = float(v);
			case "shrink": style.shrink = float(v);
			case "basis": style.basis = dim(v);
			case "width": style.width = dim(v);
			case "height": style.height = dim(v);
			case "minWidth": style.minWidth = dim(v);
			case "minHeight": style.minHeight = dim(v);
			case "maxWidth": style.maxWidth = dim(v);
			case "maxHeight": style.maxHeight = dim(v);
			case "aspectRatio": style.aspectRatio = float(v);
			case "padding": style.padding = edges(v);
			case "margin": style.margin = edges(v);
			case "borderWidth":
				// (several values: each side's)
				if (Std.isOfType(v, String) && StringTools.trim(v).indexOf(" ") > 0 || Std.isOfType(v, Array)) style.borders = edges(v) else {
					style.borders = null;
					style.borderWidth = float(v);
				}
			case "borders": style.borders = v == null ? null : edges(v);
			case "rowGap": style.rowGap = float(v);
			case "columnGap": style.columnGap = float(v);
			case "left": style.left = dim(v);
			case "top": style.top = dim(v);
			case "right": style.right = dim(v);
			case "bottom": style.bottom = dim(v);
			case "overflow": style.overflow = overflowValue(v);
			case "background":
				// (a gradient: the image over no colour, as CSS's shorthand sets both)
				if (Std.isOfType(v, String) && Gradient.isGradient(v)) {
					style.background = Color.TRANSPARENT;
					style.backgroundImage = Gradient.parse(v);
				} else {
					style.background = color(v);
					style.backgroundImage = null;
				}
			case "backgroundImage": style.backgroundImage = v == null ? null : Std.isOfType(v, String) ? Gradient.parse(v) : v;
			case "transform": style.transform = v == null || v == "none" ? null : Std.isOfType(v, String) ? Transform.parse(v) : (v : Transform);
			case "transformOrigin": style.transformOrigin = v == null ? null : Std.isOfType(v, String) ? Transform.origin(v) : (v : Array<Dim>);
			case "borderColor": style.borderColor = color(v);
			case "radius":
				// (several values: each corner's, as CSS's border-radius)
				if (Std.isOfType(v, String) && StringTools.trim(v).indexOf(" ") > 0) style.corners = CornersValue.parse(v) else if (Std.isOfType(v, Array))
					style.corners = (v : Array<Float>) else {
					style.corners = null;
					style.radius = float(v);
				}
			case "corners": style.corners = v == null ? null : Std.isOfType(v, String) ? CornersValue.parse(v) : Std.isOfType(v, Array) ? (v : Array<Float>) : (v : Corners);
			case "opacity": style.opacity = float(v);
			case "cursor": style.cursor = cursorValue(v);
			case "shadow": style.shadow = v == null ? null : Std.isOfType(v, String) ? Shadow.parse(v) : (v : Shadow);
			case "color": style.color = color(v);
			case "fontFamily": style.fontFamily = v == null ? null : Std.string(v);
			case "fontSize": style.fontSize = float(v);
			case "fontWeight": style.fontWeight = Std.int(float(v));
			case "italic": style.italic = v == true || v == "true";
			case "lineHeight": style.lineHeight = float(v);
			case "letterSpacing": style.letterSpacing = v == "normal" ? 0 : float(v);
			case "wordSpacing": style.wordSpacing = v == "normal" ? 0 : float(v);
			case "textAlign": style.textAlign = textAlignValue(v);
			case "maxLines": style.maxLines = Std.int(float(v));
			case "textDecoration": style.textDecoration = decorationValue(v);
			case "gridTemplateColumns": style.gridTemplateColumns = Std.isOfType(v, String) ? Grid.tracks(v) : v;
			case "gridTemplateRows": style.gridTemplateRows = Std.isOfType(v, String) ? Grid.tracks(v) : v;
			case "gridAutoColumns": style.gridAutoColumns = Std.isOfType(v, String) ? Grid.tracks(v)[0] : v;
			case "gridAutoRows": style.gridAutoRows = Std.isOfType(v, String) ? Grid.tracks(v)[0] : v;
			case "gridAutoFlow": style.gridAutoFlow = v == "column" || v == "Column" ? Grid.GridFlow.Column : v == "row" || v == "Row" ? Grid.GridFlow.Row : v;
			case "gridColumn": style.gridColumn = Std.isOfType(v, String) ? Grid.GridPlacement.parse(v) : Std.isOfType(v, Int) ? new Grid.GridPlacement(v, 0, 1) : v;
			case "gridRow": style.gridRow = Std.isOfType(v, String) ? Grid.GridPlacement.parse(v) : Std.isOfType(v, Int) ? new Grid.GridPlacement(v, 0, 1) : v;
			case "gridArea": style.gridArea = Std.string(v);
			case "gridTemplateAreas": style.gridTemplateAreas = v == null ? null : Std.isOfType(v, String) ? Grid.GridAreas.parse(v) : v;
			case "justifyItems": style.justifyItems = alignItemsValue(v);
			case "justifySelf": style.justifySelf = alignSelfValue(v);
			case _: return false;
		}
		return true;
	}

	public static function isStyle(name:String):Bool
		return NAMES.exists(camel(name));

	static final NAMES = ["display" => true, "position" => true, "direction" => true, "wrap" => true, "justify" => true, "alignItems" => true, "alignSelf" => true, "alignContent" => true, "grow" => true, "shrink" => true, "basis" => true, "width" => true, "height" => true, "minWidth" => true, "minHeight" => true, "maxWidth" => true, "maxHeight" => true, "aspectRatio" => true, "padding" => true, "margin" => true, "borderWidth" => true, "borders" => true, "corners" => true, "rowGap" => true, "columnGap" => true, "left" => true, "top" => true, "right" => true, "bottom" => true, "overflow" => true, "background" => true, "backgroundImage" => true, "borderColor" => true, "radius" => true, "opacity" => true, "cursor" => true, "shadow" => true, "transform" => true, "transformOrigin" => true, "color" => true, "fontFamily" => true, "fontSize" => true, "fontWeight" => true, "italic" => true, "lineHeight" => true, "letterSpacing" => true, "wordSpacing" => true, "textAlign" => true, "maxLines" => true, "textDecoration" => true, "gridTemplateColumns" => true, "gridTemplateRows" => true, "gridAutoColumns" => true, "gridAutoRows" => true, "gridAutoFlow" => true, "gridColumn" => true, "gridRow" => true, "gridArea" => true, "gridTemplateAreas" => true, "justifyItems" => true, "justifySelf" => true];

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
	// "underline", "line-through", "overline", several, "none" (or the flags)
	static function decorationValue(v:Dynamic):Int {
		if (v == null) return 0;
		if (!Std.isOfType(v, String)) return Std.int(v);
		var flags = 0;
		for (w in StringTools.trim((v : String).toLowerCase()).split(" "))
			flags |= switch w {
				case "underline": (TextDecoration.Underline : Int);
				case "line-through": (TextDecoration.LineThrough : Int);
				case "overline": (TextDecoration.Overline : Int);
				case "none" | "": 0;
				case _: throw "hxmc.ui: not a text decoration: " + w;
			}
		return flags;
	}

	static function color(v:Dynamic):Null<Color> {
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

	static function displayValue(v:Dynamic):Null<Display> {
		if (v == null) return null;
		if (!Std.isOfType(v, String)) return v;
		return switch key(v) {
			case "flex": Display.Flex;
			case "none": Display.None;
			case "grid": Display.Grid;
			case _: throw "hxmc.ui: " + v + " is not a Display";
		}
	}

	static function positionValue(v:Dynamic):Null<Position> {
		if (v == null) return null;
		if (!Std.isOfType(v, String)) return v;
		return switch key(v) {
			case "relative": Position.Relative;
			case "absolute": Position.Absolute;
			case _: throw "hxmc.ui: " + v + " is not a Position";
		}
	}

	static function directionValue(v:Dynamic):Null<Direction> {
		if (v == null) return null;
		if (!Std.isOfType(v, String)) return v;
		return switch key(v) {
			case "column": Direction.Column;
			case "row": Direction.Row;
			case "columnreverse": Direction.ColumnReverse;
			case "rowreverse": Direction.RowReverse;
			case _: throw "hxmc.ui: " + v + " is not a Direction";
		}
	}

	static function justifyValue(v:Dynamic):Null<Justify> {
		if (v == null) return null;
		if (!Std.isOfType(v, String)) return v;
		return switch key(v) {
			case "start" | "flexstart": Justify.Start;
			case "end" | "flexend": Justify.End;
			case "center": Justify.Center;
			case "spacebetween": Justify.SpaceBetween;
			case "spacearound": Justify.SpaceAround;
			case "spaceevenly": Justify.SpaceEvenly;
			case "normal": Justify.Normal;
			case _: throw "hxmc.ui: " + v + " is not a Justify";
		}
	}

	static function alignItemsValue(v:Dynamic):Null<Align> {
		if (v == null) return null;
		if (!Std.isOfType(v, String)) return v;
		return switch key(v) {
			case "auto": Align.Auto;
			case "start" | "flexstart": Align.Start;
			case "end" | "flexend": Align.End;
			case "center": Align.Center;
			case "stretch": Align.Stretch;
			case _: throw "hxmc.ui: " + v + " is not a Align";
		}
	}

	static function alignSelfValue(v:Dynamic):Null<Align> {
		if (v == null) return null;
		if (!Std.isOfType(v, String)) return v;
		return switch key(v) {
			case "auto": Align.Auto;
			case "start" | "flexstart": Align.Start;
			case "end" | "flexend": Align.End;
			case "center": Align.Center;
			case "stretch": Align.Stretch;
			case _: throw "hxmc.ui: " + v + " is not a Align";
		}
	}

	static function alignContentValue(v:Dynamic):Null<AlignContent> {
		if (v == null) return null;
		if (!Std.isOfType(v, String)) return v;
		return switch key(v) {
			case "start" | "flexstart": AlignContent.Start;
			case "end" | "flexend": AlignContent.End;
			case "center": AlignContent.Center;
			case "stretch": AlignContent.Stretch;
			case "spacebetween": AlignContent.SpaceBetween;
			case "spacearound": AlignContent.SpaceAround;
			case "spaceevenly": AlignContent.SpaceEvenly;
			case "normal": AlignContent.Normal;
			case _: throw "hxmc.ui: " + v + " is not a AlignContent";
		}
	}

	static function overflowValue(v:Dynamic):Null<Overflow> {
		if (v == null) return null;
		if (!Std.isOfType(v, String)) return v;
		return switch key(v) {
			case "visible": Overflow.Visible;
			case "hidden": Overflow.Hidden;
			case "scroll": Overflow.Scroll;
			case _: throw "hxmc.ui: " + v + " is not a Overflow";
		}
	}

	static function cursorValue(v:Dynamic):Null<Cursor> {
		if (v == null) return null;
		if (!Std.isOfType(v, String)) return v;
		return switch key(v) {
			case "auto": Cursor.Auto;
			case "default": Cursor.Default;
			case "pointer": Cursor.Pointer;
			case "text": Cursor.Text;
			case "crosshair": Cursor.Crosshair;
			case "move": Cursor.Move;
			case "notallowed": Cursor.NotAllowed;
			case "ewresize": Cursor.ResizeEW;
			case "nsresize": Cursor.ResizeNS;
			case _: throw "hxmc.ui: " + v + " is not a Cursor";
		}
	}

	static function textAlignValue(v:Dynamic):Null<TextAlign> {
		if (v == null) return null;
		if (!Std.isOfType(v, String)) return v;
		return switch key(v) {
			case "left": TextAlign.Left;
			case "center": TextAlign.Center;
			case "right": TextAlign.Right;
			case "justify": TextAlign.Justify;
			case _: throw "hxmc.ui: " + v + " is not a TextAlign";
		}
	}
}
