package helder.ui;

// Corners from one number (all four), [top left and bottom right, top
// right and bottom left], [top left, top right and bottom left, bottom
// right] or [top left, top right, bottom right, bottom left], as CSS's
// border-radius writes them, or such a string ("8 8 0 0", "6px 2px")
@:forward
abstract CornersValue(Corners) from Corners to Corners {
	@:from static inline function ofFloat(v:Float):CornersValue
		return Corners.all(v);

	@:from static inline function ofInt(v:Int):CornersValue
		return Corners.all(v);

	@:from static function ofArray(a:Array<Float>):CornersValue
		return switch a.length {
			case 1: Corners.all(a[0]);
			case 2: new Corners(a[0], a[1], a[0], a[1]);
			case 3: new Corners(a[0], a[1], a[2], a[1]);
			case 4: new Corners(a[0], a[1], a[2], a[3]);
			case _: throw "Corners: 1 to 4 values";
		}

	@:from public static function parse(s:String):CornersValue
		return ofArray([for (p in StringTools.trim(s).split(" ")) if (p != "") Std.parseFloat(StringTools.replace(p, "px", ""))]);
}
