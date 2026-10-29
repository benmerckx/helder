package helder.view.graph;

// An effect's second half (DESIGN.md 2, Effects in two halves): given the
// value its compute returned and the previous one (null on the first
// run), it may return a cleanup, run before the next apply and when the
// effect is disposed.
abstract Apply<T>((T, Null<T>) -> Null<Void->Void>) from (T, Null<T>) -> Null<Void->Void> to (T, Null<T>) -> Null<Void->Void> {
	@:from static function ofVoid2<T>(f:(T, Null<T>) -> Void):Apply<T>
		return ((v, p) -> {
			f(v, p);
			null;
		} : (T, Null<T>) -> Null<Void->Void>);

	@:from static function ofVoid1<T>(f:T->Void):Apply<T>
		return ((v, _) -> {
			f(v);
			null;
		} : (T, Null<T>) -> Null<Void->Void>);

	@:from static function ofVoid0<T>(f:Void->Void):Apply<T>
		return ((_, _) -> {
			f();
			null;
		} : (T, Null<T>) -> Null<Void->Void>);

	@:from static function ofCleanup1<T>(f:T->(Void->Void)):Apply<T>
		return ((v, _) -> f(v) : (T, Null<T>) -> Null<Void->Void>);
}
