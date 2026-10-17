package hxmc.ui;

// A length in a style: auto (the content's, or the algorithm's), pixels, or
// a percentage of the containing box's size on the same axis (its content
// box: an unknown one makes the length auto). Ints and Floats convert to
// pixels (`style.width = 120`), strings as CSS writes them ("auto", "50%",
// "12px", "calc(100% - 2px)": a percentage and pixels, added or taken away),
// or the cases (import hxmc.ui.DimValue: Percent(50)).
@:forward
abstract Dim(DimValue) from DimValue to DimValue {
	@:from static inline function ofInt(v:Int):Dim
		return DimValue.Px(v);

	@:from static inline function ofFloat(v:Float):Dim
		return DimValue.Px(v);

	@:from public static function parse(s:String):Dim {
		s = StringTools.trim(s);
		if (s == "auto") return DimValue.Auto;
		if (s == "min-content") return DimValue.MinContent;
		if (s == "max-content") return DimValue.MaxContent;
		if (s == "fit-content") return DimValue.FitContent;
		if (StringTools.startsWith(s, "calc(") && StringTools.endsWith(s, ")")) return calc(s.substring(5, s.length - 1));
		if (StringTools.endsWith(s, "%")) return DimValue.Percent(Std.parseFloat(s.substr(0, s.length - 1)));
		var v = Std.parseFloat(StringTools.endsWith(s, "px") ? s.substr(0, s.length - 2) : s);
		if (Math.isNaN(v)) throw "Dim: not a length: " + s;
		return DimValue.Px(v);
	}

	// (calc's body: terms of a percentage or pixels, each after + or -)
	static function calc(body:String):Dim {
		var p = 0.0, px = 0.0, i = 0, sign = 1.0, any = false;
		var b = StringTools.replace(body, " ", "");
		while (i < b.length) {
			var c = b.charAt(i);
			if (c == "+" || c == "-") {
				if (c == "-") sign = -sign;
				i++;
				continue;
			}
			var j = i;
			while (j < b.length && (j == i || (b.charAt(j) != "+" && b.charAt(j) != "-") || b.charAt(j - 1) == "e")) j++;
			var t = b.substring(i, j), pct = StringTools.endsWith(t, "%");
			var num = pct ? t.substr(0, t.length - 1) : StringTools.endsWith(t, "px") ? t.substr(0, t.length - 2) : t;
			if (!~/^([0-9]+\.?[0-9]*|\.[0-9]+)(e[-+]?[0-9]+)?$/.match(num)) throw "Dim: not a length in calc(" + body + "): " + t;
			if (pct) p += sign * Std.parseFloat(num) else px += sign * Std.parseFloat(num);
			any = true;
			sign = 1;
			i = j;
		}
		if (!any) throw "Dim: an empty calc()";
		return p == 0 ? DimValue.Px(px) : DimValue.Calc(p, px);
	}

	// the pixels of this length against a containing size (NaN: unknown);
	// NaN for auto, an intrinsic size, or a percentage of an unknown size
	public inline function resolve(base:Float):Float
		return switch this {
			case Px(v): v;
			case Percent(p): base * p / 100;
			case Calc(p, px): base * p / 100 + px;
			case _: Math.NaN;
		}

	// whether it is an intrinsic size (MinContent, MaxContent, FitContent)
	public inline function intrinsic():Bool
		return switch this {
			case MinContent | MaxContent | FitContent: true;
			case _: false;
		}
}
