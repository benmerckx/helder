package hxmc.theme;

import hxmc.ui.DimValue;
import hxmc.ui.Grid.TrackSize;

using StringTools;

// a property's value in a TwRule: what Tw writes as an expression of
// StyleProps's types
enum TwValue {
	VNum(v:Float);
	VInt(v:Int);
	VStr(s:String);
	VBool(b:Bool);
	// a case of an enum abstract of hxmc.ui (VEnum("Align", "Center"))
	VEnum(type:String, name:String);
	VDim(d:DimValue);
	// a CSS colour as the engine takes it: "var(--primary)/90", "#ffffff"
	VColor(css:String);
	// top, right, bottom, left
	VEdges(t:Float, r:Float, b:Float, l:Float);
	// top left, top right, bottom right, bottom left
	VCorners(tl:Float, tr:Float, br:Float, bl:Float);
	VShadow(list:Array<TwShadow>);
	VTransform(css:String);
	VTracks(list:Array<{min:TrackSize, max:TrackSize}>);
	VPlacement(start:Int, end:Int, span:Int);
	// CSS's transition shorthand, as Transition.parse reads it
	VTransition(css:String);
}

typedef TwShadow = {x:Float, y:Float, blur:Float, spread:Float, color:String};

// a Rule as data (Tw writes it as an hxmc.ui.Rule): StyleProps's fields
// by name, in the order they were first set
typedef TwRule = {
	slot:String,
	?variant:String,
	?size:String,
	when:Array<String>,
	fields:Array<String>,
	props:Map<String, TwValue>,
}

// Tailwind v4's class lists as rules, the subset shadcn/ui's components
// use, read as Tailwind's default theme with shadcn's on top (its tokens,
// radius scale and globals.css), 1rem = 16px. Plain Haxe: Tw runs it at
// compile time, the tests at run time.
//
// A class is a utility after variants (`dark:aria-invalid:ring-destructive/40`).
// Each variant becomes one of the rule's `when` states (hover, focus-visible,
// data-state=checked, aria-invalid=true, dark), except data-[size=…] and
// data-[variant=…] (also of a group-), which select the rule's size and
// variant as the widget's props do. The classes of a slot that share
// variants make one rule, ordered as Tailwind orders its CSS (by the
// variants' order, the later variant later; the same variants in the order
// of the class list, as cn's tailwind-merge keeps the last), so that the
// engine's "later rules win" gives CSS's cascade. A rule that sets some of
// a shorthand's parts (px-4 of padding, border-b, rounded-t-md, translate-x,
// leading-6 without a font size) takes the others from the rules that hold
// whenever it does, else CSS's initial values. A class neither known nor in
// IGNORED is an error, so nothing is dropped silently.
class Tailwind {
	public static inline var REM = 16.0;

	// shadcn's colour tokens (globals.css's --color-*)
	public static final TOKENS = [
		"background", "foreground", "card", "card-foreground", "popover", "popover-foreground", "primary", "primary-foreground", "secondary",
		"secondary-foreground", "muted", "muted-foreground", "accent", "accent-foreground", "destructive", "border", "input", "ring", "chart-1",
		"chart-2", "chart-3", "chart-4", "chart-5", "sidebar", "sidebar-foreground", "sidebar-primary", "sidebar-primary-foreground",
		"sidebar-accent", "sidebar-accent-foreground", "sidebar-border", "sidebar-ring"
	];

	// utilities dropped, and why: (a trailing * is a prefix, *x* a part)
	public static final IGNORED = [
		// exit animations: ui removes a popup as it closes, nothing is left to animate
		"animate-out", "fade-out*", "zoom-out*", "slide-out-to-*", "spin-out*",
		// keyframe animations, which ui's styles have none of: a skeleton's
		// pulse, an accordion's height (Radix measures it), a spinner's turn
		// (ui's Spinner turns by itself)
		"animate-pulse", "animate-accordion-*", "animate-spin",
		// markers of group-* and peer-* variants
		"group", "group/*", "peer", "peer/*",
		// container queries
		"@container", "@container/*",
		// inherited already
		"text-current",
		// (no StyleProps for them yet: text-underline-offset, auto margins,
		// sizes by calc(), scroll margins, touch-action)
		"underline-offset-*", "h-[calc(100%-1px)]",
		"max-w-[calc(100%-2rem)]", "scroll-my-*", "scroll-py-*", "touch-none",
		// what Radix's popper measures (--radix-*): ui's popups place and size themselves
		"*(--radix-*", "*[var(--radix-*",
		// a textarea growing with its text: the widget's behaviour
		"field-sizing-content",
		// a table's own layout (caption side, collapsed borders, a cell's
		// vertical alignment): ui's Table lays out its cells
		"caption-bottom", "border-collapse", "align-middle",
		// balanced lines: ui's text wraps greedily
		"text-balance",
		// visually hidden text for assistive technology: ui's semantics carry it
		"sr-only",
		// toggle-group's gap from its spacing prop (--gap), 0 unless set: the widget's
		"gap-[--spacing(var(--gap))]",
		// calendar's --cell-size: shadcn.json's vars hold it
		"[--cell-size:--spacing(8)]",
	];

	// variants whose classes are dropped, and why: (a trailing * is a prefix)
	public static final IGNORED_VARIANTS = [
		// file inputs' buttons
		"file",
		// arbitrary selectors: icons inside ([&_svg], [&>svg]), the
		// element type ([a&]), class names ([.border-b]); has-[>svg]: a
		// button's padding beside an icon
		"[*", "has-[*",
		// children's (*:) and descendants' (**:) styles, each of which ui's
		// widgets give their own slot
		"*", "**",
		// pseudo-elements (tabs' line under the active trigger): no node for them
		"after", "before",
	];

	// Tailwind v4's variant order (the later, the later in the CSS);
	// shadcn's dark is a custom variant, after all of them
	static final ORDER = [
		"*", "not", "group", "peer", "first-letter", "first-line", "marker", "selection", "file", "placeholder", "backdrop", "before", "after",
		"first", "last", "only", "odd", "even", "visited", "target", "open", "default", "checked", "indeterminate", "placeholder-shown",
		"autofill", "optional", "required", "valid", "invalid", "read-only", "empty", "focus-within", "hover", "focus", "focus-visible",
		"active", "enabled", "disabled", "inert", "in", "has", "aria", "data", "nth", "supports", "motion-safe", "motion-reduce",
		"contrast-more", "contrast-less", "max", "sm", "md", "lg", "xl", "2xl", "min", "@", "portrait", "landscape", "ltr", "rtl", "dark",
		"starting", "print", "forced-colors"
	];

	// the states a bare variant names
	static final STATES = [
		"hover", "focus", "focus-visible", "active", "disabled", "enabled", "placeholder", "selection", "first", "last", "only", "odd", "even",
		"open", "checked", "indeterminate", "invalid", "focus-within", "dark", "sm", "md", "lg", "xl", "2xl", "ltr", "rtl", "starting"
	];

