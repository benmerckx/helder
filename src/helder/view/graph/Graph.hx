package helder.view.graph;

// helder.view's reactive graph (DESIGN.md): Solid 2's semantics on a
// runtime of helder's own. Signals hold values, memos derive them, effects
// run in two halves (compute tracked, apply after the commit). Writes are
// deferred: committed together at the next flush (the loop's task ending,
// or flush()), reads seeing the committed value until then. Computations
// form an ownership tree: those made while another runs belong to it and
// are disposed before it runs again.
//
//   var count = signal(0);
//   var double = memo(() -> count() * 2);
//   effect(() -> double(), v -> trace(v));
//   count(c -> c + 1);
class Graph {
	// a signal: of a value, or of a function's value (derived from what it
	// reads, writable); a signal never holds a function (DESIGN.md 3.1, Init)
	#if hxmc.dev
	// (hxmc dev: kept across a reload by its key, helder.view.Refresh)
	public static macro function signal(init:haxe.macro.Expr, rest:Array<haxe.macro.Expr>):haxe.macro.Expr
		return helder.view.Refresh.signal(init, rest);
	#else
	public static inline function signal<T>(init:Init<T>, ?options:NodeOptions<T>):Signal<T>
		return signalOf(init, options);
	#end

	// (a value's signal, as TypeScript's signal(v) calls it: index.d.ts)
	@:noCompletion public static function signalValue<T>(@:typescript.type("T extends Function ? never : T") value:T):Signal<T>
		return new Signal(Node.signal(value, null));

	// (signal's function)
	public static function signalOf<T>(init:Init<T>, ?options:NodeOptions<T>):Signal<T>
		return new Signal(switch init.kind() {
			// (a Dynamic value, given as a function when it is none: a value)
			case null: Node.signal(null, options);
			case Derived(f) if (!Reflect.isFunction(f)): Node.signal(cast f, options);
			case Value(v): Node.signal(v, options);
			case Derived(f): Node.computed(f, options, true);
		});

	public static function memo<T>(fn:Compute<T>, ?options:NodeOptions<T>):Memo<T>
		return new Memo(Node.computed(fn, options, false));

	// compute runs now and again when what it read changes; apply after the
	// commit, given its value and the previous one (the first: at the next
	// flush); error, when given, takes compute's errors (else the nearest
	// error boundary, else flush throws them)
	public static function effect<T>(compute:Compute<T>, apply:Apply<T>, ?error:Dynamic->Void):Void
		Node.effect(compute, apply, error, false);

	// as effect, its apply in the render phase: before every effect's
	public static function renderEffect<T>(compute:Compute<T>, apply:Apply<T>, ?error:Dynamic->Void):Void
		Node.effect(compute, apply, error, true);

	// fn run once the current commit has landed (its applies done), not
	// tracked: after the nodes being rendered are in the tree (Solid 2's
	// onSettled, onMount's successor); disposed with the current owner
	public static function onSettled(fn:Void->Void):Void
		Node.effect(_ -> null, (_, _) -> {
			fn();
			null;
		}, null, false);

	// a new ownership tree, owned by the current owner if any: fn gets its dispose
	public static function root<T>(fn:(dispose:Void->Void)->T):T
		return Owner.root(fn);

	// fn's reads not tracked
	public static function untrack<T>(fn:Void->T):T
		return Node.untrack(fn);

	// commits the writes now and runs what they make stale
	public static overload extern inline function flush():Void
		Scheduler.flush();

	// runs fn, then commits its writes before returning its value
	public static overload extern inline function flush<T>(fn:Void->T):T
		return Scheduler.flushWith(fn);

	// fn runs when the current owner is disposed or runs again
	public static function onCleanup(fn:Void->Void):Void
		Owner.onCleanup(fn);

	public static function getOwner():Null<Owner>
		return Owner.current;

	// fn run (untracked) with o as the owner of what it makes
	public static function runWithOwner<T>(o:Null<Owner>, fn:Void->T):T
		return Owner.runWith(o, fn);

	// a context without a default: reading it where none is provided is an error
	public static overload extern inline function context<T>():Context<T>
		return new Context(null, false);

	// a context with a default (null is one)
	public static overload extern inline function context<T>(defaultValue:T):Context<T>
		return new Context(defaultValue, true);

	// the nearest value of c provided above the current owner, else its default
	public static function use<T>(c:Context<T>):T
		return Owner.use(c);

	// c set to value in the current owner (what it makes sees it)
	public static function setContext<T>(c:Context<T>, value:T):Void
		Owner.setContext(c, value);

	// fn run in a new owner with c set to value
	public static function provide<T, R>(c:Context<T>, value:T, fn:Void->R):R
		return Owner.provide(c, value, fn);

	// an async computation's function from a coroutine (memo(task(() -> ...))):
	// each run a task started now, on helder.async's loop, its reads up to the
	// first suspension tracked, cancelled when the run is superseded (not
	// `async`: helder.test's, imported beside it, would be shadowed)
	public static function task<T>(fn:haxe.coro.Coroutine<Void->T>):Void->Awaitable<T>
		return () -> new Coroutines.CoroutineRun<T>(cast fn);

	// whether what fn reads has a new value on its way (a held change, an
	// async answer to a new question): looks ahead of the hold, never holds
	// it; a first load gives no verdict (false; tracked, it suspends as the
	// read would); an error in fn is false
	public static function isPending(fn:Void->Any):Bool {
		var r = Node.probing(Node.PROBE_PENDING, fn);
		// (an error as the new answer is still a new answer on its way)
		if (r.failed) return r.hit;
		if (r.notReady) {
			if (Node.observer != null) throw helder.view.graph.Awaitable.NotReady.instance;
			return false;
		}
		return r.hit;
	}

	// fn's value with the values on their way (a held change's), ahead of the hold
	public static function latest<T>(fn:Void->T):T {
		var r = Node.probing(Node.PROBE_LATEST, fn);
		if (r.failed) throw r.error;
		if (r.notReady) throw helder.view.graph.Awaitable.NotReady.instance;
		return r.result;
	}

	// fn's value, or fallback's while what fn reads (or renders) is pending
	// and the boundary has not shown content (the core of <Loading>)
	public static function loadingBoundary<T>(fn:Void->T, fallback:Void->T):Memo<T>
		return Boundary.loading(fn, fallback);

	// fn's value, or fallback's when fn (or what it renders) throws; reset tries again
	// (the core of <Errored>)
	public static function errorBoundary<T>(fn:Void->T, fallback:(error:Void->Dynamic, reset:Void->Void)->T):Memo<T>
		return Boundary.errored(fn, fallback);
}
