package helder.view.graph;

// What Graph.signal is made from: a value, or a function (with or
// without the previous value) for a value derived from what it reads.
// No macro: the function forms are tried first. A signal never holds a
// function (DESIGN.md 3.1): a lambda whose parameter has no type, which
// Haxe cannot match to the derived form, would make one, and is an error
// where a type is expected and when the signal is made.
abstract Init<T>(InitKind<T>) {
	inline function new(k:InitKind<T>)
		this = k;

	@:from static inline function ofDerived<T>(f:Null<T>->T):Init<T>
		return new Init(Derived(f));

	@:from static inline function ofThunk<T>(f:Void->T):Init<T>
		return new Init(Derived(_ -> f()));

	@:from static inline function ofValue<T>(v:T):Init<T>
		return new Init(Value(v));

	@:allow(helder.view.graph) inline function kind():InitKind<T>
		return this;
}

enum InitKind<T> {
	Value(v:T);
	Derived(f:Null<T>->T);
}