	// Tailwind v4's transition-* (the properties as Style names them; the
	// colours, opacity, box-shadow and transform are what eases), and its
	// default timing (--default-transition-*)
	static final TRANSITIONS = [
		"" => "color,background,borderColor,outlineColor,textDecorationColor,opacity,shadow,transform", "all" => "all",
		"colors" => "color,background,borderColor,outlineColor,textDecorationColor", "opacity" => "opacity", "shadow" => "shadow",
		"transform" => "transform", "none" => "none"
	];
	static final EASINGS = [
		"linear" => "linear", "in" => "cubic-bezier(0.4,0,1,1)", "out" => "cubic-bezier(0,0,0.2,1)", "in-out" => "cubic-bezier(0.4,0,0.2,1)"
	];
	static inline var EASE_DEFAULT = "cubic-bezier(0.4,0,0.2,1)";
	static inline var DURATION_DEFAULT = 150.0;

	static final TEXT_SIZES = [
		"xs" => [0.75, 1 / 0.75], "sm" => [0.875, 1.25 / 0.875], "base" => [1, 1.5], "lg" => [1.125, 1.75 / 1.125], "xl" => [1.25, 1.75 / 1.25],
		"2xl" => [1.5, 2 / 1.5], "3xl" => [1.875, 2.25 / 1.875], "4xl" => [2.25, 2.5 / 2.25]
	];
	static final WEIGHTS = [
		"thin" => 100, "extralight" => 200, "light" => 300, "normal" => 400, "medium" => 500, "semibold" => 600, "bold" => 700,
		"extrabold" => 800, "black" => 900
	];
	static final LEADING = ["none" => 1, "tight" => 1.25, "snug" => 1.375, "normal" => 1.5, "relaxed" => 1.625, "loose" => 2];
	static final TRACKING = ["tighter" => -0.05, "tight" => -0.025, "normal" => 0, "wide" => 0.025, "wider" => 0.05, "widest" => 0.1];
	static final CONTAINERS = [
		"3xs" => 16, "2xs" => 18, "xs" => 20, "sm" => 24, "md" => 28, "lg" => 32, "xl" => 36, "2xl" => 42, "3xl" => 48, "4xl" => 56, "5xl" => 64,
		"6xl" => 72, "7xl" => 80
	];
	// (shadow-* as CSS writes them: x, y, blur, spread, black's alpha)
	static final SHADOWS:Map<String, Array<Array<Float>>> = [
		"2xs" => [[0, 1, 0, 0, 0.05]], "xs" => [[0, 1, 2, 0, 0.05]], "sm" => [[0, 1, 3, 0, 0.1], [0, 1, 2, -1, 0.1]],
		"md" => [[0, 4, 6, -1, 0.1], [0, 2, 4, -2, 0.1]], "lg" => [[0, 10, 15, -3, 0.1], [0, 4, 6, -4, 0.1]],
		"xl" => [[0, 20, 25, -5, 0.1], [0, 8, 10, -6, 0.1]], "2xl" => [[0, 25, 50, -12, 0.25]]
	];
	static final ALIGN = ["start" => "Start", "end" => "End", "center" => "Center", "stretch" => "Stretch", "baseline" => "Baseline"];
	static final JUSTIFY = [
		"start" => "Start", "end" => "End", "center" => "Center", "between" => "SpaceBetween", "around" => "SpaceAround",
		"evenly" => "SpaceEvenly", "normal" => "Normal"
	];
	static final CURSORS = [
		"auto" => "Auto", "default" => "Default", "pointer" => "Pointer", "text" => "Text", "crosshair" => "Crosshair", "move" => "Move",
		"not-allowed" => "NotAllowed", "ew-resize" => "ResizeEW", "col-resize" => "ResizeEW", "ns-resize" => "ResizeNS",
		"row-resize" => "ResizeNS", "grab" => "Grab", "grabbing" => "Grabbing"
	];
	static final SIDES = ["t" => [0], "r" => [1], "b" => [2], "l" => [3], "x" => [1, 3], "y" => [0, 2], "s" => [3], "e" => [1]];
	static final CORNER_SIDES = [
		"t" => [0, 1], "r" => [1, 2], "b" => [2, 3], "l" => [0, 3], "tl" => [0], "tr" => [1], "br" => [2], "bl" => [3], "s" => [0, 3],
		"e" => [1, 2], "ss" => [0], "se" => [1], "ee" => [2], "es" => [3]
	];

	// --radius in px: rounded-sm, -md, -lg, -xl... are shadcn's multiples of it
	final radius:Float;
	// CSS variables (--cell-size) a class may name: size-(--cell-size)
	final vars:Map<String, String>;
	final error:(message:String, at:Int, length:Int) -> Void;
	// (the class being read: where errors point)
	var at = 0;
	// (the slot has borders or corners on some sides only: borders and corners, not borderWidth and radius)
	var sides = new Map<String, Bool>();
	// (the class lists after variants' and sizes' so far)
	var layer = 0;

	public function new(radius:Float, error:(message:String, at:Int, length:Int) -> Void, ?vars:Map<String, String>) {
		this.radius = radius;
		this.vars = vars ?? new Map();
		this.error = error;
	}

	// the rules of a slot from its class list (the selected variant's or
	// size's, else its base classes), in the order they apply
	public static function rules(slot:String, classes:String, ?variant:String, ?size:String, radius = 10.0):Array<TwRule> {
		var tw = new Tailwind(radius, (m, _, _) -> throw m);
		return tw.slot(slot, [{classes: classes, offset: 0, variant: variant, size: size}]);
	}

