package hxmc.ui.reactive;

import hxmc.ui.Clock;
import hxmc.ui.Color;
import hxmc.ui.reactive.Reactive.*;

// Values that move toward a target as the Clock ticks: a transition eases
// over a duration from where it is to the target's new value, a spring
// follows it with a stiffness and damping (its speed carried through
// changes). Each is a signal to bind (width={transition(() -> open.value ?
// 200 : 0)}); it stops with its owner. color transitions a colour (a
// "#rrggbbaa" string, as markup takes it).
class Motion {
	// eases (ease: ease-out cubic by default) from 0 to 1
	public static function easeOut(k:Float):Float {
		var u = 1 - k;
		return 1 - u * u * u;
	}

	public static function linear(k:Float):Float
		return k;

	public static function easeInOut(k:Float):Float
		return k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;

	public static function transition(target:Void->Float, duration = 0.15, ?ease:Float->Float):Signal<Float> {
		if (ease == null) ease = easeOut;
		var out = new Signal(untrack(target));
		var from = 0.0, to = out.peek(), start = -1.0, running = false, stopped = false;
		effect(() -> {
			var t = target();
			untrack(() -> {
				if (t == to) return;
				from = out.peek();
				to = t;
				// (the start is the next tick's time: the clock may have been idle)
				start = -1;
				if (duration <= 0) {
					out.value = to;
					return;
				}
				if (running) return;
				running = true;
				Clock.add(now -> {
					if (stopped) return running = false;
					if (start < 0) start = now;
					var k = (now - start) / duration;
					if (k >= 1) {
						out.value = to;
						return running = false;
					}
					out.value = from + (to - from) * ease(k);
					return true;
				});
			});
		});
		onCleanup(() -> stopped = true);
		return out;
	}

	// a damped spring toward the target (stiffness and damping per unit mass)
	public static function spring(target:Void->Float, stiffness = 170.0, damping = 26.0):Signal<Float> {
		var out = new Signal(untrack(target));
		var to = out.peek(), x = to, v = 0.0, last = -1.0, running = false, stopped = false;
		effect(() -> {
			var t = target();
			untrack(() -> {
				if (t == to && !running) return;
				to = t;
				if (running) return;
				running = true;
				last = -1;
				Clock.add(now -> {
					if (stopped) return running = false;
					if (last < 0) last = now;
					var dt = now - last;
					last = now;
					if (dt > 0.1) dt = 0.1;
					// (semi-implicit Euler in steps of at most 4 ms)
					var n = Math.ceil(dt / 0.004);
					for (_ in 0...n) {
						var h = dt / n;
						v += (-stiffness * (x - to) - damping * v) * h;
						x += v * h;
					}
					if (Math.abs(x - to) < 1e-3 && Math.abs(v) < 1e-3) {
						x = to;
						v = 0;
						out.value = to;
						return running = false;
					}
					out.value = x;
					return true;
				});
			});
		});
		onCleanup(() -> stopped = true);
		return out;
	}

	// a colour transition: the target as markup writes colours ("#3b82f6", or a Color)
	public static function color(target:Void->Dynamic, duration = 0.15, ?ease:Float->Float):Signal<String> {
		if (ease == null) ease = easeOut;
		inline function parse(v:Dynamic):Color
			return Std.isOfType(v, String) ? Color.parse(v) : (v : Int);
		var cur:Color = parse(untrack(target));
		var out = new Signal(cur.toHex());
		var from = cur, to = cur, start = -1.0, running = false, stopped = false;
		effect(() -> {
			var c = parse(target());
			untrack(() -> {
				if (c == to) return;
				from = cur;
				to = c;
				start = -1;
				if (duration <= 0) {
					cur = to;
					out.value = to.toHex();
					return;
				}
				if (running) return;
				running = true;
				Clock.add(now -> {
					if (stopped) return running = false;
					if (start < 0) start = now;
					var k = (now - start) / duration;
					if (k >= 1) {
						cur = to;
						out.value = to.toHex();
						return running = false;
					}
					cur = Color.mix(from, to, ease(k));
					out.value = cur.toHex();
					return true;
				});
			});
		});
		onCleanup(() -> stopped = true);
		return out;
	}
}
