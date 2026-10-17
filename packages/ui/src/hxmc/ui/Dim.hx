package hxmc.ui;

// A length in a style: auto (the content's, or the algorithm's), pixels, or
// a percentage of the containing box's size on the same axis (its content
// box: an unknown one makes the length auto). Ints and Floats convert to
// pixels (`style.width = 120`), strings as CSS writes them ("auto", "50%",
// "12px"), or the cases (import hxmc.ui.DimValue: Percent(50)).
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
		if (StringTools.endsWith(s, "%")) return DimValue.Percent(Std.parseFloat(s.substr(0, s.length - 1)));
		var v = Std.parseFloat(StringTools.endsWith(s, "px") ? s.substr(0, s.length - 2) : s);
		if (Math.isNaN(v)) throw "Dim: not a length: " + s;
		return DimValue.Px(v);
	}

	// the pixels of this length against a containing size (NaN: unknown);
	// NaN for auto, an intrinsic size, or a percentage of an unknown size
	public inline function resolve(base:Float):Float
		return switch this {
			case Px(v): v;
			case Percent(p): base * p / 100;
			case _: Math.NaN;
		}

	// whether it is an intrinsic size (MinContent, MaxContent, FitContent)
	public inline function intrinsic():Bool
		return switch this {
			case MinContent | MaxContent | FitContent: true;
			case _: false;
		}
}
