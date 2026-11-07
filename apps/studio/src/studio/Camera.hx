package studio;

import helder.ui.Clock;
import helder.view.graph.Graph.*;

// The canvas' view of its world: a point of the world at (wx, wy) is drawn
// at (wx * k + x, wy * k + y) in the stage. It flies to a view on a spring
// (the zoom's scale in log space, so that zooming in and out feel the same),
// or jumps there (a pan, a wheel's zoom, reduced motion). `changed` is
// bumped at each move, for what is drawn from it.
class Camera {
	public var x(default, null) = 0.0;
	public var y(default, null) = 0.0;
	public var k(default, null) = 1.0;
	public final changed = signal(0);

	var tx = 0.0;
	var ty = 0.0;
	var tl = 0.0;
	var vx = 0.0;
	var vy = 0.0;
	var vl = 0.0;
	var lk = 0.0;
	var running = false;
	var last = -1.0;
	// whether a flight is on (the stage's handlers jump instead)
	public var flying(get, never):Bool;

	inline function get_flying()
		return running;

	public function new() {}

	// at once
	public function jump(nx:Float, ny:Float, nk:Float) {
		x = tx = nx;
		y = ty = ny;
		k = nk;
		lk = tl = Math.log(nk);
		vx = vy = vl = 0;
		running = false;
		changed(c -> c + 1);
	}

	// on the spring (Theme's stiffness and damping)
	public function fly(nx:Float, ny:Float, nk:Float) {
		if (Clock.reducedMotion) {
			jump(nx, ny, nk);
			return;
		}
		tx = nx;
		ty = ny;
		tl = Math.log(nk);
		if (running) return;
		running = true;
		last = -1;
		Clock.add(step);
	}

	function step(now:Float):Bool {
		if (!running) return false;
		if (last < 0) last = now;
		var dt = Math.min(0.1, now - last);
		last = now;
		var n = Math.ceil(dt / 0.004), s = Theme.SPRING_STIFFNESS, d = Theme.SPRING_DAMPING;
		// (the view's centre springs in screen space: x and y at the target's scale)
		for (_ in 0...n) {
			var h = dt / n;
			vx += (-s * (x - tx) - d * vx) * h;
			vy += (-s * (y - ty) - d * vy) * h;
			vl += (-s * (lk - tl) - d * vl) * h;
			x += vx * h;
			y += vy * h;
			lk += vl * h;
		}
		k = Math.exp(lk);
		var done = Math.abs(x - tx) < 0.05 && Math.abs(y - ty) < 0.05 && Math.abs(lk - tl) < 1e-4 && Math.abs(vx) + Math.abs(vy) < 0.5 && Math.abs(vl) < 1e-3;
		if (done) {
			x = tx;
			y = ty;
			lk = tl;
			k = Math.exp(tl);
			running = false;
		}
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

	// the view fitting a world rectangle into the stage (w x h) with a margin, less insets right and below
	public static function fit(rx:Float, ry:Float, rw:Float, rh:Float, sw:Float, sh:Float, pad:Float, right:Float, below:Float):{x:Float, y:Float, k:Float} {
		var aw = Math.max(40, sw - right - pad * 2), ah = Math.max(40, sh - below - pad * 2);
		var k = Math.min(aw / Math.max(1, rw), ah / Math.max(1, rh));
		return {x: (sw - right - rw * k) / 2 - rx * k, y: (sh - below - rh * k) / 2 - ry * k, k: k};
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
