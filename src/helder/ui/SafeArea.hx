package helder.ui;

import helder.view.Reactive;
import helder.view.Signal;

// The main window's safe area for markup, as CSS's env(): a literal
// attribute naming env(safe-area-inset-top) (right, bottom, left; a
// fallback after a comma for another name) is bound to it, its value the
// insets in UI pixels, again whenever they change (a rotation, the bars
// hidden): <view padding-top="env(safe-area-inset-top)">,
// padding="calc(env(safe-area-inset-top) + 8px) 16px", margin-bottom="max(12px,
// env(safe-area-inset-bottom))". calc(), max() and min() of pixels fold to
// one length; a percentage in calc() stays for Dim's. The insets are
// UiWindow's first window's (a phone has one: Window.safeTop..., over the
// UI's scale), each frame they changed; Ui.safeArea has each window's own.
// Code reads insets.value (a signal: what reads it in an effect or a
// reactive attribute follows it).
class SafeArea {
	// top, right, bottom, left in UI pixels
	public static final insets:Signal<Edges> = Reactive.signal(Edges.ZERO);

	// (UiWindow) the insets now: the signal set when they changed
	public static function set(top:Float, right:Float, bottom:Float, left:Float) {
		var e = insets.peek();
		if (e.top == top && e.right == right && e.bottom == bottom && e.left == left) return;
		insets.value = new Edges(top, right, bottom, left);
	}

	// (markup: NodeRenderer.setProperty, a literal value naming env()) the
	// attribute set from the value resolved, again when the insets change
	public static function bind(n:Node, set:(n:Node, name:String, v:Dynamic) -> Void, name:String, value:String)
		Reactive.effect(() -> set(n, name, resolve(value, insets.value)));

	// value with each env() replaced by its pixels (of e), then calc(), max()
	// and min() of pixels folded
	public static function resolve(value:String, e:Edges):String {
		var s = replace(value, "env", inner -> {
			var comma = inner.indexOf(",");
			var name = StringTools.trim(comma < 0 ? inner : inner.substr(0, comma));
			return switch name {
				case "safe-area-inset-top": px(e.top);
				case "safe-area-inset-right": px(e.right);
				case "safe-area-inset-bottom": px(e.bottom);
				case "safe-area-inset-left": px(e.left);
				case _: comma < 0 ? "0px" : StringTools.trim(inner.substr(comma + 1));
			}
		});
		// (calc inside max and min, and around them)
		s = calc(s);
		for (f in ["max", "min"])
			s = replace(s, f, inner -> {
				var vs = [for (p in inner.split(",")) pixels(StringTools.trim(p))];
				if (Lambda.exists(vs, Math.isNaN) || vs.length == 0) return '$f($inner)';
				var r = vs[0];
				for (v in vs)
					r = f == "max" ? Math.max(r, v) : Math.min(r, v);
				return px(r);
			});
		return calc(s);
	}

	// calc() of pixels folded (one of a percentage kept)
	static function calc(s:String):String {
		return replace(s, "calc", inner -> {
			if (inner.indexOf("%") >= 0) return 'calc($inner)';
			// (terms of pixels, each after + or -)
			var b = StringTools.replace(inner, " ", ""), sum = 0.0, sign = 1.0, i = 0;
			while (i < b.length) {
				var c = b.charAt(i);
				if (c == "+" || c == "-") {
					if (c == "-") sign = -sign;
					i++;
					continue;
				}
				var j = i;
				while (j < b.length && b.charAt(j) != "+" && (b.charAt(j) != "-" || b.charAt(j - 1) == "e"))
					j++;
				var v = pixels(b.substring(i, j));
				if (Math.isNaN(v)) return 'calc($inner)';
				sum += sign * v;
				sign = 1;
				i = j;
			}
			return px(sum);
		});
	}

	// each f(...) in s (its parentheses balanced) replaced by what the function makes of its inside
	static function replace(s:String, f:String, fn:String->String):String {
		var out = new StringBuf(), at = 0;
		while (true) {
			var k = s.indexOf(f + "(", at);
			// (a name's end, not another's: "max(" in "xmax(" is not max's)
			while (k > 0 && ~/[a-z-]/.match(s.charAt(k - 1)))
				k = s.indexOf(f + "(", k + 1);
			if (k < 0) break;
			var depth = 0, j = k + f.length;
			while (j < s.length) {
				var c = s.charAt(j);
				if (c == "(") depth++ else if (c == ")" && --depth == 0) break;
				j++;
			}
			if (j >= s.length) break;
			out.add(s.substring(at, k));
			out.add(fn(s.substring(k + f.length + 1, j)));
			at = j + 1;
		}
		out.add(s.substr(at));
		return out.toString();
	}

	// "12px" or "12": 12; else NaN
	static function pixels(t:String):Float {
		var n = StringTools.endsWith(t, "px") ? t.substr(0, t.length - 2) : t;
		return ~/^-?[0-9]*\.?[0-9]+(e[-+]?[0-9]+)?$/.match(n) ? Std.parseFloat(n) : Math.NaN;
	}

	static function px(v:Float):String
		return (Math.round(v * 1000) / 1000) + "px";
}
