package hxmc.ui.reactive;

// a derived value: recomputed when read and its sources changed; its
// observers are notified only when the result differs
class Memo<T> extends MemoBase {
	var v:T;
	final compute:Void->T;

	public function new(fn:Void->T) {
		var self:Null<Memo<T>> = null;
		super(() -> self.recompute(), false);
		self = this;
		compute = fn;
		update();
	}

	function recompute() {
		var old = v;
		v = compute();
		if (old != v)
			for (o in observers)
				o.state = Dirty;
	}

	public var value(get, never):T;

	function get_value():T {
		if (state != Clean) updateIfNecessary();
		var c = Reactive.current;
		if (c != null && !c.sources.contains(this)) {
			c.sources.push(this);
			observers.push(c);
		}
		return v;
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

@:allow(hxmc.ui.reactive)
class MemoBase extends Computation implements Source {
	public var observers(default, null):Array<Computation> = [];

	override function markObservers() {
		for (o in observers.copy())
			o.stale(Check);
	}
}