	// a slot's rules from several class lists (cva's base, then each
	// variant's and size's), offsets for errors
	public function slot(name:String, lists:Array<{classes:String, offset:Int, ?variant:String, ?size:String, ?prefix:String}>):Array<TwRule> {
		var groups:Array<Group> = [];
		sides = new Map();
		// (a class list after a variant's or size's, as cn's className after
		// cva's: its rules after theirs, apart from the base's)
		var selected = false;
		layer = 0;
		for (l in lists) {
			if (l.variant != null || l.size != null) selected = true else if (selected) {
				selected = false;
				layer++;
			}
			var i = 0, s = l.classes;
			while (i < s.length) {
				while (i < s.length && s.charCodeAt(i) <= " ".code)
					i++;
				var j = i;
				while (j < s.length && s.charCodeAt(j) > " ".code)
					j++;
				if (j > i) {
					at = l.offset + i;
					parse((l.prefix == null ? "" : l.prefix + ":") + s.substring(i, j), l.variant, l.size, groups);
				}
				i = j;
			}
		}
		// (two enter animations' starts that hold together, a popup side's
		// slide and its open state's zoom: one transform of both, after
		// them, as tw-animate-css's variables compose)
		var starts = [for (g in groups) if (g.when.contains("starting") && Lambda.exists(g.keys, isTransform)) g];
		for (i in 0...starts.length)
			for (j in i + 1...starts.length) {
				var a = starts[i], b = starts[j];
				if (a.holdsWith(b) || b.holdsWith(a) || a.variant != null && b.variant != null && a.variant != b.variant
					|| a.size != null && b.size != null && a.size != b.size) continue;
				var u = new Group(a.key + "+" + b.key, a.variant ?? b.variant, a.size ?? b.size, a.when.concat([for (w in b.when) if (!a.when.contains(w)) w]),
					a.order.concat(b.order));
				u.order.sort((x, y) -> y - x);
				for (k in a.keys.concat(b.keys))
					if (isTransform(k) && !u.keys.contains(k)) u.keys.push(k);
				groups.push(u);
			}
		// (stable: the same variants keep the classes' order)
		var seq = [for (i in 0...groups.length) groups[i] => i];
		groups.sort((a, b) -> {
			var c = compareOrder(a.order, b.order);
			c != 0 ? c : seq[a] - seq[b];
		});
		var out = [];
		for (i in 0...groups.length) {
			var r = finish(name, groups, i);
			if (r.fields.length > 0) out.push(r);
		}
		return out;
	}

	static function isTransform(k:String):Bool
		return k.startsWith("translate.") || k == "rotate" || k == "scale";

	// (variant orders compared as Tailwind's bitmasks: the latest variant decides)
	static function compareOrder(a:Array<Int>, b:Array<Int>):Int {
		for (i in 0...(a.length > b.length ? a.length : b.length)) {
			if (i >= a.length) return -1;
			if (i >= b.length) return 1;
			if (a[i] != b[i]) return a[i] - b[i];
		}
		return 0;
	}

	static function matches(list:Array<String>, name:String):Bool {
		for (p in list)
			if (p == name || p != "*" && p != "**" && p.endsWith("*")
				&& (p.startsWith("*") && p.length > 2 ? name.indexOf(p.substring(1, p.length - 1)) >= 0 : name.startsWith(p.substr(0, p.length - 1))))
				return true;
		return false;
	}

	// (the class's parts between colons outside brackets and parentheses)
	static function splitVariants(c:String):Array<String> {
		var parts = [], depth = 0, start = 0;
		for (i in 0...c.length) {
			var ch = c.charCodeAt(i);
			if (ch == "[".code || ch == "(".code) depth++ else if (ch == "]".code || ch == ")".code) depth-- else if (ch == ":".code
				&& depth == 0) {
				parts.push(c.substring(start, i));
				start = i + 1;
			}
		}
		parts.push(c.substr(start));
		return parts;
	}

	function parse(c:String, variant:Null<String>, size:Null<String>, groups:Array<Group>) {
		var parts = splitVariants(c);
		var utility = parts.pop();
		// (!important: the rule keeps its place; CSS would let it beat every other)
		if (utility.endsWith("!")) utility = utility.substr(0, utility.length - 1) else if (utility.startsWith("!")) utility = utility.substr(1);
		var when = [], order = [];
		for (v in parts) {
			if (matches(IGNORED_VARIANTS, v)) return;
			var r = readVariant(v);
			if (r == null) {
				error('unknown variant $v: in $c', at, c.length);
				return;
			}
			order.push(r.order);
			if (r.size != null) size = r.size else if (r.variant != null) variant = r.variant else when.push(r.state);
		}
		if (matches(IGNORED, utility)) return;
		var props = utilityProps(utility);
		if (props == null) {
			error('unknown class $c', at, c.length);
			return;
		}
		// (an enter animation's from: tw-animate-css's fade-in, zoom-in,
		// slide-in-from-*, as the starting state the node's transition eases from)
		if (Lambda.exists(props, p -> p.key.startsWith("start."))) {
			props = [for (p in props) {key: p.key.substr(6), value: p.value}];
			if (!when.contains("starting")) {
				when.push("starting");
				order.push(ORDER.indexOf("starting"));
			}
		}
		order.sort((a, b) -> b - a);
		var key = '$layer|$variant|$size|' + when.join("&");
		var g = null;
		for (x in groups)
			if (x.key == key) g = x;
		if (g == null) {
			g = new Group(key, variant, size, when, order);
			groups.push(g);
		}
		for (p in props) {
			if (!g.parts.exists(p.key)) g.keys.push(p.key);
			g.parts[p.key] = p.value;
			if (p.key.startsWith("border.") && props.length != 4) sides["border"] = true;
			if (p.key.startsWith("corner.") && props.length != 4) sides["corner"] = true;
		}
	}

	// a variant: its state, or the size or variant it selects, and its order
	function readVariant(v:String):Null<{order:Int, ?state:String, ?size:String, ?variant:String}> {
		inline function ord(name:String)
			return ORDER.indexOf(name);
		if (STATES.contains(v)) return {order: ord(v), state: v};
		for (prefix in ["group", "peer", "has", "not"])
			if (v.startsWith(prefix + "-")) {
				var inner = v.substr(prefix.length + 1);
				// (group-hover/item: the group named item, "group/item:hover"; a group's data-[size=sm] selects the size, its name aside)
				var slash = inner.lastIndexOf("/"), name = "";
				if (slash > inner.lastIndexOf("]")) {
					name = prefix == "group" || prefix == "peer" ? "/" + inner.substr(slash + 1) : "";
					inner = inner.substr(0, slash);
				}
				var r = readVariant(inner);
				if (r == null) return null;
				if (r.size != null || r.variant != null) return {order: ord(prefix), size: r.size, variant: r.variant};
				return {order: ord(prefix), state: prefix + name + ":" + r.state};
			}
		if (v.startsWith("aria-")) {
			var a = v.substr(5);
			return {order: ord("aria"), state: a.startsWith("[") ? "aria-" + attribute(a) : 'aria-$a=true'};
		}
		if (v.startsWith("data-")) {
			var a = v.substr(5);
			var attr = a.startsWith("[") ? attribute(a) : a;
			var eq = attr.indexOf("=");
			var name = eq < 0 ? attr : attr.substr(0, eq);
			if (eq > 0 && name == "size") return {order: ord("data"), size: attr.substr(eq + 1)};
			if (eq > 0 && name == "variant") return {order: ord("data"), variant: attr.substr(eq + 1)};
			return {order: ord("data"), state: "data-" + attr};
		}
		return null;
	}

	// ([state=checked], [disabled], [state="open"]: name=value, quotes left out)
	static function attribute(a:String):String
		return a.substring(1, a.length - 1).replace('"', "").replace("'", "");

