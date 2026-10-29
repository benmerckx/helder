package helder.view.graph;

// A computation's function: given the previous value (null on the first
// run) or not.
abstract Compute<T>(Null<T>->T) from Null<T>->T to Null<T>->T {
	@:from static inline function ofThunk<T>(f:Void->T):Compute<T>
		return (_ -> f() : Null<T>->T);
}
