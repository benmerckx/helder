package hxmc.ui.reactive;

// Fine-grained reactivity, as Solid has it: signals hold values, memos
// derive values from them, effects run code that reads them, again
// whenever what they read changes. Reading a signal or memo inside a memo
// or an effect makes it a source of that computation (tracking); writing a
// signal marks its observers: memos as possibly stale, effects to run.
// Effects then run (at once, or at the end of a batch); a memo recomputes
// lazily, when read and one of its sources really changed (Reactively's
// clean/check/dirty states: no glitches, no needless work).
//
// Computations form an ownership tree: those created while another one
// runs belong to it and are disposed (their cleanups run) before it runs
// again or when it is disposed; root() makes a tree's top.
class Reactive {
	// the computation running now: what reads are tracked for
	@:allow(hxmc.ui.reactive) static var current:Null<Computation> = null;
	// the owner new computations and cleanups attach to
	@:allow(hxmc.ui.reactive) static var owner:Null<Owner> = null;
	static var batching = 0;
	static final queue:Array<Computation> = [];
	static var flushing = false;

	public static inline function signal<T>(value:T):Signal<T>
		return new Signal(value);

	public static inline function memo<T>(fn:Void->T):Memo<T>
		return new Memo(fn);

	// runs fn now and whenever what it read changes
	public static function effect(fn:Void->Void):Computation {
		var c = new Computation(fn, true);
		c.update();
		return c;
	}

	// a new ownership tree: fn gets its dispose
	public static function root<T>(fn:(dispose:Void->Void)->T):T {
		var o = new Owner(null);
		var savedOwner = owner, savedCurrent = current;
		owner = o;
		current = null;
		try {
			var r = fn(o.dispose);
			owner = savedOwner;
			current = savedCurrent;
			return r;
		} catch (e:Dynamic) {
			owner = savedOwner;
			current = savedCurrent;
			throw e;
		}
	}

	// fn runs when the current owner is disposed or runs again
	public static function onCleanup(fn:Void->Void)
		if (owner != null) owner.cleanups.push(fn);

	// fn's reads are not tracked
	public static function untrack<T>(fn:Void->T):T {
		var saved = current;
		current = null;
		try {
			var r = fn();
			current = saved;
			return r;
		} catch (e:Dynamic) {
			current = saved;
			throw e;
		}
	}

	// the writes in fn run their effects once, after it
	public static function batch(fn:Void->Void) {
		batching++;
		try {
			fn();
		} catch (e:Dynamic) {
			batching--;
			throw e;
		}
		batching--;
		if (batching == 0) flush();
	}

	@:allow(hxmc.ui.reactive) static function schedule(c:Computation) {
		queue.push(c);
		if (batching == 0) flush();
	}

	static function flush() {
		if (flushing) return;
		flushing = true;
		var i = 0;
		try {
			while (i < queue.length)
				queue[i++].updateIfNecessary();
		} catch (e:Dynamic) {
			queue.resize(0);
			flushing = false;
			throw e;
		}
		queue.resize(0);
		flushing = false;
	}
}

// what owns computations and cleanups
class Owner {
	public final parent:Null<Owner>;
	public final children:Array<Owner> = [];
	public final cleanups:Array<Void->Void> = [];
	var disposed = false;

	public function new(parent:Null<Owner>) {
		this.parent = parent;
		if (parent != null) parent.children.push(this);
	}

	// disposes the children and runs the cleanups (the owner itself stays usable)
	public function clean() {
		for (c in children.copy())
			c.dispose();
		children.resize(0);
		var cs = cleanups.copy();
		cleanups.resize(0);
		for (f in cs)
			f();
	}

	public function dispose() {
		if (disposed) return;
		disposed = true;
		clean();
		if (parent != null) parent.children.remove(this);
		detach();
	}

	function detach() {}

	public var isDisposed(get, never):Bool;

	inline function get_isDisposed()
		return disposed;
}

enum abstract State(Int) to Int {
	var Clean;
	var Check;
	var Dirty;
}

// a memo or an effect: it runs fn, tracking its sources
class Computation extends Owner {
	final fn:Void->Void;
	public final isEffect:Bool;
	@:allow(hxmc.ui.reactive) var state:State = Dirty;
	@:allow(hxmc.ui.reactive) var sources:Array<Source> = [];
	var running = false;