	// a utility's parts: StyleProps's fields, or parts of one ("padding.0"...)
	function utilityProps(u:String):Null<Array<{key:String, value:TwValue}>> {
		var neg = u.startsWith("-");
		if (neg) u = u.substr(1);
		var out = [];
		inline function set(k:String, v:TwValue)
			out.push({key: k, value: v});
		inline function en(k:String, type:String, name:String)
			set(k, VEnum(type, name));
		// (the value after a prefix: "px-4" after "px-" is "4")
		function after(p:String):Null<String>
			return u.startsWith(p) ? u.substr(p.length) : null;
		function signed(v:Null<Float>):Null<Float>
			return v == null ? null : neg ? -v : v;
		switch u {
			case "flex" | "inline-flex":
				en("display", "Display", "Flex");
				en("direction.default", "Direction", "Row");
			case "grid" | "inline-grid": en("display", "Display", "Grid");
			case "hidden": en("display", "Display", "None");
			case "block" | "inline-block" | "inline": en("display", "Display", "Flex");
			case "flex-col": en("direction", "Direction", "Column");
			case "flex-row": en("direction", "Direction", "Row");
			case "flex-col-reverse": en("direction", "Direction", "ColumnReverse");
			case "flex-row-reverse": en("direction", "Direction", "RowReverse");
			case "flex-wrap": set("wrap", VBool(true));
			case "flex-nowrap": set("wrap", VBool(false));
			case "flex-1": set("flex", VNum(1));
			case "flex-none":
				set("grow", VNum(0));
				set("shrink", VNum(0));
				set("basis", VDim(Auto));
			case "shrink": set("shrink", VNum(1));
			case "shrink-0": set("shrink", VNum(0));
			case "grow": set("grow", VNum(1));
			case "grow-0": set("grow", VNum(0));
			case "place-content-center":
				en("alignContent", "AlignContent", "Center");
				en("justify", "Justify", "Center");
			case "place-items-center":
				en("alignItems", "Align", "Center");
				en("justifyItems", "Align", "Center");
			case "relative": en("position", "Position", "Relative");
			case "absolute" | "fixed": en("position", "Position", "Absolute");
			case "sticky": en("position", "Position", "Sticky");
			case "overflow-hidden" | "overflow-clip": en("overflow", "Overflow", "Hidden");
			case "overflow-x-hidden" | "overflow-x-clip": en("overflowX", "Overflow", "Hidden");
			case "overflow-y-hidden" | "overflow-y-clip": en("overflowY", "Overflow", "Hidden");
			case "overflow-x-auto" | "overflow-x-scroll": en("overflowX", "Overflow", "Scroll");
			case "overflow-y-auto" | "overflow-y-scroll": en("overflowY", "Overflow", "Scroll");
			case "overflow-x-visible": en("overflowX", "Overflow", "Visible");
			case "overflow-y-visible": en("overflowY", "Overflow", "Visible");
			case "select-none": en("userSelect", "UserSelect", "None");
			case "select-text": en("userSelect", "UserSelect", "Text");
			case "select-all": en("userSelect", "UserSelect", "All");
			case "select-auto": en("userSelect", "UserSelect", "Auto");
			case "overflow-visible": en("overflow", "Overflow", "Visible");
			case "overflow-auto" | "overflow-scroll": en("overflow", "Overflow", "Scroll");
			case "visible": en("visibility", "Visibility", "Visible");
			case "invisible": en("visibility", "Visibility", "Hidden");
			case "pointer-events-none": en("pointerEvents", "PointerEvents", "None");
			case "pointer-events-auto": en("pointerEvents", "PointerEvents", "Auto");
			case "border": for (i in 0...4) set('border.$i', VNum(1));
			case "rounded": for (i in 0...4) set('corner.$i', VNum(4));
			case "shadow-none": set("shadow", VShadow([]));
			case "ring": set("ringWidth", VNum(1));
			case "ring-inset": set("ringInset", VBool(true));
			// (outline-hidden: a transparent outline, shown only in forced colours; neither draws the window's focus ring)
			case "outline-none" | "outline-hidden": en("outlineStyle", "OutlineStyle", "None");
			case "outline":
				set("outlineWidth", VNum(1));
				en("outlineStyle", "OutlineStyle", "Solid");
			case "animate-in": set("enter", VBool(true));
			case "underline": set("textDecoration", VInt(1));
			case "line-through": set("textDecoration", VInt(2));
			case "overline": set("textDecoration", VInt(4));
			case "no-underline": set("textDecoration", VInt(0));
			case "uppercase": en("textTransform", "TextTransform", "Uppercase");
			case "lowercase": en("textTransform", "TextTransform", "Lowercase");
			case "capitalize": en("textTransform", "TextTransform", "Capitalize");
			case "normal-case": en("textTransform", "TextTransform", "None");
			case "italic": set("italic", VBool(true));
			case "not-italic": set("italic", VBool(false));
			case "whitespace-nowrap" | "text-nowrap": en("textWrap", "TextWrap", "NoWrap");
			case "whitespace-normal" | "text-wrap": en("textWrap", "TextWrap", "Wrap");
			case "truncate":
				en("overflow", "Overflow", "Hidden");
				en("textOverflow", "TextOverflow", "Ellipsis");
				en("textWrap", "TextWrap", "NoWrap");
			case "text-ellipsis": en("textOverflow", "TextOverflow", "Ellipsis");
			case "break-words": en("overflowWrap", "OverflowWrap", "BreakWord");
			case "break-all": en("wordBreak", "WordBreak", "BreakAll");
			case "tabular-nums": set("fontVariantNumeric", VStr("tabular-nums"));
			case "text-left": en("textAlign", "TextAlign", "Left");
			case "text-center": en("textAlign", "TextAlign", "Center");
			case "text-right": en("textAlign", "TextAlign", "Right");
			case "text-justify": en("textAlign", "TextAlign", "Justify");
			case "font-sans": set("fontFamily", VStr("sans-serif"));
			case "font-serif": set("fontFamily", VStr("serif"));
			case "font-mono": set("fontFamily", VStr("monospace"));
			case "aspect-square": set("aspectRatio", VNum(1));
			case "aspect-video": set("aspectRatio", VNum(16 / 9));
			case _:
		}
		if (out.length > 0) return out;
		var v:Null<String>;
		// spacing: padding, margin, gap
		for (p in ["p", "m"]) {
			var field = p == "p" ? "padding" : "margin";
			for (side in ["", "x", "y", "t", "r", "b", "l", "s", "e"])
				if ((v = after(p + side + "-")) != null) {
					// (an auto margin: NaN, as Edges.AUTO)
					var n = p == "m" && v == "auto" && !neg ? Math.NaN : signed(spacing(v));
					if (n == null || p == "p" && neg) return null;
					for (i in (side == "" ? [0, 1, 2, 3] : SIDES[side]))
						set('$field.$i', VNum(n));
					return out;
				}
		}
		for (g in [["gap-x-", "columnGap"], ["gap-y-", "rowGap"], ["gap-", "gap"]])
			if ((v = after(g[0])) != null) {
				var n = spacing(v);
				if (n == null) return null;
				set(g[1], VNum(n));
				return out;
			}
		// sizes
		if ((v = after("size-")) != null) {
			var d = size(v, false);
			if (d == null) return null;
			set("width", VDim(d));
			set("height", VDim(d));
			return out;
		}
		for (s in [
			["min-w-", "minWidth"], ["min-h-", "minHeight"], ["max-w-", "maxWidth"], ["max-h-", "maxHeight"], ["w-", "width"], ["h-", "height"],
			["basis-", "basis"]
		])
			if ((v = after(s[0])) != null) {
				var d = size(v, s[0] == "max-w-");
				if (d == null) return null;
				set(s[1], VDim(d));
				return out;
			}
		for (s in [["inset-x-", "left", "right"], ["inset-y-", "top", "bottom"], ["inset-", "left", "right", "top", "bottom"], ["top-", "top"],
			["right-", "right"], ["bottom-", "bottom"], ["left-", "left"]])
			if ((v = after(s[0])) != null) {
				var d = size(v, false);
				if (d == null) return null;
				if (neg) d = switch d {
					case Px(x): Px(-x);
					case Percent(x): Percent(-x);
					case _: return null;
				}
				for (k in s.slice(1))
					set(k, VDim(d));
				return out;
			}
		if ((v = after("z-")) != null) {
			var n = Std.parseInt(v);
			if (n == null) return null;
			set("zIndex", VInt(n));
			return out;
		}
		if ((v = after("order-")) != null) {
			var n = Std.parseInt(v);
			if (n == null) return null;
			set("order", VInt(neg ? -n : n));
			return out;
		}
		if ((v = after("opacity-")) != null) {
			var n = Std.parseFloat(v);
			if (Math.isNaN(n)) return null;
			set("opacity", VNum(n / 100));
			return out;
		}
		if ((v = after("line-clamp-")) != null) {
			var n = Std.parseInt(v);
			if (n == null) return null;
			set("maxLines", VInt(n));
			return out;
		}
		if ((v = after("cursor-")) != null) {
			if (!CURSORS.exists(v)) return null;
			en("cursor", "Cursor", CURSORS[v]);
			return out;
		}
		// flex and grid alignment
		for (a in [["items-", "alignItems"], ["self-", "alignSelf"], ["justify-items-", "justifyItems"], ["justify-self-", "justifySelf"]])
			if ((v = after(a[0])) != null) {
				var name = v == "auto" ? "Auto" : ALIGN[v];
				if (name == null) return null;
				en(a[1], "Align", name);
				return out;
			}
		if ((v = after("justify-")) != null) {
			if (!JUSTIFY.exists(v)) return null;
			en("justify", "Justify", JUSTIFY[v]);
			return out;
		}
		if ((v = after("content-")) != null) {
			var name = v == "normal" ? "Normal" : JUSTIFY[v];
			if (name == null) return null;
			en("alignContent", "AlignContent", name);
			return out;
		}
		for (t in [["grid-cols-", "gridTemplateColumns"], ["grid-rows-", "gridTemplateRows"]])
			if ((v = after(t[0])) != null) {
				var n = Std.parseInt(v);
				var list = n != null ? [for (_ in 0...n) {min: TrackSize.Px(0), max: TrackSize.Fr(1)}] : v.startsWith("[") ? tracks(v) : null;
				if (list == null) return null;
				set(t[1], VTracks(list));
				return out;
			}
		for (t in [["auto-rows-", "gridAutoRows"], ["auto-cols-", "gridAutoColumns"]])
			if ((v = after(t[0])) != null) {
				var s:TrackSize = switch v {
					case "auto": Auto;
					case "min": MinContent;
					case "max": MaxContent;
					case "fr": Fr(1);
					case _: return null;
				}
				set(t[1], VTracks([{min: v == "fr" ? TrackSize.Px(0) : s, max: s}]));
				return out;
			}
		for (axis in [["col", "gridColumn"], ["row", "gridRow"]]) {
			for (part in ["span", "start", "end"])
				if ((v = after(axis[0] + "-" + part + "-")) != null) {
					var n = v == "full" && part == "span" ? -1 : Std.parseInt(v);
					if (n == null) return null;
					if (n == -1) {
						set(axis[1] + ".start", VInt(1));
						set(axis[1] + ".end", VInt(-1));
					} else set(axis[1] + "." + part, VInt(n));
					return out;
				}
		}
		// borders and corners
		if ((v = after("border-")) != null) {
			var w = borderWidth(v);
			if (w != null) {
				for (i in 0...4)
					set('border.$i', VNum(w));
				return out;
			}
			var dash = v.indexOf("-");
			var side = dash < 0 ? v : v.substr(0, dash);
			if (SIDES.exists(side)) {
				w = dash < 0 ? 1 : borderWidth(v.substr(dash + 1));
				if (w == null) return null;
				for (i in SIDES[side])
					set('border.$i', VNum(w));
				return out;
			}
			var c = color(v);
			if (c == null) return null;
			set("borderColor", VColor(c));
			return out;
		}
		if ((v = after("rounded-")) != null) {
			var dash = v.indexOf("-");
			var corners = [0, 1, 2, 3];
			if (CORNER_SIDES.exists(v)) {
				corners = CORNER_SIDES[v];
				v = "";
			} else if (dash > 0 && CORNER_SIDES.exists(v.substr(0, dash))) {
				corners = CORNER_SIDES[v.substr(0, dash)];
				v = v.substr(dash + 1);
			}
			var r = rounded(v);
			if (r == null) return null;
			for (i in corners)
				set('corner.$i', VNum(r));
			return out;
		}
		// colours, text
		if ((v = after("bg-")) != null) {
			var c = color(v);
			if (c == null) return null;
			set("background", VColor(c));
			return out;
		}
		if ((v = after("text-")) != null) {
			var slash = v.indexOf("/");
			var name = slash < 0 ? v : v.substr(0, slash);
			if (TEXT_SIZES.exists(name)) {
				var s = TEXT_SIZES[name];
				set("fontSize", VNum(s[0] * REM));
				if (slash < 0) set("textLeading", VNum(s[1])) else {
					var l = leading(v.substr(slash + 1));
					if (l == null) return null;
					set("leading", l);
				}
				return out;
			}
			if (v.startsWith("[")) {
				var n = length(v.substring(1, v.length - 1));
				if (n == null) return null;
				set("fontSize", VNum(n));
				return out;
			}
			var c = color(v);
			if (c == null) return null;
			set("color", VColor(c));
			return out;
		}
		if ((v = after("font-")) != null) {
			var w = WEIGHTS[v];
			if (w == null && v.startsWith("[")) w = Std.parseInt(v.substring(1, v.length - 1));
			if (w == null) return null;
			set("fontWeight", VInt(w));
			return out;
		}
		if ((v = after("leading-")) != null) {
			var l = leading(v);
			if (l == null) return null;
			set("leading", l);
			return out;
		}
		if ((v = after("tracking-")) != null) {
			var em = TRACKING[v];
			if (em == null) return null;
			set("tracking", VNum(neg ? -em : em));
			return out;
		}
		// shadows, rings, outlines
		if ((v = after("shadow-")) != null) {
			if (v.startsWith("[")) {
				var s = shadow(v.substring(1, v.length - 1));
				if (s == null) return null;
				set("shadow", VShadow([s]));
				return out;
			}
			var s = SHADOWS[v];
			if (s == null) return null;
			set("shadow", VShadow([for (x in s) {x: x[0], y: x[1], blur: x[2], spread: x[3], color: 'rgba(0, 0, 0, ${x[4]})'}]));
			return out;
		}
		// (a ring: Tailwind's box-shadow of no blur outside the border box, and its offset's gap)
		for (o in ["ring", "outline"]) {
			if ((v = after('$o-offset-')) != null) {
				var w = borderWidth(v);
				if (w != null) set(o == "ring" ? "ringOffsetWidth" : "outlineOffset", VNum(w)) else {
					var c = o == "ring" ? color(v) : null;
					if (c == null) return null;
					set("ringOffsetColor", VColor(c));
				}
				return out;
			}
			if ((v = after('$o-')) != null) {
				var w = borderWidth(v);
				if (w != null) {
					set('${o}Width', VNum(w));
					if (o == "outline") en("outlineStyle", "OutlineStyle", "Solid");
				} else {
					var c = color(v);
					if (c == null) return null;
					set('${o}Color', VColor(c));
				}
				return out;
			}
		}
		// transitions: their properties, duration, easing and delay
		if ((v = u == "transition" ? "" : after("transition-")) != null) {
			var p = TRANSITIONS[v];
			if (p == null && v.startsWith("[") && v.endsWith("]")) p = [for (c in v.substring(1, v.length - 1).split(",")) styleName(c)].join(",");
			if (p == null) return null;
			set("transition.property", VStr(p));
			return out;
		}
		for (t in [["duration-", "transition.duration"], ["delay-", "transition.delay"]])
			if ((v = after(t[0])) != null) {
				var n = number(v);
				if (n == null) return null;
				set(t[1], VNum(n));
				return out;
			}
		if ((v = after("ease-")) != null) {
			var e = EASINGS[v];
			if (e == null) return null;
			set("transition.easing", VStr(e));
			return out;
		}
		// an enter animation's start (tw-animate-css: with animate-in, from these to the node's own)
		if (u == "fade-in" || (v = after("fade-in-")) != null) {
			var n = u == "fade-in" ? 0 : number(v);
			if (n == null) return null;
			set("start.opacity", VNum(n / 100));
			return out;
		}
		if (u == "zoom-in" || (v = after("zoom-in-")) != null) {
			var n = u == "zoom-in" ? 0 : number(v);
			if (n == null) return null;
			set("start.scale", VStr("" + n / 100));
			return out;
		}
		if ((v = after("spin-in-")) != null) {
			var n = number(v);
			if (n == null) return null;
			set("start.rotate", VStr(n + "deg"));
			return out;
		}
		if ((v = after("slide-in-from-")) != null) {
			var dash = v.indexOf("-");
			var side = dash < 0 ? v : v.substr(0, dash), amount = dash < 0 ? "full" : v.substr(dash + 1);
			var axis = side == "top" || side == "bottom" ? "y" : side == "left" || side == "right" ? "x" : null;
			var t = axis == null ? null : translate(amount, side == "top" || side == "left");
			if (t == null) return null;
			set('start.translate.$axis', VStr(t));
			return out;
		}
		if ((v = after("fill-")) != null) {
			var c = color(v);
			if (c == null) return null;
			set("color", VColor(c));
			return out;
		}
		// transforms
		for (axis in ["x", "y"])
			if ((v = after('translate-$axis-')) != null) {
				var t = translate(v, neg);
				if (t == null) return null;
				set('translate.$axis', VStr(t));
				return out;
			}
		if ((v = after("rotate-")) != null) {
			var n = v.startsWith("[") ? null : Std.parseFloat(v);
			if (n == null || Math.isNaN(n)) return null;
			set("rotate", VStr((neg ? -n : n) + "deg"));
			return out;
		}
		if ((v = after("scale-")) != null) {
			var n = Std.parseFloat(v);
			if (Math.isNaN(n)) return null;
			set("scale", VStr("" + n / 100));
			return out;
		}
		return null;
	}

