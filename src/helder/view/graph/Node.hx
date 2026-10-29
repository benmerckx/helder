package helder.view.graph;

import helder.view.graph.Awaitable.NotReady;
import helder.view.graph.Owner.GraphError;

// A node of the graph: a signal (a value), a computed (a memo, or a
// derived signal, which can also be written) or an effect.
//
// Writes are deferred (Scheduler): a written node keeps the new value
// pending until the flush, which stages it in a transaction (Tx); a node
// keeps its committed value (the screen's) and, while a transaction holds
// it, a staged one. A computation run for a transaction reads its staged
// values and so joins it (reading another's joins both); one that reads
// none of it commits at once. Reading inside a computation makes the node
// its source; a staging marks the observers (Reactively's colouring: a
// direct observer dirty, those further down to check), effects and owned
// memos queued, an unowned memo recomputed when read.
//
// A computed that returns an Awaitable is pending until it answers, in
// the transaction that asked; reading it there stops the reader
// (NotReady): a memo is pending in turn, a render effect blocks the
// transaction (or an armed loading boundary above it catches it), a user
// effect waits. The answer lands into that transaction (Scheduler).
@:allow(helder.view.graph)
class Node<T> extends Owner {
	static inline var SIGNAL = 0;
	static inline var COMPUTED = 1;
	static inline var EFFECT = 2;
	static inline var RENDER = 3;

	static inline var CLEAN = 0;
	static inline var CHECK = 1;
	static inline var DIRTY = 2;

	static inline var PROBE_NONE = 0;
	static inline var PROBE_PENDING = 1;
	static inline var PROBE_LATEST = 2;

	// the computation whose reads are tracked now (null: none)
	static var observer:Null<Node<Dynamic>> = null;
	// the computation running now, tracked or not (its reads join transactions)
	static var runner:Null<Node<Dynamic>> = null;
	// (isPending, latest: reads that look ahead, and whether one saw a value on its way)
	static var probe = PROBE_NONE;
	static var probeHit = false;
	// (each run's number: a source read twice in a run is tracked once)
	static var runs = 0;
	// (the transaction a NotReady thrown came from)
	static var notReadyIn:Null<Tx> = null;

	final kind:Int;
	// the committed value (the screen's), and the staged one while a transaction holds it
	var value:T;
	var staged:Null<T> = null;
	var stagedIn:Null<Tx> = null;
	// (a write waiting for the flush)
	var pendingValue:Null<T> = null;
	var hasPending = false;
	// (a computed: no committed value yet; its async in flight, for that transaction)
	var uninit = false;
	var pendingIn:Null<Tx> = null;
	var awaiting:Null<Awaitable<Dynamic>> = null;
	var asked = 0;
	var answer:Dynamic = null;
	var answerFailed = false;
	final fn:Null<Null<T>->Dynamic>;
	final equals:Null<(T, T) -> Bool>;
	final unobserved:Null<Void->Void>;
	final ownedWrite:Bool;
	var state = CLEAN;
	var error:Dynamic = null;
	var hasError = false;
	var stagedError:Dynamic = null;
	var stagedFailed = false;
	var sources:Null<Array<Node<Dynamic>>> = null;
	var observers:Null<Array<Node<Dynamic>>> = null;
	// (a run's tracking: the old sources read again in order, then the new ones)
	var run = 0;
	var kept = 0;
	var added:Null<Array<Node<Dynamic>>> = null;
	var trackedBy:Null<Node<Dynamic>> = null;
	var trackedIn = -1;
	// (whether its run read what the transaction it ran for staged)
	var joined = false;
	// (an effect's: its second half, its last applied value, its cleanup,
	// its error handler, whether it waits in a queue or for its apply)
	var apply:Null<(T, Null<T>) -> Null<Void->Void>> = null;
	var applied:Null<T> = null;
	var applyCleanup:Null<Void->Void> = null;
	var onFailure:Null<Dynamic->Void> = null;
	var queued = false;
	var toApply = false;
	// (a render effect waiting on a value not ready: the transaction it blocks, or the boundary that caught it)
	var blockedIn:Null<Tx> = null;
	var caughtBy:Null<Boundary> = null;
	// (an unowned memo nothing observes: the commit it was last computed after)
	var tick = -1;
	// (a derived signal: its written value kept until a source changes)
	var writable = false;

