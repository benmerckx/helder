package helder.ui.motion;

// One animated value: its target, and where it is (value) and how fast it
// moves (velocity) as last sampled. Moving, it is the target plus an
// offset that one analytic segment takes to 0 (Rune's tracks, SwiftUI's
// springs): a spring's closed form in each regime (under, critically and
// over damped), a tween's eased fall with the velocity it was given fading
// out, or a decay's exponential one. Each is evaluated at the time asked
// (the Clock's: a headless run's virtual one), not integrated step by step,
// so the same times give the same values at any frame rate. Retargeting
// samples it exactly where it is and starts the next segment there, from
// that position and velocity: nothing jumps. Each segment knows when it is
// settled for good (within eps of its target, and 10 eps a second still),
// after which the track rests at its target. No allocation: sampling only
// writes its fields.
class Track {
	public static inline var REST = 0;
	static inline var UNDER = 1;
	static inline var CRITICAL = 2;
	static inline var OVER = 3;
	static inline var DECAY = 4;
	static inline var TWEEN = 5;
	// (the longest a segment runs before it is settled)
	static inline var MAX_SETTLE = 120.0;

	public var target(default, null) = 0.0;
	public var value(default, null) = 0.0;
	public var velocity(default, null) = 0.0;
	// (the segment: its kind, start, settled time and coefficients)
	public var kind(default, null) = REST;
	var t0 = 0.0;
	public var end(default, null) = 0.0;
	var c0 = 0.0;
	var c1 = 0.0;
	var c2 = 0.0;
	var c3 = 0.0;
	var c4 = 0.0;
	var c5 = 0.0;
	var easing:Null<Array<Float>> = null;
	// settled within this of the target (and 10 times it a second)
	public final eps:Float;

	public function new(value:Float, eps = 0.001) {
		this.eps = eps;
		set(value);
	}

	public inline function moving():Bool
		return kind != REST;

	// at v at once, still
	public function set(v:Float) {
		target = value = v;
		velocity = 0;
		kind = REST;
	}

	// moved by d, its target too, its motion as it was (a parent's edge it rides moved)
	public function shift(d:Float) {
		target += d;
		value += d;
	}

	// where it is at now (value, velocity); settled: at rest on its target
	public function sample(now:Float) {
		if (kind == REST) {
			value = target;
			velocity = 0;
			return;
		}
		// (begun at the first time it is sampled at)
		if (t0 < 0) {
			t0 = now;
			end += now;
		}
		if (now >= end) {
			kind = REST;
			value = target;
			velocity = 0;
			return;
		}
		var tau = now - t0;
		if (tau < 0) tau = 0;
		var o = 0.0, v = 0.0;
		switch kind {
			case UNDER:
				var e = Math.exp(-c4 * tau), s = Math.sin(c5 * tau), c = Math.cos(c5 * tau);
				o = e * (c0 * c + c1 * s);
				v = e * (c2 * c + c3 * s);
			case CRITICAL:
				var e = Math.exp(-c4 * tau);
				o = (c0 + c1 * tau) * e;
				v = (c2 + c3 * tau) * e;
			case OVER:
				var e1 = Math.exp(c2 * tau), e2 = Math.exp(c3 * tau);
				o = c0 * e1 + c1 * e2;
				v = c0 * c2 * e1 + c1 * c3 * e2;
			case DECAY:
				var e = Math.exp(-c1 * tau);
				o = c0 * e;
				v = -c1 * c0 * e;
			case TWEEN:
				// (c0: the offset, c1: the duration, c2: its inverse, c3: the velocity carried in)
				var u = tau * c2;
				if (u > 1) u = 1;
				var y = bezier(easing, u);
				var w = 1 - u;
				o = c0 * (1 - y) + c3 * tau * w * w;
				v = -c0 * slope * c2 + c3 * w * (1 - 3 * u);
			case _:
		}
		value = target + o;
		velocity = v;
	}

	// to target from where it is at now (sampled exactly), with its velocity,
	// along curve (instant or null: there at once); the same target again: as it
	// goes. now below 0: from where it was last sampled, beginning when it is next
	// sampled (a change between frames moves from the next frame on)
	public function animate(now:Float, to:Float, curve:Null<Curve>, ?withVelocity:Float) {
		if (now >= 0 || kind == REST) sample(now < 0 ? Clock.now : now);
		if (withVelocity != null) velocity = withVelocity;
		if (to == target && withVelocity == null && kind != REST) return;
		target = to;
		start(curve, now, value - to, velocity);
	}

	// a fling let go at now with velocity v: it decays at rate (1/s) to where that takes it, its target
	public function release(now:Float, v:Float, rate = 2.0) {
		sample(now);
		var x = value;
		target = x + v / rate;
		start(Curve.decay(rate), now, x - target, v);
	}

