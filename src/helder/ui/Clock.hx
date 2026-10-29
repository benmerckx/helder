package helder.ui;

// The animation clock: what animates adds a step, called with the time (in
// seconds) at each tick until it returns false. A window ticks it before
// each frame and keeps drawing while anything animates (active); a test
// ticks it by hand.
class Clock {
	// the last tick's time
	public static var now(default, null) = 0.0;
	static final steps:Array<Float->Bool> = [];

	public static function add(step:Float->Bool)
		steps.push(step);

	public static var active(get, never):Bool;

	static inline function get_active()
		return steps.length > 0;

	// runs the steps to their ends (tests, a screenshot): ticks a tenth of a
	// second apart, from now on, until none is left
	public static function finish() {
		var t = now, n = 0;
		while (active && n++ < 100000) {
			t += 0.1;
			tick(t);
		}
	}

	// runs the steps at time t (the ones done are dropped): whether any is left
	public static function tick(t:Float):Bool {
		now = t;
		var i = 0, ran = steps.length > 0;
		while (i < steps.length) {
			if (steps[i](t)) i++ else steps.splice(i, 1);
		}
		// (what the steps wrote lands now, helder.view.graph)
		if (ran) helder.view.graph.Graph.flush();
		return steps.length > 0;
	}
}
