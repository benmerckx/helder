package helder.view;

// a value: reading it (value, get()) inside a computation tracks it; writing a different one notifies
class Signal<T> extends SignalBase {
	var v:T;

	public function new(value:T) {
		v = value;
	}

	public var value(get, set):T;

	function get_value():T {
		track();
		return v;
	}

	function set_value(x:T):T {
		if (x == v) return x;
		v = x;
		Reactive.batch(notify);
		return x;
	}

	public inline function get():T
		return value;

	public inline function set(x:T)
		value = x;

	// sets it from its current value (untracked)
	public inline function update(f:T->T)
		value = f(v);

	// the value, not tracked
	public inline function peek():T
		return v;

	// notifies even though the value is the same object (it was changed inside)
	public function changed()
		Reactive.batch(notify);

	public function toString():String
		return 'Signal($v)';
}

@:allow(helder.view)
class SignalBase implements Source {
	public var observers(default, null):Null<Array<Computation>> = null;

	function track() {
		var c = Reactive.current;
		if (c != null && c.depend(this)) {
			if (observers == null) observers = [];
			observers.push(c);
		}
	}

	function notify() {
		if (observers == null) return;
		for (o in observers.copy())
			o.stale(Dirty);
	}
}
