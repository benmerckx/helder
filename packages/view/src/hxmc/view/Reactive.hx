package hxmc.view;

import hxmc.view.Memo;
import hxmc.view.Signal;

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
	@:allow(hxmc.view) static var current:Null<Computation> = null;
	// the owner new computations and cleanups attach to
	@:allow(hxmc.view) static var owner:Null<Owner> = null;
	static var batching = 0;
	// Render inserting nodes: onMount waits for the outermost insertion's end
	static var mounting = 0;
	static final mounts:Array<{fn:Void->Void, owner:Null<Owner>}> = [];
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

	// the owner of the code running now (null: none)
	public static inline function getOwner():Null<Owner>
		return owner;

	// runs fn (untracked) with o as the owner of what it creates
	public static function runWithOwner<T>(o:Null<Owner>, fn:Void->T):T {
		var savedOwner = owner, savedCurrent = current;
		owner = o;
		current = null;
		try {
			var r = fn();
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

	// a context with its default value (Context)
	public static inline function context<T>(defaultValue:T):Context<T>
		return new Context(defaultValue);

	// runs fn with c set to value for everything created inside it
	public static function provide<T, R>(c:Context<T>, value:T, fn:Void->R):R {
		var o = new Owner(owner);
		if (o.contexts == null) o.contexts = new Map();
		o.contexts.set(c.id, value);
		var saved = owner;
		owner = o;
		try {
			var r = fn();
			owner = saved;
			return r;
		} catch (e:Dynamic) {
			owner = saved;
			throw e;
		}
	}

	// sets c to value in the current owner (a component's: what it renders sees it)
	public static function setContext<T>(c:Context<T>, value:T) {
		if (owner == null) throw "hxmc.view: setContext outside an owner (a root, a component)";
		if (owner.contexts == null) owner.contexts = new Map();
		owner.contexts.set(c.id, value);
	}

	// the nearest value of c above the code running (else its default)
	public static function use<T>(c:Context<T>):T {
		if (owner == null) return c.defaultValue;
		var l = owner.lookup(c.id);
		return l.found ? l.value : c.defaultValue;
	}

	// fn runs (untracked) once the nodes being rendered are in the tree: at
	// the end of the outermost Render insertion, or now outside one
	public static function onMount(fn:Void->Void) {
		if (mounting > 0) mounts.push({fn: fn, owner: owner}) else untrack(fn);
	}

	// Render's insertions: onMount's functions run after the outermost
	@:allow(hxmc.view) static function mount(fn:Void->Void) {
		mounting++;
		try fn() catch (e:Dynamic) {
			mounting--;
			if (mounting == 0) mounts.resize(0);
			throw e;
		}
		mounting--;
		if (mounting == 0 && mounts.length > 0) {
			var ms = mounts.copy();
			mounts.resize(0);
			for (m in ms)
				if (m.owner == null || !m.owner.isDisposed) {
					var saved = owner;
					owner = m.owner;
					try untrack(m.fn) catch (e:Dynamic) {
						owner = saved;
						throw e;
					}
					owner = saved;
				}
		}
	}

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

	@:allow(hxmc.view) static function schedule(c:Computation) {
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
