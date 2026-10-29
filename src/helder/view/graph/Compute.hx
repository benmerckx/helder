package helder.view.graph;

// A computation's function: given the previous value (null on the first
// run) or not; an effect's may return nothing; a memo's may return an
// Awaitable (async: the memo's value is its answer). Underneath, a
// function whose result is a T or an Awaitable<T> (a computation that
// returns an Awaitable is async, as Solid's returning a Promise).
abstract Compute<T>(Null<T>->Dynamic) from Null<T>->T to Null<T>->Dynamic {
	@:from static inline function ofAsync<T, A:Awaitable<T>>(f:Void->A):Compute<T>
		return cast (_ -> f() : Null<T>->Dynamic);

	@:from static inline function ofVoid(f:Void->Void):Compute<Any>
		return cast (_ -> {
			f();
			null;
		} : Null<Any>->Dynamic);

	@:from static inline function ofThunk<T>(f:Void->T):Compute<T>
		return cast (_ -> f() : Null<T>->Dynamic);
}
