package helder.ui;

// A scroll glided to rather than jumped to: a mouse wheel's notches where
// the platform glides them (Event.eased: macOS, a browser's page), as a
// scroller's (Scrolling) and a node that scrolls itself (DataGrid, CodeView).
// A notch from rest eases in and out over DURATION, as a browser starts one
// gently; one while gliding goes on from its speed to the new end, slowing,
// so that a quick turn of the wheel flows. It runs on the node's screen's
// clock and starts at its first tick (Clock.now is the last tick's, long
// ago when the window was idle).
//
//   var glide = new ScrollGlide(node, (x, y) -> scrollTo(x, y));
//   onWheel = e -> if (e.eased) glide.to(left, top, glide.heading(left, top, e.deltaX, e.deltaY, maxLeft, maxTop));
class ScrollGlide {
	// how long a notch glides (seconds)
	public static inline var DURATION = 0.2;

	public var gliding(default, null) = false;
	// where it is heading
	public var toX(default, null) = 0.0;
	public var toY(default, null) = 0.0;

	final node:Node;
	final set:(x:Float, y:Float) -> Void;
	var fromX = 0.0;
	var fromY = 0.0;
	var at = -1.0;
	var fromRest = false;

	public function new(node:Node, set:(x:Float, y:Float) -> Void) {
		this.node = node;
		this.set = set;
	}

	// a notch's end: dx, dy on from where it is (x, y) or where it heads, within 0 to max
	public function heading(x:Float, y:Float, dx:Float, dy:Float, maxX:Float, maxY:Float):{x:Float, y:Float} {
		var tx = (gliding ? toX : x) + dx, ty = (gliding ? toY : y) + dy;
		return {x: tx < 0 ? 0 : tx > maxX ? maxX : tx, y: ty < 0 ? 0 : ty > maxY ? maxY : ty};
	}

	// glides from x, y to an end: whether it moves
	public function to(x:Float, y:Float, end:{x:Float, y:Float}):Bool {
		if (!gliding && end.x == x && end.y == y) return false;
		fromX = x;
		fromY = y;
		toX = end.x;
		toY = end.y;
		at = -1;
		fromRest = !gliding;
		if (!gliding) {
			gliding = true;
			Clock.addFor(node, step);
		}
		if (node.ui != null) node.ui.requestFrame();
		return true;
	}

	// stopped where it is (a press, a key, a scroll of another kind)
	public function stop()
		gliding = false;

	function step(t:Float):Bool {
		if (!gliding) return false;
		if (at < 0) at = t;
		var k = Math.min(1, Math.max(0, (t - at) / DURATION)), e = ease(k, fromRest);
		set(fromX + (toX - fromX) * e, fromY + (toY - fromY) * e);
		if (k < 1) return true;
		gliding = false;
		return false;
	}

	// the curve: from rest in and out (cubic), while gliding out (quadratic: from its speed)
	public static inline function ease(k:Float, fromRest:Bool):Float
		return fromRest ? (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2) : 1 - Math.pow(1 - k, 2);
}
