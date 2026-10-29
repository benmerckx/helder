package helder.view.graph;

// A prop that reads (DESIGN.md 3.2): a constant, a signal, a memo or a
// function, each read by calling it (`props.step()`), tracked as what it
// reads is. Markup binds a prop of this type the way Solid binds props: a
// hole that may read (3.3) is given as a function of it, so the component
// reads the value when it uses it, not when it is made:
//
//   function Counter(props:{step:Read<Int>}) ...
//   <Counter step={1}/>  <Counter step={size}/>  <Counter step={a() + b()}/>
//
// A constant is a small cell, not a closure; a signal or a memo is its node.
abstract Read<T>(Reader<T>) from Reader<T> to Reader<T> {
	inline function new(r:Reader<T>)
		this = r;

	@:from static inline function ofSignal<T>(s:Signal<T>):Read<T>
		return new Read(s.node());

	@:from static inline function ofMemo<T>(m:Memo<T>):Read<T>
		return new Read(m.node());

	@:from static inline function ofThunk<T>(f:Void->T):Read<T>
		return new Read(new Thunk(f));

	@:from static inline function ofValue<T>(v:T):Read<T>
		return new Read(new Const(v));

	@:op(a()) inline function get():T
		return this.read();

	// the value, not tracked
	public inline function peek():T
		return this.peek();
}

// What a Read reads: a node, a constant, a function.
interface Reader<T> {
	function read():T;
	function peek():T;
}

// A constant's cell (the runtime sets it once, binds nothing).
class Const<T> implements Reader<T> {
	public final value:T;

	public function new(v:T)
		value = v;

	public function read():T
		return value;

	public function peek():T
		return value;
}

// A function read through a Read.
class Thunk<T> implements Reader<T> {
	public final fn:Void->T;

	public function new(f:Void->T)
		fn = f;

	public function read():T
		return fn();

	public function peek():T
		return Node.untrack(fn);
}