	public function new(fn:Void->Void, isEffect:Bool) {
		super(Reactive.owner);
		this.fn = fn;
		this.isEffect = isEffect;
	}

	@:allow(hxmc.ui.reactive) function update() {
		if (isDisposed) return;
		if (running) throw "hxmc.ui.reactive: a computation depends on itself";
		clean();
		for (s in sources)
			s.observers.remove(this);
		sources = [];
		var savedOwner = Reactive.owner, savedCurrent = Reactive.current;
		Reactive.owner = this;
		Reactive.current = this;
		running = true;
		try {
			fn();
		} catch (e:Dynamic) {
			running = false;
			Reactive.owner = savedOwner;
			Reactive.current = savedCurrent;
			state = Clean;
			throw e;
		}
		running = false;
		Reactive.owner = savedOwner;
		Reactive.current = savedCurrent;
		state = Clean;
	}

	// a source changed (Dirty) or may have (Check)
	@:allow(hxmc.ui.reactive) function stale(s:State) {
		if ((state : Int) >= (s : Int)) return;
		var was = state;
		state = s;
		if (was == Clean) {
			if (isEffect) Reactive.schedule(this);
			markObservers();
		}
	}

	function markObservers() {}

	@:allow(hxmc.ui.reactive) function updateIfNecessary() {
		if (state == Check) {
			for (s in sources.copy()) {
				if (Std.isOfType(s, MemoBase)) (cast s : MemoBase).updateIfNecessary();
				if (state == Dirty) break;
			}
		}
		if (state == Dirty) update();
		state = Clean;
	}

	override function detach() {
		for (s in sources)
			s.observers.remove(this);
		sources = [];
	}
}

// what computations read: signals and memos
interface Source {
	var observers(default, null):Array<Computation>;
}

@:allow(hxmc.ui.reactive)
class SignalBase implements Source {
	public var observers(default, null):Array<Computation> = [];

	function track() {
		var c = Reactive.current;
		if (c != null && !c.sources.contains(this)) {
			c.sources.push(this);
			observers.push(c);
		}
	}

	function notify() {
		for (o in observers.copy())
			o.stale(Dirty);
	}
}

// a value: reading it (value, get()) inside a computation tracks it; writing a different one notifies
class Signal<T> extends SignalBase {
	var v:T;

	public function new(value:T) {
		v = value;
	}

	public var value(get, set):T;

	function get_value():T {
		track();
		return v;
	}

	function set_value(x:T):T {
		if (x == v) return x;
		v = x;
		Reactive.batch(notify);
		return x;
	}

	public inline function get():T
		return value;

	public inline function set(x:T)
		value = x;

	// sets it from its current value (untracked)
	public inline function update(f:T->T)
		value = f(v);

	// the value, not tracked
	public inline function peek():T
		return v;

	// notifies even though the value is the same object (it was changed inside)
	public function changed()
		Reactive.batch(notify);

	public function toString():String
		return 'Signal($v)';
}

@:allow(hxmc.ui.reactive)
class MemoBase extends Computation implements Source {
	public var observers(default, null):Array<Computation> = [];

	override function markObservers() {
		for (o in observers.copy())
			o.stale(Check);
	}
}

// a derived value: recomputed when read and its sources changed; its
// observers are notified only when the result differs
class Memo<T> extends MemoBase {
	var v:T;
	final compute:Void->T;

	public function new(fn:Void->T) {
		var self:Null<Memo<T>> = null;
		super(() -> self.recompute(), false);
		self = this;
		compute = fn;
		update();
	}

	function recompute() {
		var old = v;
		v = compute();
		if (old != v)
			for (o in observers)
				o.state = Dirty;
	}

	public var value(get, never):T;

	function get_value():T {
		if (state != Clean) updateIfNecessary();
		var c = Reactive.current;
		if (c != null && !c.sources.contains(this)) {
			c.sources.push(this);
			observers.push(c);
		}
		return v;
	}

	public inline function get():T
		return value;

	public inline function peek():T {
		if (state != Clean) updateIfNecessary();
		return v;
	}

	public function toString():String
		return 'Memo($v)';
}
