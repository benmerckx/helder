package helder.ui;

@:structInit class Size {
	public static final ZERO:Size = {width: 0, height: 0};

	public final width:Float;
	public final height:Float;

	public inline function new(width:Float, height:Float) {
		this.width = width;
		this.height = height;
	}
}
