package studio;

import helder.ui.Clock;
import helder.ui.motion.Track;
import helder.view.graph.Graph.*;

// The canvas' view of its world: a point of the world at (wx, wy) is drawn
// at (wx * k + x, wy * k + y) in the stage. It flies to a view on a spring
// (helder.ui.motion's analytic tracks: the same frames at any frame rate)
// (the zoom's scale in log space, so that zooming in and out feel the same),
// or jumps there (a pan, a wheel's zoom, reduced motion). `changed` is
// bumped at each move, for what is drawn from it.
class Camera {
	public var x(default, null) = 0.0;
	public var y(default, null) = 0.0;
	public var k(default, null) = 1.0;
	public final changed = signal(0);

	// (where it flies: the view's x, y and the scale's log, each an analytic track, helder.ui.motion's)
	final fx = new Track(0, 0.05);
	final fy = new Track(0, 0.05);
	final fl = new Track(0, 1e-4);
	var running = false;
	// whether a flight is on (the stage's handlers jump instead)
	public var flying(get, never):Bool;

	inline function get_flying()
		return running;

	public function new() {}

	// at once
	public function jump(nx:Float, ny:Float, nk:Float) {
		x = nx;
		y = ny;
		k = nk;
		fx.set(nx);
		fy.set(ny);
		fl.set(Math.log(nk));
		running = false;
		changed(c -> c + 1);
	}

	// on the spring (Theme's: from where it is, its velocity kept when it is re-aimed)
	public function fly(nx:Float, ny:Float, nk:Float) {
		if (Clock.reducedMotion) {
			jump(nx, ny, nk);
			return;
		}
		var c = Theme.ZOOM;
		fx.animate(-1, nx, c);
		fy.animate(-1, ny, c);
		fl.animate(-1, Math.log(nk), c);
		if (running) return;
		running = true;
		Clock.add(step);
	}

	function step(now:Float):Bool {
		if (!running) return false;
		fx.sample(now);
		fy.sample(now);
		fl.sample(now);
		x = fx.value;
		y = fy.value;
		k = Math.exp(fl.value);
		running = fx.moving() || fy.moving() || fl.moving();
		changed(c -> c + 1);
		return running;
	}

	// moved by dx, dy (stage points)
	public function panBy(dx:Float, dy:Float)
		jump(x + dx, y + dy, k);

	// scaled by f about the stage's point (px, py)
	public function zoomAt(px:Float, py:Float, f:Float) {
		var nk = Math.max(0.05, Math.min(8, k * f));
		var wx = (px - x) / k, wy = (py - y) / k;
		jump(px - wx * nk, py - wy * nk, nk);
	}

	// the view fitting a world rectangle into the stage (w x h) with a margin, less insets right, below and above (stage points)
	public static function fit(rx:Float, ry:Float, rw:Float, rh:Float, sw:Float, sh:Float, pad:Float, right:Float, below:Float, above = 0.0):{x:Float, y:Float, k:Float} {
		var aw = Math.max(40, sw - right - pad * 2), ah = Math.max(40, sh - below - above - pad * 2);
		var k = Math.min(aw / Math.max(1, rw), ah / Math.max(1, rh));
		return {x: (sw - right - rw * k) / 2 - rx * k, y: above + (sh - below - above - rh * k) / 2 - ry * k, k: k};
	}

	// a world point in the stage
	public inline function sx(wx:Float):Float
		return wx * k + x;

	public inline function sy(wy:Float):Float
		return wy * k + y;

	// a stage point in the world
	public inline function wx(px:Float):Float
		return (px - x) / k;

	public inline function wy(py:Float):Float
		return (py - y) / k;

	public function transform():String
		return 'translate(${r(x)}px, ${r(y)}px) scale(${Math.round(k * 100000) / 100000})';

	static inline function r(v:Float):Float
		return Math.round(v * 100) / 100;
}
