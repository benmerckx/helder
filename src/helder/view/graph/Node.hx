package helder.view.graph;

import helder.view.graph.Owner.GraphError;

// A node of the graph: a signal (a value), a computed (a memo, or a
// derived signal, which can also be written) or an effect. Writes are
// deferred (Scheduler): a written node keeps the new value pending until
// the commit, reads seeing the committed one; an update is given the
// pending value. Reading inside a computation makes the node its source;
// a commit marks the observers (Reactively's colouring: a direct observer
// dirty, those further down to check), effects queued, memos recomputed
// when read (no glitches, no needless work).
@:allow(helder.view.graph)
class Node<T> extends Owner {
	static inline var SIGNAL = 0;
	static inline var COMPUTED = 1;
	static inline var EFFECT = 2;
	static inline var RENDER = 3;

	static inline var CLEAN = 0;
	static inline var CHECK = 1;
	static inline var DIRTY = 2;

	// the computation whose reads are tracked now (null: none)
	static var observer:Null<Node<Dynamic>> = null;
	// (each run's number: a source read twice in a run is tracked once)
	static var runs = 0;

	final kind:Int;
	var value:T;
	var pendingValue:Null<T> = null;
	var hasPending = false;
	final fn:Null<Null<T>->T>;
	final equals:Null<(T, T) -> Bool>;
	final unobserved:Null<Void->Void>;
	final ownedWrite:Bool;
	var state = CLEAN;
	var initialized = false;
	var error:Dynamic = null;
	var hasError = false;
	var sources:Null<Array<Node<Dynamic>>> = null;
	var observers:Null<Array<Node<Dynamic>>> = null;
	// (a run's tracking: the old sources read again in order, then the new ones)
	var run = 0;
	var kept = 0;
	var added:Null<Array<Node<Dynamic>>> = null;
	var trackedBy:Null<Node<Dynamic>> = null;
	var trackedIn = -1;
	// (an effect's: its second half, its last applied value, its cleanup,
	// its error handler, whether it waits in a queue or for its apply)
	var apply:Null<(T, Null<T>) -> Null<Void->Void>> = null;
	var applied:Null<T> = null;
	var applyCleanup:Null<Void->Void> = null;
	var onFailure:Null<Dynamic->Void> = null;
	var queued = false;
	var toApply = false;
	// (an unowned memo nothing observes: the flush it was last computed after)
	var tick = -1;
	// (a derived signal: its written value kept until a source changes)
	var writable = false;

	function new(kind:Int, value:Null<T>, fn:Null<Null<T>->T>, options:Null<NodeOptions<T>>) {
		// (a signal belongs to no owner: only computations are disposed with theirs)
		super(kind == SIGNAL ? null : Owner.current);
		this.kind = kind;
		this.value = value;
		this.fn = fn;
		equals = options != null ? options.equals : null;
		unobserved = options != null ? options.unobserved : null;
		ownedWrite = options != null && options.ownedWrite == true;
	}

	public static function signal<T>(value:T, options:Null<NodeOptions<T>>):Node<T> {
		if (Reflect.isFunction(value)) throw new GraphError("a signal never holds a function: signal(fn) derives its value from fn (give its parameter a type: (prev:Null<T>) -> ...)");
		return new Node(SIGNAL, value, null, options);
	}

	// a memo (writable: a derived signal), computed now
	public static function computed<T>(fn:Compute<T>, options:Null<NodeOptions<T>>, writable:Bool):Node<T> {
		var n = new Node(COMPUTED, null, fn, options);
		n.writable = writable;
		n.recompute();
		return n;
	}

	// compute run now; apply at the next flush, a render effect's first now
	public static function effect<T>(compute:Compute<T>, apply:Apply<T>, error:Null<Dynamic->Void>, render:Bool) {
		var n = new Node(render ? RENDER : EFFECT, null, compute, null);
		n.apply = apply;
		n.onFailure = error;
		n.recompute();
		if (render && n.toApply) {
			n.toApply = false;
			n.applyNow();
		}
	}

	public static function untrack<T>(fn:Void->T):T {
		var saved = observer;
		observer = null;
		try {
			var r = fn();
			observer = saved;
			return r;
		} catch (e:Dynamic) {
			observer = saved;
			throw e;
		}
	}

	// fn run with o the owner and obs the observer
	static function within<T>(o:Null<Owner>, obs:Null<Node<Dynamic>>, fn:Void->T):T {
		var savedOwner = Owner.current, savedObserver = observer;
		Owner.current = o;
		observer = obs;
		try {
			var r = fn();
			Owner.current = savedOwner;
			observer = savedObserver;
			return r;
		} catch (e:Dynamic) {
			Owner.current = savedOwner;
			observer = savedObserver;
			throw e;
		}
	}

	public function read():T {
		if (kind != SIGNAL) fresh();
		if (observer != null) observer.track(this);
		if (hasError) throw error;
		return value;
	}

	public function peek():T {
		if (kind != SIGNAL) fresh();
		if (hasError) throw error;
		return value;
	}

	public function write(v:T) {
		checkWritable();
		if (same(hasPending ? pendingValue : value, v)) return;
		pendingValue = v;
		if (!hasPending) {
			hasPending = true;
			Scheduler.enqueueWrite(this);
		}
	}

	// f given the latest value written (pending, else committed)
	public function update(f:T->T)
		write(f(hasPending ? pendingValue : value));

	// (a computed up to date: an unowned memo nothing observes is not kept
	// up to date by the flushes, it computes again when read after one, as
	// Solid 2 releases it)
	inline function fresh() {
		if (kind == COMPUTED && !writable && parent == null && tick != Scheduler.ticks && (observers == null || observers.length == 0)) state = DIRTY;
		if (state != CLEAN) updateIfNecessary();
	}

