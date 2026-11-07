package helder.ui;

// The animation clock: what animates adds a step, called with the time (in
// seconds) at each tick until it returns false. A window ticks it before
// each frame and keeps drawing while anything animates (active); a test
// ticks it by hand.
class Clock {
	// the last tick's time
	public static var now(get, never):Float;
	// the system asks for reduced motion (a headless run's --reduced-motion):
	// what moves a node's place, size or shape jumps to its end (Style's
	// transitions of transform and shadow, Motion's transition and spring,
	// helder.ui.motion's travel, sizes, radii and matched flights), fades,
	// presence and colours still ease (motion's over 0.15 s)
	public static var reducedMotion(get, set):Bool;

	// (each of these the current screen's: helder.ui.ScreenContext; a
	// program's own is its main context, a story host's screens have one each)
	static function get_now():Float
		return ScreenContext.current.now;

	static function get_reducedMotion():Bool
		return ScreenContext.current.reducedMotion;

	static function set_reducedMotion(v:Bool):Bool
		return ScreenContext.current.reducedMotion = v;

	public static function add(step:Float->Bool)
		ScreenContext.current.steps.push(step);

	// a step on a screen's clock (a Ui's: Ui.context), whichever is current
	@:noCompletion public static function addTo(context:ScreenContext, step:Float->Bool)
		context.steps.push(step);

	// a step on the clock of the screen n is drawn in (the current one's while it is in none)
	@:noCompletion public static function addFor(n:Node, step:Float->Bool)
		(n.ui == null ? ScreenContext.current : n.ui.context).steps.push(step);

	public static var active(get, never):Bool;

	static inline function get_active()
		return ScreenContext.current.steps.length > 0;

	// f called once the clock reaches seconds from now (its screen's clock:
	// not while the screen is suspended); not an animation, so the window
	// sleeps until then (UiWindow.run). The timer, to cancel it
	@:noCompletion public static function after(seconds:Float, f:Void->Void):ScreenContext.Timer {
		var c = ScreenContext.current;
		var t = @:privateAccess new ScreenContext.Timer(c.now + seconds, f);
		c.timers.push(t);
		return t;
	}

	// (the timers due at t run, in their order)
	static function timers(c:ScreenContext, t:Float) {
		if (c.timers.length == 0) return;
		var due = [for (x in c.timers) if (x.at <= t) x];
		if (due.length == 0) return;
		for (x in due)
			c.timers.remove(x);
		for (x in due)
			if (!@:privateAccess x.cancelled) @:privateAccess x.f();
		helder.view.graph.Graph.flush();
	}

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
		var c = ScreenContext.current, steps = c.steps;
		c.now = t;
		timers(c, t);
		var i = 0, ran = steps.length > 0;
		while (i < steps.length) {
			if (steps[i](t)) i++ else steps.splice(i, 1);
		}
		// (what the steps wrote lands now, helder.view.graph)
		if (ran) helder.view.graph.Graph.flush();
		return steps.length > 0;
	}
}
