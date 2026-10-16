package hxmc.ui.reactive;

// what owns computations and cleanups
class Owner {
	public final parent:Null<Owner>;
	public final children:Array<Owner> = [];
	public final cleanups:Array<Void->Void> = [];
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