	// (shadow-[0_4px_12px_rgba(0,0,0,0.1)]: x, y, blur, spread in px, a colour)
	static function shadow(v:String):Null<TwShadow> {
		var paren = v.indexOf("(");
		var parts = (paren < 0 ? v : v.substr(0, paren)).split("_").filter(p -> p != "");
		var color = paren < 0 ? parts.pop() : parts.pop() + v.substr(paren);
		var n = [for (p in parts) length(p)];
		if (n.length < 2 || n.length > 4 || n.contains(null) || color == null) return null;
		while (n.length < 4)
			n.push(0);
		return {x: n[0], y: n[1], blur: n[2], spread: n[3], color: color};
	}

	// --spacing (0.25rem) times n, px, or an arbitrary length
	function spacing(v:String):Null<Float> {
		if (v == "px") return 1;
		if (v.startsWith("(") && v.endsWith(")")) return vars.exists(v.substring(1, v.length - 1)) ? length(vars[v.substring(1, v.length - 1)]) : null;
		if (v.startsWith("[")) return length(v.substring(1, v.length - 1));
		var n = number(v);
		return n == null ? null : n * 0.25 * REM;
	}

	// (a number as Tailwind's scales write it, whole or in halves: 0, 1.5)
	static function number(v:String):Null<Float> {
		for (i in 0...v.length) {
			var c = v.charCodeAt(i);
			if (!(c >= "0".code && c <= "9".code || c == ".".code)) return null;
		}
		var n = Std.parseFloat(v);
		return Math.isNaN(n) ? null : n;
	}

