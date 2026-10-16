package hxmc.ui.reactive;

import hxmc.ui.reactive.Memo;
import hxmc.ui.reactive.Signal;

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
