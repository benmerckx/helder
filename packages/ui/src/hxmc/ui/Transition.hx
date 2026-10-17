package hxmc.ui;

// A CSS transition (Style.transition): the properties that ease to a new
// value rather than jump to it, over a duration (seconds) after a delay,
// along a timing function (a cubic Bézier, CSS's: ease by default; linear,
// ease-in, ease-out, ease-in-out, cubic-bezier(x1, y1, x2, y2)). parse takes
// CSS's shorthand, one transition or several (a comma between):
// "background-color 150ms ease-in-out, opacity 0.2s"; "all" (or none
// named) is every property that eases. The properties that ease: colours
// (background, color, border, outline, text decoration), opacity,
// transform (function by function where both lists have the same ones,
// else none against each one's identity), box-shadow (shadow by shadow);
// others jump. A node's first style does not ease, as CSS's does not.
class Transition {
	// the Style properties that ease (as Style names them)
	public static final EASED = ["background", "color", "borderColor", "outlineColor", "textDecorationColor", "opacity", "transform", "shadow", "ringColor", "ringWidth"];

	// the properties (Style's names; "all": every one that eases), each with its own timing (several: CSS's lists)
	public final properties:Array<String>;
	public final durations:Array<Float>;
	public final delays:Array<Float>;
	public final easings:Array<Array<Float>>;

	public function new(properties:Array<String>, durations:Array<Float>, ?delays:Array<Float>, ?easings:Array<Array<Float>>) {
		this.properties = properties;
		this.durations = durations;
		this.delays = delays ?? [for (_ in properties) 0.0];
		this.easings = easings ?? [for (_ in properties) EASE];
	}

	// CSS's timing functions as cubic Béziers
	public static final EASE = [0.25, 0.1, 0.25, 1.0];
	public static final LINEAR = [0.0, 0.0, 1.0, 1.0];
	public static final EASE_IN = [0.42, 0.0, 1.0, 1.0];
	public static final EASE_OUT = [0.0, 0.0, 0.58, 1.0];
	public static final EASE_IN_OUT = [0.42, 0.0, 0.58, 1.0];

	// the timing of property (a Style name), null when it does not ease: its duration, delay, easing
	public function timing(property:String):Null<{duration:Float, delay:Float, easing:Array<Float>}> {
		var k = properties.lastIndexOf(property);
		// (a ring is a box-shadow to CSS)
		if (k < 0 && (property == "ringColor" || property == "ringWidth")) k = properties.lastIndexOf("shadow");
		if (k < 0) k = properties.lastIndexOf("all");
		if (k < 0 || EASED.indexOf(property) < 0) return null;
		var d = durations[k % durations.length];
		if (d <= 0) return null;
		return {duration: d, delay: delays[k % delays.length], easing: easings[k % easings.length]};
	}

	// CSS's shorthand ("none": null)
	public static function parse(css:String):Null<Transition> {
		var s = StringTools.trim(css);
		if (s == "" || s == "none") return null;
		var properties = [], durations = [], delays = [], easings = [];
		for (part in splitTop(s)) {
			var property = "all", times = [], easing = EASE;
			for (w in words(part)) {
				var t = time(w);
				if (t != null) times.push(t) else {
					var e = easingOf(w);
					if (e != null) easing = e else property = w;
				}
			}
			properties.push(styleName(property));
			durations.push(times.length > 0 ? times[0] : 0);
			delays.push(times.length > 1 ? times[1] : 0);
			easings.push(easing);
		}
		return new Transition(properties, durations, delays, easings);
	}

	// a CSS property's Style name (a Style name as it is)
	static function styleName(css:String):String
		return switch css.toLowerCase() {
			case "background-color" | "background": "background";
			case "border-color": "borderColor";
			case "outline-color": "outlineColor";
			case "text-decoration-color": "textDecorationColor";
			case "box-shadow": "shadow";
			case "translate" | "scale" | "rotate": "transform";
			case _ if (css.indexOf("-") > 0): [for (i => w in css.split("-")) i == 0 ? w : w.charAt(0).toUpperCase() + w.substr(1)].join("");
			case _: css;
		}

