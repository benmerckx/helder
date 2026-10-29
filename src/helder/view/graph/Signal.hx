package helder.view.graph;

// A value in the graph (DESIGN.md 3.1): called to read it (tracked inside
// a computation), called with a value to write it, with a function to
// update it from the latest value written (a write is committed at the
// next flush: reads see the committed value until then). Made by
// Graph.signal: a value, or a function for a value derived from what it
// reads that can also be written. Never a function itself.
abstract Signal<T>(Node<T>) {
	@:allow(helder.view.graph) inline function new(n:Node<T>)
		this = n;

	@:op(a()) inline function read():T
		return this.read();

	// (update before write: an argument of no static type, Dynamic, is then a
	// write (Haxe picks the last overload it fits), a function literal an update)
	@:op(a()) inline function update(f:T->T):Void
		this.update(f);

	@:op(a()) inline function write(value:T):Void
		this.write(value);

	// the committed value, not tracked
	public inline function peek():T
		return this.peek();

	@:allow(helder.view.graph) inline function node():Node<T>
		return this;
}
