package hxmc.ui;

// Edges from one number (all four), [vertical, horizontal], [top, horizontal,
// bottom] or [top, right, bottom, left], as CSS writes them
@:forward
abstract EdgesValue(Edges) from Edges to Edges {
	@:from static inline function ofFloat(v:Float):EdgesValue
		return new Edges(v, v, v, v);

	@:from static inline function ofInt(v:Int):EdgesValue
		return new Edges(v, v, v, v);

	@:from static function ofArray(a:Array<Float>):EdgesValue
		return switch a.length {
			case 1: new Edges(a[0], a[0], a[0], a[0]);
			case 2: new Edges(a[0], a[1], a[0], a[1]);
			case 3: new Edges(a[0], a[1], a[2], a[1]);
			case 4: new Edges(a[0], a[1], a[2], a[3]);
			case _: throw "Edges: 1 to 4 values";
		}
}
