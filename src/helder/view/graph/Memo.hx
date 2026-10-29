package helder.view.graph;

// A derived value (DESIGN.md 2, Memos): called to read it, computed when
// first read and again when read after what it read changed; its readers
// are marked only when the result differs.
abstract Memo<T>(Node<T>) {
	@:allow(helder.view.graph) inline function new(n:Node<T>)
		this = n;

	@:op(a()) inline function read():T
		return this.read();

	// the value, not tracked
	public inline function peek():T
		return this.peek();

	@:allow(helder.view.graph) inline function node():Node<T>
		return this;
}
