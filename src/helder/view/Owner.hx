package helder.view;

// what owns computations and cleanups (its lists made when first needed:
// most owners have no children, many no cleanups)
class Owner {
	public final parent:Null<Owner>;
	public var children(default, null):Null<Array<Owner>> = null;
	public var cleanups(default, null):Null<Array<Void->Void>> = null;
	// the context values set here (Reactive.provide), by Context id
	@:allow(helder.view) var contexts:Null<Map<Int, Dynamic>>;
	// what catches errors thrown below (ErrorBoundary)
	@:allow(helder.view) var onError:Null<Dynamic->Void>;
	// what is told of a value not ready below (Loading)
	@:allow(helder.view) var onPending:Null<Pending->Void>;
	var disposed = false;

	public function new(parent:Null<Owner>) {
		this.parent = parent;
		if (parent != null) {
			if (parent.children == null) parent.children = [];
			parent.children.push(this);
		}
	}

	// fn runs when this owner is disposed or cleaned
	public function onCleanup(fn:Void->Void) {
		if (cleanups == null) cleanups = [];
		cleanups.push(fn);
	}

	// disposes the children and runs the cleanups (the owner itself stays usable)
	public function clean() {
		if (children != null) {
			// (taken first: each child disposed leaves a list no longer here)
			var cs = children;
			children = null;
			for (c in cs)
				c.dispose();
		}
		if (cleanups != null) {
			var fs = cleanups;
			cleanups = null;
			for (f in fs)
				f();
		}
	}

	// the nearest context value of id, here or above (found: whether one was)
	@:allow(helder.view) function lookup(id:Int):{found:Bool, value:Dynamic} {
		var o = this;
		while (o != null) {
			if (o.contexts != null && o.contexts.exists(id)) return {found: true, value: o.contexts.get(id)};
			o = o.parent;
		}
		return {found: false, value: null};
	}

	// hands an error to the nearest handler (onError) here or above: false when there is none
	@:allow(helder.view) function handle(e:Dynamic):Bool {
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

	// a value not ready, read below: the nearest Loading boundary told
	// (none: nothing rendered, logged in dev builds)
	@:allow(helder.view) function suspended(p:Pending) {
		var o = this;
		while (o != null) {
			if (o.onPending != null) {
				o.onPending(p);
				return;
			}
			o = o.parent;
		}
		#if hxmc.dev
		Sys.stderr().writeString("helder.view: " + p.message + ": no <Loading> above it, nothing rendered for it\n");
		#end
	}

	public function dispose() {
		if (disposed) return;
		disposed = true;
		clean();
		if (parent != null && parent.children != null) parent.children.remove(this);
		detach();
	}

	function detach() {}

	public var isDisposed(get, never):Bool;

	inline function get_isDisposed()
		return disposed;
}
