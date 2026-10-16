package hxmc.ui;

// Four lengths in pixels: padding, margin (EdgesValue converts to them).
@:structInit class Edges {
	public var top:Float;
	public var right:Float;
	public var bottom:Float;
	public var left:Float;

	public static final ZERO:Edges = {top: 0, right: 0, bottom: 0, left: 0};

	public inline function new(top:Float, right:Float, bottom:Float, left:Float) {
		this.top = top;
		this.right = right;
		this.bottom = bottom;
		this.left = left;
	}

	public var horizontal(get, never):Float;
	public var vertical(get, never):Float;

	inline function get_horizontal()
		return left + right;

	inline function get_vertical()
		return top + bottom;
}