	// a CSS length in px: 3px, 1.15rem, 0
	static function length(v:String):Null<Float> {
		var n = number(v.endsWith("px") ? v.substr(0, v.length - 2) : v.endsWith("rem") ? v.substr(0, v.length - 3) : v);
		return n == null ? null : v.endsWith("rem") ? n * REM : v.endsWith("px") || n == 0 ? n : null;
	}

	// a width, height, size or inset: spacing, a fraction, full, auto, fit...
	function size(v:String, max:Bool):Null<DimValue> {
		switch v {
			case "full": return Percent(100);
			case "auto" | "none": return Auto;
			case "fit": return FitContent;
			case "min": return MinContent;
			case "max": return MaxContent;
			case _:
		}
		if (max && CONTAINERS.exists(v)) return Px(CONTAINERS[v] * REM);
		var slash = v.indexOf("/");
		if (slash > 0) {
			var a = number(v.substr(0, slash)), b = number(v.substr(slash + 1));
			return a == null || b == null || b == 0 ? null : Percent(a / b * 100);
		}
		if (v.startsWith("[") && v.endsWith("%]")) {
			var p = number(v.substring(1, v.length - 2));
			return p == null ? null : Percent(p);
		}
		var n = spacing(v);
		return n == null ? null : Px(n);
	}

