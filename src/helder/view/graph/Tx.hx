package helder.view.graph;

// A transaction (DESIGN.md 2, Holds): the change one flush makes, or an
// async answer landing, over the nodes it stages. Computations run for it
// read its staged values; a render effect that reads a value not ready
// (no armed boundary above it) blocks it, and it waits, parked, its
// stagings unseen, until nothing it renders waits; then it commits: every
// staging becomes the committed value, its effects' applies run in one
// frame. A computation that reads what another transaction staged joins
// it: the two become one (merged here, find() its survivor).
@:allow(helder.view.graph)
class Tx {
	var into:Null<Tx> = null;
	var committed = false;
	// the nodes it staged
	final nodes:Array<Node<Dynamic>> = [];
	// the effects run for it: their applies at its commit
	final effects:Array<Node<Dynamic>> = [];
	// the render effects waiting on a value not ready: it commits when none is left
	final blocked:Array<Node<Dynamic>> = [];
	// the display-ahead readers (isPending, latest) of what it holds: run again at its commit
	final verdicts:Array<Node<Dynamic>> = [];

	function new() {}

	function find():Tx {
		var t = this;
		while (t.into != null)
			t = t.into;
		return t;
	}

	// a and b one transaction
	static function merge(a:Tx, b:Tx):Tx {
		a = a.find();
		b = b.find();
		if (a == b) return a;
		b.into = a;
		for (n in b.nodes)
			a.nodes.push(n);
		for (n in b.effects)
			if (!a.effects.contains(n)) a.effects.push(n);
		for (n in b.blocked)
			if (!a.blocked.contains(n)) a.blocked.push(n);
		for (n in b.verdicts)
			a.verdicts.push(n);
		Scheduler.merged(a, b);
		return a;
	}

	function block(n:Node<Dynamic>)
		if (!blocked.contains(n)) blocked.push(n);

	function unblock(n:Node<Dynamic>)
		blocked.remove(n);
}
