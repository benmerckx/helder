package hxmc.ui.reactive;

// what owns computations and cleanups
class Owner {
	public final parent:Null<Owner>;
	public final children:Array<Owner> = [];
	public final cleanups:Array<Void->Void> = [];
	// the context values set here (Reactive.provide), by Context id
	@:allow(hxmc.ui.reactive) var contexts:Null<Map<Int, Dynamic>>;
	// what catches errors thrown below (ErrorBoundary)
	@:allow(hxmc.ui.reactive) var onError:Null<Dynamic->Void>;
	var disposed = false;

	public function new(parent:Null<Owner>) {
		this.parent = parent;
		if (parent != null) parent.children.push(this);
	}

	// disposes the children and runs the cleanups (the owner itself stays usable)
	public function clean() {
		for (c in children.copy())
			c.dispose();
		children.resize(0);
		var cs = cleanups.copy();
		cleanups.resize(0);
		for (f in cs)
			f();
	}

	// the nearest context value of id, here or above (found: whether one was)
	@:allow(hxmc.ui.reactive) function lookup(id:Int):{found:Bool, value:Dynamic} {
		var o = this;
		while (o != null) {
			if (o.contexts != null && o.contexts.exists(id)) return {found: true, value: o.contexts.get(id)};
			o = o.parent;
		}
		return {found: false, value: null};
	}

	// hands an error to the nearest handler (onError) here or above: false when there is none
	@:allow(hxmc.ui.reactive) function handle(e:Dynamic):Bool {
		var o = this;
		while (o != null) {
			if (o.onError != null) {
				o.onError(e);
				return true;
			}
			o = o.parent;
		}
		return false;
	}

	public function dispose() {
		if (disposed) return;
		disposed = true;
		clean();
		if (parent != null) parent.children.remove(this);
		detach();
	}

	function detach() {}

	public var isDisposed(get, never):Bool;

	inline function get_isDisposed()
		return disposed;
}