	// border-N, ring-N: a width in px
	static function borderWidth(v:String):Null<Float> {
		if (v.startsWith("[")) return length(v.substring(1, v.length - 1));
		var n = Std.parseInt(v);
		return n == null || "" + n != v ? null : n;
	}

	// rounded-*: shadcn's multiples of --radius (globals.css's @theme), Tailwind's otherwise
	function rounded(v:String):Null<Float>
		return switch v {
			case "": 4;
			case "none": 0;
			case "xs": 2;
			case "sm": radius * 0.6;
			case "md": radius * 0.8;
			case "lg": radius;
			case "xl": radius * 1.4;
			case "2xl": radius * 1.8;
			case "3xl": radius * 2.2;
			case "4xl": radius * 2.6;
			// (calc(infinity * 1px): as many px as any box needs)
			case "full": 1e6;
			case _: v.startsWith("[") ? length(v.substring(1, v.length - 1)) : null;
		}

	// leading-*: a multiple of the font size, or px (VDim) to divide by it
	function leading(v:String):Null<TwValue> {
		if (LEADING.exists(v)) return VNum(LEADING[v]);
		// (leading-[1.4]: a multiple)
		if (v.startsWith("[") && number(v.substring(1, v.length - 1)) != null) return VNum(number(v.substring(1, v.length - 1)));
		var n = spacing(v);
		return n == null ? null : VDim(Px(n));
	}

	// a colour: a token (with an alpha in percent), white, black, transparent
	static function color(v:String):Null<String> {
		var slash = v.lastIndexOf("/");
		var name = slash < 0 ? v : v.substr(0, slash);
		var alpha = slash < 0 ? null : number(v.substr(slash + 1));
		if (slash >= 0 && alpha == null) return null;
		if (TOKENS.contains(name)) return 'var(--$name)' + (alpha == null ? "" : '/$alpha');
		var rgb = switch name {
			case "white": "255, 255, 255";
			case "black": "0, 0, 0";
			case "transparent": return alpha == null ? "transparent" : null;
			case _: return null;
		}
		return alpha == null ? 'rgb($rgb)' : 'rgba($rgb, ${alpha / 100})';
	}

	// a translation: spacing, a fraction or full (of the box), an arbitrary
	// length or percentage, calc(a% - b px) as two
	function translate(v:String, neg:Bool):Null<String> {
		inline function sign(s:String)
			return neg ? (s.startsWith("-") ? s.substr(1) : "-" + s) : s;
		if (v == "full") return sign("100%");
		var slash = v.indexOf("/");
		if (slash > 0) {
			var a = number(v.substr(0, slash)), b = number(v.substr(slash + 1));
			return a == null || b == null || b == 0 ? null : sign(a / b * 100 + "%");
		}
		if (v.startsWith("[")) {
			var a = v.substring(1, v.length - 1).replace("_", "");
			if (a.startsWith("calc(") && a.endsWith(")")) {
				// calc(100%-2px), calc(-50% - 2px): a percentage, then px
				var body = a.substring(5, a.length - 1);
				var op = body.indexOf("-", 1);
				var plus = body.indexOf("+", 1);
				if (plus > 0 && (op < 0 || plus < op)) op = plus;
				if (op < 0) return null;
				var p = body.substr(0, op), l = length(body.substr(op + 1));
				if (!p.endsWith("%") || l == null) return null;
				if (body.charAt(op) == "-") l = -l;
				return neg ? null : p + " " + l + "px";
			}
			if (a.endsWith("%")) return number(a.startsWith("-") ? a.substring(1, a.length - 1) : a.substr(0, a.length - 1)) == null ? null : sign(a);
			var l = length(a.startsWith("-") ? a.substr(1) : a);
			return l == null ? null : sign((a.startsWith("-") ? -l : l) + "px");
		}
		var n = spacing(v);
		return n == null ? null : sign(n + "px");
	}

	// (a CSS property as Style names it, as Transition.parse does: box-shadow is shadow)
	static function styleName(css:String):String
		return switch css {
			case "background-color" | "background": "background";
			case "box-shadow": "shadow";
			case "translate" | "scale" | "rotate": "transform";
			case _: [for (i => w in css.split("-")) i == 0 ? w : w.charAt(0).toUpperCase() + w.substr(1)].join("");
		}

	// grid-cols-[1fr_auto], grid-rows-[auto_auto]
	static function tracks(v:String):Null<Array<{min:TrackSize, max:TrackSize}>> {
		var out = [];
		for (t in v.substring(1, v.length - 1).split("_")) {
			var s:TrackSize = if (t == "auto") Auto else if (t == "min-content") MinContent else if (t == "max-content") MaxContent else if (t.endsWith("fr")) {
				var n = number(t.substr(0, t.length - 2));
				if (n == null) return null;
				Fr(n);
			} else if (t.endsWith("%")) {
				var n = number(t.substr(0, t.length - 1));
				if (n == null) return null;
				Percent(n);
			} else {
				var n = length(t);
				if (n == null) return null;
				Px(n);
			}
			out.push({min: s.match(Fr(_)) ? TrackSize.Auto : s, max: s});
		}
		return out;
	}

