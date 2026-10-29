package view.graph;

// vi.fn() for the graph's tests: counts its calls and keeps their arguments
class Spy {
	public var calls(default, null) = 0;
	public var args(default, null):Array<Array<Dynamic>> = [];

	public function new() {}

	public function call(?a:Dynamic, ?b:Dynamic) {
		calls++;
		args.push([a, b]);
	}

	// called with v, returning it (vi.fn(v => v))
	public function ret<T>(v:T):T {
		call(v);
		return v;
	}

	public function fn0():Void->Void
		return () -> call();

	public function fn1<A>():A->Void
		return a -> call(a);

	public function fn2<A, B>():(A, B)->Void
		return (a, b) -> call(a, b);

	// whether a call had these arguments (the missing ones null)
	public function calledWith(?a:Dynamic, ?b:Dynamic):Bool {
		for (c in args)
			if (helder.test.Equal.diff(c, [a, b]) == null) return true;
		return false;
	}

	public function reset() {
		calls = 0;
		args = [];
	}
}
