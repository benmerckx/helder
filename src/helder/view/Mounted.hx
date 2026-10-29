package helder.view;

// What ViewRuntime keeps of what it mounted (each renderer's runtime, N its
// nodes).

// content mounted in an owner of its own: the owner and the nodes put in place
class Shown<N> {
	public final owner:helder.view.graph.Owner;
	public final nodes:Array<N>;

	public function new(owner, nodes) {
		this.owner = owner;
		this.nodes = nodes;
	}
}

// a For's row: its item, what it shows, its cell (by index: a signal of the item)
class Row<N> {
	public var item:Dynamic;
	public final shown:Shown<N>;
	public final cell:Null<helder.view.graph.Node<Dynamic>>;

	public function new(item, shown, cell) {
		this.item = item;
		this.shown = shown;
		this.cell = cell;
	}
}

// a boundary's content (Loading's, Errored's): the nodes in parent before
// anchor that its content put there, in their order (put before anchor or
// before one of them; removed; arranged), to be taken out while its
// fallback shows and put back after
class Capture<N> {
	public final parent:N;
	public final anchor:N;
	public final nodes:Array<N> = [];
	public var attached = true;

	public function new(parent, anchor) {
		this.parent = parent;
		this.anchor = anchor;
	}

	// whether a node put before before is its content's
	public inline function owns(before:Null<N>):Bool
		return before != null && (before == anchor || nodes.indexOf(before) >= 0);

	// n put before before (owns(before))
	public function put(n:N, before:N) {
		nodes.remove(n);
		var i = before == anchor ? nodes.length : nodes.indexOf(before);
		nodes.insert(i, n);
	}

	public inline function remove(n:N)
		nodes.remove(n);

	// ns put in that order before before (owns(before))
	public function arranged(ns:Array<N>, before:N) {
		for (n in ns)
			nodes.remove(n);
		var i = before == anchor ? nodes.length : nodes.indexOf(before);
		for (k in 0...ns.length)
			nodes.insert(i + k, ns[k]);
	}
}

// (Errored's fallback, as its boundary's value)
class FallbackOf {
	public final content:Any;

	public function new(content)
		this.content = content;
}
