package helder.view.graph;

// options of a signal and a memo
typedef NodeOptions<T> = {
	// whether a new value is the same as the old one (default ==): the same is no change
	?equals:(T, T) -> Bool,
	// called when its last reader goes
	?unobserved:Void->Void,
	// (a signal) writable inside a computation (DESIGN.md 6, 3)
	?ownedWrite:Bool,
}
