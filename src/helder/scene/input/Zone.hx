package helder.scene.input;

// A part of the window a finger's press is taken in (Binding's Touch and
// TouchDelta, a VirtualStick's or a VirtualButton's): a rectangle in
// fractions of the window's width and height (0 to 1, from the top left),
// or a circle around a point in those fractions, its radius in points (a
// button keeps its size on every screen). Where a press began decides.
class Zone {
	public final x0:Float;
	public final y0:Float;
	public final x1:Float;
	public final y1:Float;
	// a circle's radius in points (< 0: the rectangle)
	public final radius:Float;

	function new(x0:Float, y0:Float, x1:Float, y1:Float, radius:Float) {
		this.x0 = x0;
		this.y0 = y0;
		this.x1 = x1;
		this.y1 = y1;
		this.radius = radius;
	}

	public static function rect(x0:Float, y0:Float, x1:Float, y1:Float):Zone
		return new Zone(x0, y0, x1, y1, -1);

	// a circle around (cx, cy) (fractions), radius points
	public static function circle(cx:Float, cy:Float, radius:Float):Zone
		return new Zone(cx, cy, cx, cy, radius);

	// the whole window
	public static function all():Zone
		return new Zone(0, 0, 1, 1, -1);

	// the same part of the window (Actions: one control for the bindings of equal zones)
	public function equals(o:Zone):Bool
		return o == this || o.x0 == x0 && o.y0 == y0 && o.x1 == x1 && o.y1 == y1 && o.radius == radius;

	// whether x, y (pixels) is in it, in a window width x height pixels of scale pixels a point
	public function contains(x:Float, y:Float, width:Float, height:Float, scale:Float):Bool {
		if (radius < 0) return x >= x0 * width && x <= x1 * width && y >= y0 * height && y <= y1 * height;
		var dx = x - x0 * width, dy = y - y0 * height, r = radius * scale;
		return dx * dx + dy * dy <= r * r;
	}

	// its centre's x, y in pixels
	public inline function centerX(width:Float):Float
		return (x0 + x1) / 2 * width;

	public inline function centerY(height:Float):Float
		return (y0 + y1) / 2 * height;
}
