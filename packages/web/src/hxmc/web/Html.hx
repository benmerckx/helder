package hxmc.web;

// What the DOM renderer and the static one share: how an attribute of
// markup becomes an HTML attribute or a DOM property, the style's
// serialization, escaping, void and raw text elements.
//
// Attributes, as Solid has them: class (or className), for (or htmlFor), a
// boolean attribute (hidden, disabled, checked, ...: present when true,
// absent when false or null), data-* and aria-* (attributes, true written
// "true"), any other name an attribute, null or false removing it. A few
// names are DOM properties, set as properties by the DOM renderer and
// written as what the parser makes of them by the static one: value (a
// textarea's content, else the attribute), checked, selected, muted,
// indeterminate, innerHTML (raw markup), textContent (text).
//
// The style: a string, as written, or an object of properties
// ({color: "red", fontSize: 12}: names in camelCase or as CSS has them,
// numbers in px but for the unitless properties, null leaving one out).
class Html {
	// elements without content or end tag
	public static final VOID = [
		"area" => true, "base" => true, "br" => true, "col" => true, "embed" => true, "hr" => true, "img" => true, "input" => true, "link" => true,
		"meta" => true, "source" => true, "track" => true, "wbr" => true
	];

	// boolean attributes (present or absent)
	public static final BOOLEAN = [
		"allowfullscreen" => true, "async" => true, "autofocus" => true, "autoplay" => true, "checked" => true, "controls" => true, "default" => true,
		"defer" => true, "disabled" => true, "formnovalidate" => true, "hidden" => true, "inert" => true, "ismap" => true, "itemscope" => true,
		"loop" => true, "multiple" => true, "muted" => true, "nomodule" => true, "novalidate" => true, "open" => true, "playsinline" => true,
		"readonly" => true, "required" => true, "reversed" => true, "selected" => true
	];

	// names the DOM renderer sets as properties
	public static final PROPERTIES = [
		"value" => true, "checked" => true, "selected" => true, "muted" => true, "indeterminate" => true, "innerHTML" => true, "textContent" => true
	];

	// SVG's own elements (made in its namespace; an element whose name both
	// have, a, title, style or script, is SVG's when written svg:a)
	public static final SVG = [
		"svg" => true, "animate" => true, "animateMotion" => true, "animateTransform" => true, "circle" => true, "clipPath" => true, "defs" => true,
		"desc" => true, "ellipse" => true, "feBlend" => true, "feColorMatrix" => true, "feComposite" => true, "feFlood" => true,
		"feGaussianBlur" => true, "feMerge" => true, "feMergeNode" => true, "feOffset" => true, "filter" => true, "foreignObject" => true, "g" => true,
		"image" => true, "line" => true, "linearGradient" => true, "marker" => true, "mask" => true, "path" => true, "pattern" => true,
		"polygon" => true, "polyline" => true, "radialGradient" => true, "rect" => true, "stop" => true, "symbol" => true, "text" => true,
		"textPath" => true, "tspan" => true, "use" => true
	];

	public static inline final SVG_NS = "http://www.w3.org/2000/svg";

	// CSS properties whose numbers have no unit
	static final UNITLESS = [
		"opacity" => true, "z-index" => true, "flex" => true, "flex-grow" => true, "flex-shrink" => true, "font-weight" => true,
		"line-height" => true, "order" => true, "zoom" => true, "orphans" => true, "widows" => true, "tab-size" => true, "column-count" => true,
		"fill-opacity" => true, "stroke-opacity" => true, "stroke-width" => true, "aspect-ratio" => true
	];

	// a markup attribute's HTML name: class for className, for for htmlFor
	public static inline function attributeName(name:String):String
		return name == "className" ? "class" : name == "htmlFor" ? "for" : name;

	// an attribute's value as written (null: absent)
	public static function attributeValue(name:String, v:Dynamic):Null<String> {
		if (v == null) return null;
		if (BOOLEAN.exists(name)) return v == false || v == "false" ? null : "";
		if (v == false && !StringTools.startsWith(name, "aria-") && !StringTools.startsWith(name, "data-")) return null;
		return Std.string(v);
	}

	// a tag's element name and whether it is SVG's (svg:a: a, SVG's)
	public static inline function isSvgTag(tag:String):Bool
		return SVG.exists(tag) || StringTools.startsWith(tag, "svg:");

	public static inline function localName(tag:String):String
		return StringTools.startsWith(tag, "svg:") ? tag.substr(4) : tag;

	// a style object or string as CSS declarations
	public static function style(v:Dynamic):String {
		if (v == null) return "";
		if (Std.isOfType(v, String)) return v;
		var b = new StringBuf();
		for (f in Reflect.fields(v)) {
			var x:Dynamic = Reflect.field(v, f);
			if (x == null || x == false) continue;
			var name = cssName(f);
			if (b.length > 0) b.add(";");
			b.add(name);
			b.add(":");
			b.add(Std.isOfType(x, Float) && !UNITLESS.exists(name) && x != 0 && !StringTools.startsWith(name, "--") ? x + "px" : Std.string(x));
		}
		return b.toString();
	}

	// fontSize as font-size (custom properties, --x, and names with - kept)
	public static function cssName(f:String):String {
		if (f.indexOf("-") >= 0) return f;
		var b = new StringBuf();
		for (i in 0...f.length) {
			var c = f.charCodeAt(i);
			if (c >= "A".code && c <= "Z".code) {
				b.addChar("-".code);
				b.addChar(c + 32);
			} else b.addChar(c);
		}
		var s = b.toString();
		// (vendor prefixes: WebkitX as -webkit-x)
		return StringTools.startsWith(s, "webkit-") || StringTools.startsWith(s, "moz-") || StringTools.startsWith(s, "ms-") ? "-" + s : s;
	}

	// text as HTML text: &, < and > escaped
	public static function escapeText(s:String):String {
		if (s.indexOf("&") < 0 && s.indexOf("<") < 0 && s.indexOf(">") < 0) return s;
		return StringTools.replace(StringTools.replace(StringTools.replace(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;");
	}

	// text as a double-quoted attribute value: & and " escaped
	public static function escapeAttribute(s:String):String {
		if (s.indexOf("&") < 0 && s.indexOf('"') < 0) return s;
		return StringTools.replace(StringTools.replace(s, "&", "&amp;"), '"', "&quot;");
	}

	// an event attribute's DOM event: onClick click, onDoubleClick dblclick,
	// on:my-event my-event
	public static function eventName(name:String):String {
		if (StringTools.startsWith(name, "on:")) return name.substr(3);
		var e = name.substr(2).toLowerCase();
		return e == "doubleclick" ? "dblclick" : e;
	}
}
