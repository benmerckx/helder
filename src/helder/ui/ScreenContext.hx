package helder.ui;

import helder.view.graph.Graph;
import helder.view.graph.Signal;

// What one screen of a program has of its own, instead of the program's
// globals: the animation clock's steps and its timers (Clock), the keymap
// (Keymap.global), the safe area markup reads (SafeArea.insets), dark or
// light, reduced motion, and its settings (helder.os.Store's stores, in
// memory). A program has one, main, which is what those globals have
// always been; a story host (helder.story.Host: the studio's previews)
// makes one a screen, so that fifty screens in one program each animate,
// bind keys, keep settings and wait on timers apart, and a screen
// suspended stops all of it at once. A screen's Ui (its focus, its theme)
// is its own already.
//
// The current one is what the globals read: run(f) makes this one current
// while f runs (its build, its events, its frame), then puts the last one
// back. Nothing in a context points at another, and current is the only
// static: a screen could move to a thread of its own with current made
// the thread's.
//
//   var screen = new ScreenContext("Todo/Empty");
//   screen.run(() -> Render.render(story.build(controls), ui.root));
//   screen.run(() -> Clock.tick(now));    // its animations only
class ScreenContext {
	static var cur:Null<ScreenContext> = null;
	static var first:Null<ScreenContext> = null;

	// the program's own (the globals as they always were)
	public static var main(get, never):ScreenContext;
	// the one the globals read now
	public static var current(get, never):ScreenContext;

	public final name:String;
	// the keymap of the Ui made in it (Keymap.global while it is current)
	public final keymap:helder.ui.actions.Keymap;
	// the safe area its markup reads (SafeArea.insets), in UI pixels
	public final safeArea:Signal<Edges>;
	// an inset title bar's area free of the window's buttons (env(titlebar-area-*); null: not inset)
	public final titlebarArea:Signal<Null<TitlebarArea>>;
	// dark or light: a host gives it to the screen's Ui (Ui.dark)
	public final dark:Signal<Bool>;
	// reduced motion (Clock.reducedMotion while current)
	public var reducedMotion = false;
	// suspended: its clock is not ticked, its timers do not run (a host's screen off screen)
	public var suspended = false;
	#if (target.name == "hxmc")
	// its settings: helder.os.Store.open's stores while it is current (null:
	// the platform's, as the main context's); in memory, kept for the run
	public final stores:Null<Map<String, helder.os.Store>>;
	#end

	// its clock's time (its last tick); Clock's steps and timers
	@:allow(helder.ui.Clock) public var now(default, null) = 0.0;
	@:allow(helder.ui.Clock) final steps:Array<Float->Bool> = [];
	@:allow(helder.ui.Clock) final timers:Array<Timer> = [];
	// (helder.ui.motion's: what moves in it, whether its step is on its clock)
	@:allow(helder.ui.motion.Motions) final motions:Array<helder.ui.motion.Present> = [];
	@:allow(helder.ui.motion.Motions) var motionTicking = false;

	// (isolated: settings of its own, in memory; the main context's are the platform's)
	public function new(name:String, isolated = true, ?keymap:helder.ui.actions.Keymap) {
		this.name = name;
		this.keymap = keymap ?? new helder.ui.actions.Keymap();
		safeArea = Graph.signalOf(Edges.ZERO, {ownedWrite: true});
		titlebarArea = Graph.signalOf((null : Null<TitlebarArea>), {ownedWrite: true});
		dark = Graph.signalOf(true, {ownedWrite: true});
		#if (target.name == "hxmc")
		stores = isolated ? new Map() : null;
		#end
		// (a new screen starts where the program's clock is, with its motion setting)
		if (first != null) {
			now = first.now;
			reducedMotion = first.reducedMotion;
		}
	}

	static function get_main():ScreenContext {
		if (first == null) {
			first = new ScreenContext("main", false, @:privateAccess helder.ui.actions.Keymap.app);
			// (the system's appearance: UiWindow's, followed by the windows)
			first.dark(false);
		}
		return first;
	}

	static inline function get_current():ScreenContext
		return cur ?? main;

	// f with this context current (its result); the one before current again after, also when f throws
	public function run<T>(f:Void->T):T {
		var was = cur;
		enter();
		var r = try f() catch (e:Dynamic) {
			leave(was);
			throw e;
		}
		leave(was);
		return r;
	}

	inline function enter() {
		cur = this;
		#if (target.name == "hxmc")
		helder.os.Store.scope = stores;
		#end
	}

	inline function leave(was:Null<ScreenContext>) {
		cur = was;
		#if (target.name == "hxmc")
		helder.os.Store.scope = was?.stores;
		#end
	}

	// whether anything animates in it (its clock has steps)
	public var animating(get, never):Bool;

	inline function get_animating()
		return steps.length > 0;

	// the time its next timer is due (Clock's time; infinity: none)
	public function nextTimer():Float {
		var t = Math.POSITIVE_INFINITY;
		for (x in timers)
			if (x.at < t) t = x.at;
		return t;
	}
}

// (a timer of a context's clock: Clock.after's)
@:allow(helder.ui.Clock)
class Timer {
	public final at:Float;
	final f:Void->Void;
	var cancelled = false;

	function new(at:Float, f:Void->Void) {
		this.at = at;
		this.f = f;
	}

	public function cancel()
		cancelled = true;
}
