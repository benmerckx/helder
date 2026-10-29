package helder.view.graph;

// When writes are committed and effects run (DESIGN.md 2, Writes and
// commits; Holds). A write queues its node; a flush stages the pending
// writes in a transaction, runs what they make stale for it (owned memos,
// then render effects' computes, then the others', parents first), and
// settles it: committed when nothing it renders waits (its effects'
// applies then, render effects first), else parked until its async lands.
// An async answer lands into the transaction that asked, the same way. A
// flush comes from flush(), or, after a write outside one, from `later`
// (helder.async's loop: when the task running ends, as Solid 2's
// microtask; unset, nothing flushes until flush() is called).
@:allow(helder.view.graph)
class Scheduler {
	// how a flush is asked for after a write (the loop's: at the end of its task)
	public static var later:Null<(Void->Void)->Void> = null;

	static final writes:Array<Node<Dynamic>> = [];
	static final landings:Array<Node<Dynamic>> = [];
	static final memos:Array<Node<Dynamic>> = [];
	static final renders:Array<Node<Dynamic>> = [];
	static final effects:Array<Node<Dynamic>> = [];
	// (applies on the screen: effects whose run joined no transaction)
	static final applies:Array<Node<Dynamic>> = [];
	// (transactions parked: waiting on async something they render reads)
	static final held:Array<Tx> = [];
	// the transaction whose computations run now (null: the screen)
	static var world:Null<Tx> = null;
	static var running = false;
	// (inside flush(fn): its writes wait for its own flush)
	static var holding = 0;
	static var asked = false;
	static var failure:Null<Dynamic> = null;
	static var hasFailure = false;
	// (commits made: an unowned memo's freshness)
	static var ticks = 0;

	public static function flush() {
		if (running) return;
		running = true;
		asked = false;
		try {
			while (writes.length > 0 || landings.length > 0 || memos.length > 0 || renders.length > 0 || effects.length > 0
				|| applies.length > 0) {
				if (landings.length > 0) {
					var ls = landings.copy();
					landings.resize(0);
					for (n in ls) {
						var tx = n.pendingIn != null ? n.pendingIn.find() : null;
						if (tx == null || tx.committed) tx = new Tx();
						n.pendingIn = null;
						world = tx;
						n.land();
						// (what waits in it runs again in its world: a mount over what it staged can show now)
						for (b in tx.find().blocked.copy())
							if (!b.disposed) b.mark(Node.DIRTY);
						drain();
						settle();
					}
				}
				if (writes.length > 0) {
					ticks++;
					world = new Tx();
					var ws = writes.copy();
					writes.resize(0);
					for (n in ws)
						n.stageWrite(world);
					drain();
					settle();
				}
				// (what is stale outside a transaction: verdict readers after a commit)
				drain();
				if (applies.length > 0) {
					// (those a commit has not applied since)
					var as = [for (n in applies) if (n.toApply) n];
					applies.resize(0);
					runApplies(as);
				}
			}
		} catch (e:Dynamic) {
			reset();
			throw e;
		}
		running = false;
		world = null;
		if (hasFailure) {
			var e = failure;
			reset();
			throw e;
		}
	}

	public static function flushWith<T>(fn:Void->T):T {
		holding++;
		var r = try fn() catch (e:Dynamic) {
			holding--;
			throw e;
		}
		holding--;
		flush();
		return r;
	}

	static function drain() {
		runQueue(memos);
		runQueue(renders);
		runQueue(effects);
	}

	// (parents first: a parent running again disposes its old children before they run)
	static function runQueue(q:Array<Node<Dynamic>>) {
		while (q.length > 0) {
			var batch = q.copy();
			q.resize(0);
			haxe.ds.ArraySort.sort(batch, (a, b) -> a.depth - b.depth);
			for (n in batch) {
				n.queued = false;
				n.updateIfNecessary();
			}
		}
	}

	// (render effects' applies before the others')
	static function runApplies(ns:Array<Node<Dynamic>>) {
		for (n in ns)
			if (n.kind == Node.RENDER && !n.disposed) n.runApply();
		for (n in ns)
			if (n.kind != Node.RENDER && !n.disposed) n.runApply();
	}

	// (the world's transaction: parked while a render effect waits in it, else committed)
	static function settle() {
		var t = world.find();
		world = null;
		if (t.blocked.length > 0) {
			if (!held.contains(t)) held.push(t);
			// (its readers, served the screen, see it held now: isPending)
			for (n in t.readers)
				if (!n.disposed && !t.effects.contains(n)) n.mark(Node.DIRTY);
			return;
		}
		held.remove(t);
		commit(t);
	}

	static function commit(t:Tx) {
		t.committed = true;
		for (n in t.nodes)
			if (n.stagedIn != null && n.stagedIn.find() == t) n.commitStaged();
		for (n in t.effects)
			n.toApply = false;
		runApplies(t.effects);
		// (its frame readers, served the committed values, run again on the screen)
		for (n in t.readers)
			if (!n.disposed && !t.effects.contains(n)) n.mark(Node.DIRTY);
	}

	// the world joins other (a computation read what other stages): one transaction
	static function join(other:Tx):Tx {
		if (world == null) return other.find();
		world = Tx.merge(world, other);
		return world;
	}

	// (b merged into a: a parked if either was)
	static function merged(a:Tx, b:Tx) {
		if (held.remove(b) && !held.contains(a)) held.push(a);
	}

	static function enqueueWrite(n:Node<Dynamic>) {
		writes.push(n);
		ask();
	}

	static function landing(n:Node<Dynamic>) {
		landings.push(n);
		ask();
	}

	// a stale computation: to run
	static function enqueue(n:Node<Dynamic>) {
		if (n.queued) return;
		n.queued = true;
		(n.kind == Node.RENDER ? renders : n.kind == Node.EFFECT ? effects : memos).push(n);
		ask();
	}

	// an effect computed on the screen: its apply to run
	static function enqueueApply(n:Node<Dynamic>) {
		if (n.toApply) return;
		n.toApply = true;
		applies.push(n);
		ask();
	}

	// an error in a cleanup or an apply: in a flush, thrown at its end; else now
	static function report(e:Dynamic) {
		if (running) failed(e) else throw e;
	}

	// (an effect's error nothing handled: the flush throws it, after the others ran)
	static function failed(e:Dynamic) {
		if (hasFailure) return;
		failure = e;
		hasFailure = true;
	}

	static function ask() {
		if (running || holding > 0 || asked || later == null) return;
		asked = true;
		later(flush);
	}

	static function reset() {
		running = false;
		world = null;
		for (q in [writes, landings, memos, renders, effects, applies]) {
			for (n in q) {
				n.queued = false;
				n.toApply = false;
				n.hasPending = false;
				n.state = Node.CLEAN;
			}
			q.resize(0);
		}
		failure = null;
		hasFailure = false;
	}
}
