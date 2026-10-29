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

	@:op(a()) inline function write(value:T):Void
		this.write(value);

	// (Updater, not T->T: hxmc 0.1.0-nightly.20261028.d002660 fails to
	// resolve the abstract (HXB) when this overload takes T->T and is
	// called from a module-level function; reported)
	@:op(a()) inline function update(f:Updater<T>):Void
		this.update(f);

	// the committed value, not tracked
	public inline function peek():T
		return this.peek();

	@:allow(helder.view.graph) inline function node():Node<T>
		return this;
}

typedef Updater<T> = T->T;
