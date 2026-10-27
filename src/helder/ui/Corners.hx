package helder.ui;

// Four corner radii in pixels (Style.corners): top left, top right, bottom
// right, bottom left (CornersValue converts to them)
@:structInit class Corners {
	public var topLeft:Float;
	public var topRight:Float;
	public var bottomRight:Float;
	public var bottomLeft:Float;

	public inline function new(topLeft:Float, topRight:Float, bottomRight:Float, bottomLeft:Float) {
		this.topLeft = topLeft;
		this.topRight = topRight;
		this.bottomRight = bottomRight;
		this.bottomLeft = bottomLeft;
	}

	public static inline function all(r:Float):Corners
		return new Corners(r, r, r, r);

	// each grown (shrunk) by d, not below 0
	public function grow(d:Float):Corners
		return new Corners(Math.max(0, topLeft + d), Math.max(0, topRight + d), Math.max(0, bottomRight + d), Math.max(0, bottomLeft + d));

	public function uniform():Bool
		return topLeft == topRight && topRight == bottomRight && bottomRight == bottomLeft;
}