	function new(kind:Int, value:Null<T>, fn:Null<Null<T>->Dynamic>, options:Null<NodeOptions<T>>) {
		// (a signal belongs to no owner: only computations are disposed with theirs)
		super(kind == SIGNAL ? null : Owner.current);
		this.kind = kind;
		this.value = value;
		this.fn = fn;
		uninit = kind == COMPUTED;
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
			Scheduler.applies.remove(n);
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

	// fn's reads looking ahead: whether one saw a value on its way (isPending), or
	// those values (latest); a first load gives no verdict (NotReady: tracked, it
	// suspends as the read would; untracked, isPending is false)
	static function probing<R>(mode:Int, fn:Void->R):{result:Null<R>, hit:Bool, notReady:Bool} {
		var savedProbe = probe, savedHit = probeHit;
		probe = mode;
		probeHit = false;
		var r:Null<R> = null, notReady = false;
		try r = fn() catch (e:NotReady) notReady = true catch (e:Dynamic) {
			probe = savedProbe;
			probeHit = savedHit;
			throw e;
		}
		var hit = probeHit;
		probe = savedProbe;
		probeHit = savedHit;
		return {result: r, hit: hit, notReady: notReady};
	}

	public function read():T {
		if (kind != SIGNAL) fresh();
		if (observer != null) observer.track(this);
		return serve();
	}

	public function peek():T {
		if (kind != SIGNAL) fresh();
		return serve();
	}

	// the value a read gets: in a transaction's world its staging (reading it
	// joins it), on the screen the committed value
	function serve():T {
		var t = stagedIn != null ? stagedIn.find() : null;
		var p = pendingIn != null ? pendingIn.find() : null;
		if (probe != PROBE_NONE) return probed(t, p);
		var w = Scheduler.world;
		if (w != null && (t != null || p != null)) {
			if (t != null) w = Scheduler.join(t);
			if (p != null) w = Scheduler.join(p);
			if (runner != null) runner.joined = true;
			if (p != null) notReady(w);
			if (t != null) {
				if (stagedFailed) throw stagedError;
				return staged;
			}
		}
		if (uninit) notReady(p);
		if (hasError) throw error;
		return value;
	}

	function probed(t:Null<Tx>, p:Null<Tx>):T {
		var ahead = t != null ? t : p;
		if (ahead != null && runner != null && !ahead.verdicts.contains(runner)) ahead.verdicts.push(runner);
		if (probe == PROBE_PENDING) {
			if (t != null || (p != null && !uninit)) probeHit = true;
		}
		if (t != null) {
			if (stagedFailed) throw stagedError;
			return staged;
		}
		if (uninit) notReady(p);
		if (hasError) throw error;
		return value;
	}

	inline function notReady(tx:Null<Tx>):Dynamic {
		notReadyIn = tx;
		throw NotReady.instance;
	}

	public function write(v:T) {
		checkWritable();
		if (same(latest(), v)) return;
		pendingValue = v;
		if (!hasPending) {
			hasPending = true;
			Scheduler.enqueueWrite(this);
		}
	}

	// f given the latest value written (pending, else staged, else committed)
	public function update(f:T->T)
		write(f(latest()));

	inline function latest():Null<T>
		return hasPending ? pendingValue : stagedIn != null ? staged : value;

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

	// (the flush: a pending write staged in tx; one that nets to the current value is none)
	function stageWrite(tx:Tx) {
		hasPending = false;
		var v = pendingValue;
		pendingValue = null;
		if (!uninit && same(stagedIn != null ? staged : value, v)) return;
		stage(v, tx);
		markObservers(DIRTY);
	}

	// (v staged in tx: a node another transaction holds joins it with tx)
	function stage(v:Null<T>, tx:Tx) {
		var t = stagedIn != null ? stagedIn.find() : null;
		if (t == null) {
			stagedIn = tx.find();
			stagedIn.nodes.push(this);
		} else if (t != tx.find()) {
			Scheduler.join(t);
		}
		staged = v;
		stagedFailed = false;
		stagedError = null;
	}

	function stageError(e:Dynamic, tx:Tx) {
		stage(null, tx);
		stagedFailed = true;
		stagedError = e;
	}

	// (its transaction committed: the staging is the value)
	function commitStaged() {
		if (stagedFailed) {
			error = stagedError;
			hasError = true;
		} else {
			value = staged;
			hasError = false;
			error = null;
		}
		uninit = false;
		staged = null;
		stagedIn = null;
		stagedFailed = false;
		stagedError = null;
	}

	// (its async answered: the answer staged in the transaction that asked, its readers run again)
	function land() {
		var w = Scheduler.world;
		if (answerFailed) stageError(answer, w) else stage(answer, w);
		answer = null;
		if (observers != null) for (o in observers) o.mark(DIRTY);
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
		// (a superseded async run: cancelled, its answer dropped)
		asked++;
		if (awaiting != null) {
			var a = awaiting;
			awaiting = null;
			a.cancel();
		}
		pendingIn = null;
		release();
		var savedOwner = Owner.current, savedObserver = observer, savedRunner = runner, savedProbe = probe;
		Owner.current = this;
		observer = this;
		runner = this;
		probe = PROBE_NONE;
		joined = false;
		run = ++runs;
		kept = 0;
		added = null;
		var r:Dynamic = null, failure:Dynamic = null, failed = false, waiting = false;
		try r = fn(kind == COMPUTED ? current() : value) catch (e:NotReady) waiting = true catch (e:Dynamic) {
			failure = e;
			failed = true;
		}
		Owner.current = savedOwner;
		observer = savedObserver;
		runner = savedRunner;
		probe = savedProbe;
		reconcile();
		state = CLEAN;
		var w = Scheduler.world != null ? Scheduler.world.find() : null;
		var mine = w != null && joined;
		if (waiting) wait(notReadyIn != null ? notReadyIn.find() : null)
		else if (failed) failWith(failure, mine ? w : null)
		else if (kind == COMPUTED && Std.isOfType(r, Awaitable)) ask(r, w)
		else settle(r, mine ? w : null);
	}

	// (the value its run builds on: the world's staging, else the committed one)
	function current():Null<T> {
		var w = Scheduler.world;
		if (stagedIn != null && w != null && stagedIn.find() == w.find()) return staged;
		return uninit ? null : value;
	}

	// (its run read a value not ready, in tx)
	function wait(tx:Null<Tx>) {
		switch kind {
			case COMPUTED:
				// (pending in turn: its readers wait with it)
				pendingIn = tx;
				if (observers != null) for (o in observers) o.state = DIRTY;
			case RENDER:
				// (an armed boundary above catches it, else it holds the transaction)
				var b = Boundary.catching(this);
				if (b != null) {
					caughtBy = b;
					b.caught(this);
				} else if (tx != null) {
					blockedIn = tx;
					tx.block(this);
				}
			case _:
				// (a user effect holds nothing: it runs again when the value lands)
		}
	}

	// (no longer waiting: off the transaction it blocked, the boundary that caught it)
	function release() {
		if (blockedIn != null) {
			blockedIn.find().unblock(this);
			blockedIn = null;
		}
		if (caughtBy != null) {
			var b = caughtBy;
			caughtBy = null;
			b.released(this);
		}
	}

	// (async: pending in the transaction that asked, until the answer lands)
	function ask(a:Awaitable<Dynamic>, w:Null<Tx>) {
		var tx = w != null ? w : new Tx();
		pendingIn = tx;
		awaiting = a;
		var id = asked;
		if (observers != null) for (o in observers) o.state = DIRTY;
		a.onAnswer(v -> answered(id, v, false), e -> answered(id, e, true));
	}

	function answered(id:Int, v:Dynamic, failed:Bool) {
		if (id != asked || disposed) return;
		awaiting = null;
		answer = v;
		answerFailed = failed;
		Scheduler.landing(this);
	}

	// (a value computed: staged in tx when its run joined one, else committed)
	function settle(v:Null<T>, tx:Null<Tx>) {
		if (kind == COMPUTED) {
			// (a comparator's error is the computation's)
			var changed = try uninit || hasError || stagedFailed || !same(stagedIn != null ? staged : value, v) catch (e:Dynamic) {
				failWith(e, tx);
				return;
			};
			if (!changed) return;
			if (tx != null) stage(v, tx) else {
				value = v;
				uninit = false;
				hasError = false;
				error = null;
			}
			// (its observers read it again)
			if (observers != null) for (o in observers) o.state = DIRTY;
			return;
		}
		value = v;
		if (tx != null) {
			if (!tx.effects.contains(this)) tx.effects.push(this);
		} else
			Scheduler.enqueueApply(this);
	}

	function failWith(e:Dynamic, tx:Null<Tx>) {
		if (kind == COMPUTED) {
			if (tx != null) stageError(e, tx) else {
				error = e;
				hasError = true;
				uninit = false;
			}
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
		release();
		if (awaiting != null) {
			var a = awaiting;
			awaiting = null;
			a.cancel();
		}
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