	function checkWritable() {
		if (ownedWrite || Owner.current == null || Owner.disposing > 0) return;
		throw new GraphError("a write inside an owned scope (a root's body, a component, a computation): write from an event or an effect's apply, or make the signal with ownedWrite");
	}

	inline function same(a:Null<T>, b:Null<T>):Bool
		return equals != null ? equals(a, b) : a == b;

	// (the commit: the pending value committed, the observers marked)
	function commit() {
		hasPending = false;
		var v = pendingValue;
		pendingValue = null;
		// (a derived signal written: its value until its function runs again, given it as prev)
		if (initialized && same(value, v)) return;
		value = v;
		hasError = false;
		markObservers(DIRTY);
	}

	function markObservers(s:Int) {
		if (observers == null) return;
		for (o in observers)
			o.mark(s);
	}

	function mark(s:Int) {
		if (state >= s) return;
		var was = state;
		state = s;
		if (was == CLEAN) {
			// (an owned memo is eager: brought up to date by the flush, read or not)
			if (kind >= EFFECT || parent != null) Scheduler.enqueue(this);
			if (kind == COMPUTED) markObservers(CHECK);
		}
	}

	// up to date: recomputed if a source really changed
	function updateIfNecessary() {
		if (disposed) return;
		if (state == CHECK && sources != null) {
			for (s in sources) {
				if (s.kind == COMPUTED) s.updateIfNecessary();
				if (state == DIRTY) break;
			}
		}
		if (state == DIRTY) recompute();
		state = CLEAN;
	}

	// runs its function, tracking what it reads
	function recompute() {
		if (disposed) return;
		try clean() catch (e:Dynamic) Scheduler.report(e);
		tick = Scheduler.ticks;
		var savedOwner = Owner.current, savedObserver = observer;
		Owner.current = this;
		observer = this;
		run = ++runs;
		kept = 0;
		added = null;
		var v:Null<T> = null, failure:Dynamic = null, failed = false;
		try v = fn(initialized ? value : null) catch (e:Dynamic) {
			failure = e;
			failed = true;
		}
		Owner.current = savedOwner;
		observer = savedObserver;
		reconcile();
		state = CLEAN;
		if (failed) {
			fail(failure);
			return;
		}
		if (kind == COMPUTED) {
			// (a comparator's error is the computation's)
			var changed = try !initialized || hasError || !same(value, v) catch (e:Dynamic) {
				fail(e);
				return;
			};
			initialized = true;
			hasError = false;
			if (changed) {
				value = v;
				// (its observers read it again)
				if (observers != null) for (o in observers) o.state = DIRTY;
			}
		} else {
			value = v;
			initialized = true;
			Scheduler.enqueueApply(this);
		}
	}

	function fail(e:Dynamic) {
		if (kind == COMPUTED) {
			error = e;
			hasError = true;
			initialized = true;
			if (observers != null) for (o in observers) o.state = DIRTY;
			return;
		}
		// (an effect: its handler, else the nearest boundary, else the flush throws it)
		if (onFailure != null) onFailure(e) else if (parent == null || !parent.handle(e)) Scheduler.failed(e);
	}

	// s read in the current run
	function track(s:Node<Dynamic>) {
		if (s.trackedBy == this && s.trackedIn == run) return;
		s.trackedBy = this;
		s.trackedIn = run;
		if (added == null && sources != null && kept < sources.length && sources[kept] == s) {
			kept++;
			return;
		}
		if (added == null) added = [];
		added.push(s);
	}

	// (after a run: the new sources subscribed, then those not read again left)
	function reconcile() {
		var old = sources;
		if (added != null) {
			var stale = old != null && kept < old.length ? old.slice(kept) : null;
			if (old == null) sources = old = [];
			old.resize(kept);
			for (s in added) {
				old.push(s);
				if (s.observers == null) s.observers = [];
				s.observers.push(this);
			}
			added = null;
			if (stale != null) for (s in stale) s.unobserve(this);
		} else if (old != null && kept < old.length) {
			var stale = old.slice(kept);
			old.resize(kept);
			for (s in stale)
				s.unobserve(this);
		}
	}

	function unobserve(o:Node<Dynamic>) {
		if (observers == null || !observers.remove(o)) return;
		if (observers.length == 0 && unobserved != null) unobserved();
	}

	// (applies its second half; its error the nearest boundary's, else the flush's)
	function runApply() {
		toApply = false;
		try applyNow() catch (e:Dynamic) if (parent == null || !parent.handle(e)) Scheduler.report(e);
	}

	// (the previous apply's cleanup first)
	function applyNow() {
		if (disposed || apply == null) return;
		if (applyCleanup != null) {
			var c = applyCleanup;
			applyCleanup = null;
			c();
		}
		var prev = applied;
		applied = value;
		var c = within(null, null, () -> apply(value, prev));
		if (c != null && !Reflect.isFunction(c))
			throw new GraphError("effect callback returned an invalid cleanup value: return a cleanup function or nothing");
		applyCleanup = c;
	}

	override function unlink() {
		if (sources != null) {
			var ss = sources;
			sources = null;
			for (s in ss)
				s.unobserve(this);
		}
		if (applyCleanup != null) {
			var c = applyCleanup;
			applyCleanup = null;
			Owner.disposing++;
			try c() catch (e:Dynamic) {
				Owner.disposing--;
				throw e;
			}
			Owner.disposing--;
		}
	}
}