	// (a time: "150ms", "0.2s"; null: not one)
	static function time(w:String):Null<Float> {
		var ms = StringTools.endsWith(w, "ms"), sec = !ms && StringTools.endsWith(w, "s");
		if (!ms && !sec) return null;
		var v = Std.parseFloat(w.substr(0, w.length - (ms ? 2 : 1)));
		return Math.isNaN(v) ? null : ms ? v / 1000 : v;
	}

	// a timing function's Bézier (null: not one)
	public static function easingOf(w:String):Null<Array<Float>> {
		var l = StringTools.trim(w).toLowerCase();
		return switch l {
			case "ease": EASE;
			case "linear": LINEAR;
			case "ease-in": EASE_IN;
			case "ease-out": EASE_OUT;
			case "ease-in-out": EASE_IN_OUT;
			case _ if (StringTools.startsWith(l, "cubic-bezier(") && StringTools.endsWith(l, ")")):
				var vs = l.substring(13, l.length - 1).split(",").map(x -> Std.parseFloat(StringTools.trim(x)));
				vs.length == 4 && !Lambda.exists(vs, Math.isNaN) ? vs : null;
			case _: null;
		}
	}

	// (the parts between commas outside parentheses)
	static function splitTop(s:String):Array<String> {
		var out = [], depth = 0, start = 0;
		for (i in 0...s.length) {
			var c = s.charCodeAt(i);
			if (c == "(".code) depth++ else if (c == ")".code) depth-- else if (c == ",".code && depth == 0) {
				out.push(s.substring(start, i));
				start = i + 1;
			}
		}
		out.push(s.substr(start));
		return out;
	}

	// (the words of a part, a function with its parentheses one word)
	static function words(s:String):Array<String> {
		var out = [], depth = 0, cur = new StringBuf(), any = false;
		for (i in 0...s.length) {
			var c = s.charCodeAt(i);
			if (c == "(".code) depth++ else if (c == ")".code) depth--;
			if ((c == " ".code || c == "\t".code) && depth == 0) {
				if (any) out.push(cur.toString());
				cur = new StringBuf();
				any = false;
			} else {
				cur.addChar(c);
				any = true;
			}
		}
		if (any) out.push(cur.toString());
		return out;
	}

	// the easing's progress at k (0 to 1): the Bézier's y where its x is k
	public static function ease(easing:Array<Float>, k:Float):Float {
		if (k <= 0) return 0;
		if (k >= 1) return 1;
		var x1 = easing[0], y1 = easing[1], x2 = easing[2], y2 = easing[3];
		inline function bez(t:Float, a:Float, b:Float):Float
			return 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t;
		// (t for x = k: Newton's steps, then bisection where they stall)
		var t = k;
		for (_ in 0...8) {
			var x = bez(t, x1, x2) - k;
			if (Math.abs(x) < 1e-6) return bez(t, y1, y2);
			var d = 3 * (1 - t) * (1 - t) * x1 + 6 * (1 - t) * t * (x2 - x1) + 3 * t * t * (1 - x2);
			if (Math.abs(d) < 1e-6) break;
			t -= x / d;
		}
		var lo = 0.0, hi = 1.0;
		t = k;
		for (_ in 0...40) {
			var x = bez(t, x1, x2);
			if (Math.abs(x - k) < 1e-7) break;
			if (x < k) lo = t else hi = t;
			t = (lo + hi) / 2;
		}
		return bez(t, y1, y2);
	}

	// a value of property between from and to (k: 0 to 1, eased)
	public static function between(property:String, from:Dynamic, to:Dynamic, k:Float):Dynamic
		return switch property {
			case "opacity" | "ringWidth": (from : Float) + ((to : Float) - (from : Float)) * k;
			case "transform": Transform.between(from, to, k);
			case "shadow": Shadow.between(from, to, k);
			case _: Color.between(from, to, k);
		}
}