	// a group's rule: its parts made StyleProps's fields, a shorthand's
	// parts it leaves out from the groups before it that hold whenever it
	// does (else CSS's initial values)
	function finish(slot:String, groups:Array<Group>, i:Int):TwRule {
		var g = groups[i];
		function inherited(k:String):Null<TwValue> {
			if (g.parts.exists(k)) return g.parts[k];
			var j = i;
			while (--j >= 0)
				if (groups[j].holdsWith(g) && groups[j].parts.exists(k)) return groups[j].parts[k];
			return null;
		}
		function num(k:String, initial:Float):Float
			return switch inherited(k) {
				case VNum(v): v;
				case _: initial;
			}
		var r:TwRule = {slot: slot, when: g.when, fields: [], props: new Map()};
		if (g.variant != null) r.variant = g.variant;
		if (g.size != null) r.size = g.size;
		function field(k:String, v:TwValue) {
			if (!r.props.exists(k)) r.fields.push(k);
			r.props[k] = v;
		}
		var done = new Map<String, Bool>();
		for (k in g.keys) {
			var dot = k.indexOf(".");
			var base = dot < 0 ? k : k.substr(0, dot);
			if (done.exists(base)) continue;
			done[base] = true;
			switch base {
				case "padding" | "margin":
					// (all four sides: the shorthand; else each side the rule sets, as CSS's longhands)
					var all = [for (s in 0...4) g.parts.exists('$base.$s')].indexOf(false) < 0;
					if (all) field(base, VEdges(num('$base.0', 0), num('$base.1', 0), num('$base.2', 0), num('$base.3', 0))) else
						for (s in 0...4)
							if (g.parts.exists('$base.$s')) field(base + ["Top", "Right", "Bottom", "Left"][s], g.parts['$base.$s']);
				case "border":
					var e = [for (s in 0...4) num('border.$s', 0)];
					if (sides.exists("border")) field("borders", VEdges(e[0], e[1], e[2], e[3])) else field("borderWidth", VNum(e[0]));
				case "corner":
					var c = [for (s in 0...4) num('corner.$s', 0)];
					if (sides.exists("corner")) field("corners", VCorners(c[0], c[1], c[2], c[3])) else field("radius", VNum(c[0]));
				case "transition" | "enter":
					// (transition-* with duration-*, ease-*, delay-* (Tailwind's
					// defaults else: 150ms, its ease); duration-* alone: CSS's
					// initial property, all; animate-in: opacity and transform
					// too, eased from the starting state over the same
					// duration (tw-animate-css's 150ms, ease, else))
					done["transition"] = done["enter"] = true;
					var property = switch inherited("transition.property") {
						case VStr(p): p;
						case _: null;
					}
					var easing = switch inherited("transition.easing") {
						case VStr(e): e;
						case _: null;
					}
					var given = inherited("transition.duration") != null;
					var duration = num("transition.duration", DURATION_DEFAULT), delay = num("transition.delay", 0);
					var list = [];
					function add(p:String, ms:Float, e:String)
						list.push('$p ${ms}ms $e' + (delay != 0 ? ' ${delay}ms' : ""));
					if (property == null && given) property = "all";
					if (property != null && property != "none") for (p in property.split(","))
						add(p, duration, easing ?? EASE_DEFAULT);
					if (inherited("enter") != null) for (p in ["opacity", "transform"])
						add(p, given ? duration : DURATION_DEFAULT, easing ?? "ease");
					field("transition", VTransition(list.length == 0 ? "all 0s" : list.join(", ")));
				case "direction":
					if (g.parts.exists("direction")) field("direction", g.parts["direction"]) else if (inherited("direction") == null)
						field("direction", g.parts["direction.default"]);
				case "leading" | "textLeading":
					done["leading"] = done["textLeading"] = true;
					switch inherited("leading") ?? inherited("textLeading") {
						// (leading-6: pixels, over any multiple, as Tailwind's --tw-leading over text-sm's)
						case VDim(Px(px)): field("lineHeightPx", VNum(px));
						case v: field("lineHeight", v);
					}
				case "tracking":
					field("letterSpacingEm", g.parts["tracking"]);
				case "translate" | "rotate" | "scale":
					done["translate"] = done["rotate"] = done["scale"] = true;
					var css = [];
					for (axis in ["x", "y"])
						switch inherited('translate.$axis') {
							case VStr(t): for (p in t.split(" ")) if (p != "0px") css.push('translate${axis.toUpperCase()}($p)');
							case _:
						}
					switch inherited("rotate") {
						case VStr(a) if (a != "0deg"): css.push('rotate($a)');
						case _:
					}
					switch inherited("scale") {
						case VStr(s) if (s != "1"): css.push('scale($s)');
						case _:
					}
					field("transform", VTransform(css.length == 0 ? "none" : css.join(" ")));
				case "gridColumn" | "gridRow":
					var start = 0, end = 0, span = 1;
					switch inherited('$base.start') {
						case VInt(n): start = n;
						case _:
					}
					switch inherited('$base.end') {
						case VInt(n): end = n;
						case _:
					}
					switch inherited('$base.span') {
						case VInt(n): span = n;
						case _:
					}
					field(base, VPlacement(start, end, span));
				case _:
					field(k, g.parts[k]);
			}
		}
		return r;
	}

	// a rule as text, for tests and errors: `button[destructive] hover: background=var(--destructive)/90`
	public static function describe(r:TwRule):String {
		var b = new StringBuf();
		b.add(r.slot);
		if (r.variant != null) b.add('[${r.variant}]');
		if (r.size != null) b.add('(${r.size})');
		if (r.when.length > 0) b.add(" " + r.when.join(" ") + ":");
		for (k in r.fields)
			b.add(' $k=' + value(r.props[k]));
		return b.toString();
	}

	public static function value(v:TwValue):String
		return switch v {
			case VNum(n) | VDim(Px(n)): num(n);
			case VInt(n): '$n';
			case VStr(s) | VColor(s) | VTransform(s) | VTransition(s): s;
			case VBool(b): '$b';
			case VEnum(_, name): name;
			case VDim(Percent(p)): num(p) + "%";
			case VDim(d): '$d';
			case VEdges(t, r, b, l): t == r && r == b && b == l ? num(t) : [t, r, b, l].map(num).join(" ");
			case VCorners(tl, tr, br, bl): tl == tr && tr == br && br == bl ? num(tl) : [tl, tr, br, bl].map(num).join(" ");
			case VShadow(list): list.length == 0 ? "none" : [for (s in list) [s.x, s.y, s.blur, s.spread].map(num).join(" ") + " " + s.color].join(", ");
			case VTracks(list): [for (t in list) t.min == t.max ? '${t.max}' : 'minmax(${t.min}, ${t.max})'].join(" ");
			case VPlacement(start, end, span): '$start/$end span $span';
		}

	// (rounded to 4 places)
	static function num(n:Float):String
		return Math.isNaN(n) ? "auto" : Math.abs(n) >= 1e5 ? "" + n : "" + Math.round(n * 10000) / 10000;
}

// the classes of a slot that share variants: one rule
private class Group {
	public final key:String;
	public final variant:Null<String>;
	public final size:Null<String>;
	public final when:Array<String>;
	// (the variants' orders, the latest first)
	public final order:Array<Int>;
	public final parts = new Map<String, TwValue>();
	public final keys:Array<String> = [];

	public function new(key, variant, size, when, order) {
		this.key = key;
		this.variant = variant;
		this.size = size;
		this.when = when;
		this.order = order;
	}

	// whether this rule holds whenever g does
	public function holdsWith(g:Group):Bool {
		if (variant != null && variant != g.variant || size != null && size != g.size) return false;
		for (w in when)
			if (!g.when.contains(w)) return false;
		return true;
	}
}
