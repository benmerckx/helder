package helder.view.graph;

// What owns computations, cleanups and context values: the ownership
// tree. Computations made while another runs belong to it; disposing an
// owner unwinds it: its children first, newest first, then its own
// cleanups, the last registered first (Solid 2's order).
@:allow(helder.view.graph)
class Owner {
	// the owner of the code running now (null: none)
	public static var current(default, null):Null<Owner> = null;

	public final parent:Null<Owner>;
	var children:Null<Array<Owner>> = null;
	var cleanups:Null<Array<Void->Void>> = null;
	// the context values set here, by Context id
	var contexts:Null<Map<Int, Dynamic>> = null;
	// what takes an error thrown below (an error boundary)
	var onError:Null<Dynamic->Void> = null;
	var disposed = false;

	// (disposals running: writes are allowed there)
	static var disposing = 0;

	public function new(parent:Null<Owner>) {
		this.parent = parent;
		if (parent != null) {
			if (parent.children == null) parent.children = [];
			parent.children.push(this);
		}
	}

	public var isDisposed(get, never):Bool;

	inline function get_isDisposed()
		return disposed;

	public function dispose() {
		if (disposed) return;
		disposed = true;
		clean();
		if (parent != null && parent.children != null) parent.children.remove(this);
		unlink();
	}

	// its children disposed and its cleanups run (it stays usable: a computation running again)
	function clean() {
		if (children == null && cleanups == null) return;
		disposing++;
		var failure:Null<Dynamic> = null;
		if (children != null) {
			var cs = children;
			children = null;
			var i = cs.length;
			while (i-- > 0)
				try cs[i].dispose() catch (e:Dynamic) if (failure == null) failure = e;
		}
		if (cleanups != null) {
			var fs = cleanups;
			cleanups = null;
			var i = fs.length;
			while (i-- > 0)
				try fs[i]() catch (e:Dynamic) if (failure == null) failure = e;
		}
		disposing--;
		// (every cleanup ran; the first failure reported)
		if (failure != null) throw failure;
	}

	// (a node's: off its sources and queues)
	function unlink() {}

	// the error handled by the nearest boundary here or above: false when there is none
	function handle(e:Dynamic):Bool {
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

	public static function root<T>(fn:(dispose:Void->Void)->T):T {
		var o = new Owner(current);
		return Node.within(o, null, () -> fn(o.dispose));
	}

	public static function onCleanup(fn:Void->Void) {
		var o = current;
		if (o == null) return;
		if (o.cleanups == null) o.cleanups = [];
		o.cleanups.push(fn);
	}

	public static function runWith<T>(o:Null<Owner>, fn:Void->T):T
		return Node.within(o, null, fn);

	public static function use<T>(c:Context<T>):T {
		var o = current;
		if (o == null) throw new GraphError("context read outside an owner (a root, a component)");
		while (o != null) {
			if (o.contexts != null && o.contexts.exists(c.id)) return o.contexts.get(c.id);
			o = o.parent;
		}
		if (!c.hasDefault) throw new GraphError("context not provided and without a default (give it one, null included: context(null))");
		return c.defaultValue;
	}

	public static function setContext<T>(c:Context<T>, value:T) {
		var o = current;
		if (o == null) throw new GraphError("setContext outside an owner (a root, a component)");
		if (o.contexts == null) o.contexts = new Map();
		o.contexts.set(c.id, value);
	}

	public static function provide<T, R>(c:Context<T>, value:T, fn:Void->R):R {
		var o = new Owner(current);
		o.contexts = [c.id => (value : Dynamic)];
		return Node.within(o, Node.observer, fn);
	}
}

// a misuse of the graph (a write in an owned scope, a context not found)
class GraphError extends haxe.Exception {}
