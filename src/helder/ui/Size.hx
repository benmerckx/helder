package helder.ui;

// A width and a height: a value on hxmc's targets (@:hxmc.struct: copied,
// never allocated; measureContent returns one per text measured)
@:structInit @:hxmc.struct final class Size {
	public static final ZERO:Size = {width: 0, height: 0};
	// (no size: contentInk's none)
	public static final NONE:Size = {width: Math.NaN, height: Math.NaN};

	public final width:Float;
	public final height:Float;

	public inline function new(width:Float, height:Float) {
		this.width = width;
		this.height = height;
	}
}
