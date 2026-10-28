package helder.view;

// a derived value: recomputed when read and its sources changed; its
// observers are notified only when the result differs
class Memo<T> extends MemoBase {
	var v:T;
	final compute:Void->T;

	public function new(fn:Void->T) {
		super(null, false);
		compute = fn;
		update();
	}

	// (its computation read a value not ready: its readers throw it)
	var notReady:Null<Pending> = null;

	override function run() {
		var old = v;
		notReady = null;
		v = compute();
		if (old != v && observers != null)
			for (o in observers)
				o.state = Dirty;
	}

	public var value(get, never):T;

	function get_value():T {
		if (state != Clean) updateIfNecessary();
		var c = Reactive.current;
		if (c != null && c.depend(this)) {
			if (observers == null) observers = [];
			observers.push(c);
		}
		if (notReady != null) throw notReady;
		return v;
	}

	override function pending(p:Pending) {
		notReady = p;
		// (its readers read it again: they throw it now)
		if (observers != null)
			for (o in observers.copy())
				o.stale(Dirty);
	}

	public inline function get():T
		return value;

	public inline function peek():T {
		if (state != Clean) updateIfNecessary();
		return v;
	}

	public function toString():String
		return 'Memo($v)';
}

@:allow(helder.view)
class MemoBase extends Computation implements Source {
	public var observers(default, null):Null<Array<Computation>> = null;

	override function markObservers() {
		if (observers == null) return;
		for (o in observers.copy())
			o.stale(Check);
	}
}