	// (a segment from offset (where it is less its target) and velocity v0; now below 0: begun when next sampled)
	function start(curve:Null<Curve>, now:Float, offset:Float, v0:Float) {
		t0 = now;
		var at = now < 0 ? 0.0 : now;
		kind = REST;
		if (curve == null || curve.kind == Curve.INSTANT_KIND || (offset == 0 && v0 == 0)) {
			value = target;
			velocity = 0;
			return;
		}
		var a = offset;
		switch curve.kind {
			case Curve.SPRING_KIND:
				var omega = curve.omega(), zeta = curve.zeta();
				if (Math.abs(zeta - 1) < 1e-4) {
					kind = CRITICAL;
					var b = v0 + omega * a;
					c0 = a;
					c1 = b;
					c2 = b - omega * a;
					c3 = -omega * b;
					c4 = omega;
				} else if (zeta < 1) {
					kind = UNDER;
					var sigma = zeta * omega, wd = omega * Math.sqrt(1 - zeta * zeta);
					var b = (v0 + sigma * a) / wd;
					c0 = a;
					c1 = b;
					c2 = b * wd - sigma * a;
					c3 = -a * wd - sigma * b;
					c4 = sigma;
					c5 = wd;
				} else {
					kind = OVER;
					var root = Math.sqrt(zeta * zeta - 1);
					var r1 = -omega * (zeta - root), r2 = -omega * (zeta + root);
					var k1 = (v0 - r2 * a) / (r1 - r2);
					c0 = k1;
					c1 = a - k1;
					c2 = r1;
					c3 = r2;
				}
				end = at + settleAfter();
			case Curve.TWEEN_KIND:
				kind = TWEEN;
				easing = curve.easing;
				c0 = a;
				c1 = curve.duration;
				c2 = 1 / curve.duration;
				c3 = v0;
				end = at + curve.duration;
			case Curve.DECAY_KIND:
				kind = DECAY;
				var k = curve.rate;
				// (the target is where the velocity takes it: the offset is -v0 / k)
				c0 = -v0 / k;
				c1 = k;
				var tp = Math.log(Math.abs(c0) / eps), tv = Math.log(Math.abs(v0) / (10 * eps));
				end = at + clamp(Math.max(tp, tv) / k);
			case _:
		}
	}

	static inline function clamp(t:Float):Float
		return !(t > 0) ? 0 : t > MAX_SETTLE ? MAX_SETTLE : t;

	// (seconds from the start until the offset stays within eps and the velocity within 10 eps: the envelopes, else bisection)
	function settleAfter():Float {
		var ep = eps, ev = 10 * eps;
		switch kind {
			case UNDER:
				var tp = Math.log(Math.sqrt(c0 * c0 + c1 * c1) / ep), tv = Math.log(Math.sqrt(c2 * c2 + c3 * c3) / ev);
				return clamp(Math.max(tp, tv) / c4);
			case CRITICAL:
				// (each of offset and velocity (a + b t) e^-ωt, within (|a| + |b| t) e^-ωt: its time to eps by a
				// fixed point, t = ln((|a| + |b| t) / eps) / ω, from below; no allocation)
				return clamp(Math.max(critical(c0, c1, ep), critical(c2, c3, ev)));
			case OVER:
				// (within (|c1| + |c2|) e^(r1 t), r1 the slower root; |r1 c1| + |r2 c2| times e^(r1 t) for the velocity)
				var tp = Math.log((Math.abs(c0) + Math.abs(c1)) / ep) / -c2, tv = Math.log((Math.abs(c0 * c2) + Math.abs(c1 * c3)) / ev) / -c2;
				return clamp(Math.max(tp, tv));
			case _:
				return 0;
		}
	}

	// (when (|a| + |b| t) e^-ωt falls to eps for good, ω the segment's)
	function critical(a:Float, b:Float, eps:Float):Float {
		var aa = Math.abs(a), bb = Math.abs(b), t = 1 / c4;
		if (aa + bb == 0) return 0;
		// (past 1/ω the bound only falls: from there up to its fixed point)
		for (_ in 0...100) {
			var next = Math.log((aa + bb * t) / eps) / c4;
			if (next <= t + 1e-7) break;
			t = next;
		}
		return t;
	}

	// (the easing's slope at the last bezier's point: dy/dx)
	static var slope = 0.0;

	// a cubic Bézier's y where its x is u (0 to 1), its slope dy/dx left in slope
	public static function bezier(e:Null<Array<Float>>, u:Float):Float {
		if (e == null) {
			slope = 1;
			return u;
		}
		var x1 = e[0], y1 = e[1], x2 = e[2], y2 = e[3];
		inline function bz(t:Float, a:Float, b:Float):Float
			return 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t;
		inline function dbz(t:Float, a:Float, b:Float):Float
			return 3 * (1 - t) * (1 - t) * a + 6 * (1 - t) * t * (b - a) + 3 * t * t * (1 - b);
		if (u <= 0) {
			var dx = dbz(0, x1, x2);
			slope = dx > 1e-9 ? dbz(0, y1, y2) / dx : 0;
			return 0;
		}
		if (u >= 1) {
			var dx = dbz(1, x1, x2);
			slope = dx > 1e-9 ? dbz(1, y1, y2) / dx : 0;
			return 1;
		}
		// (t for x = u: Newton's steps, then bisection)
		var t = u;
		var found = false;
		for (_ in 0...8) {
			var x = bz(t, x1, x2) - u;
			if (Math.abs(x) < 1e-7) {
				found = true;
				break;
			}
			var d = dbz(t, x1, x2);
			if (Math.abs(d) < 1e-6) break;
			t -= x / d;
			if (t < 0 || t > 1) break;
		}
		if (!found) {
			var lo = 0.0, hi = 1.0;
			t = u;
			for (_ in 0...40) {
				var x = bz(t, x1, x2);
				if (Math.abs(x - u) < 1e-7) break;
				if (x < u) lo = t else hi = t;
				t = (lo + hi) / 2;
			}
		}
		var dx = dbz(t, x1, x2);
		slope = dx > 1e-9 ? dbz(t, y1, y2) / dx : 0;
		return bz(t, y1, y2);
	}
}
