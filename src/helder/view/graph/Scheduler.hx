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

	// (each queue's spare: the queue taken by swapping them, nothing copied)
	static var writes:Array<Node<Dynamic>> = [];
	static var writesTaken:Array<Node<Dynamic>> = [];
	static var landings:Array<Node<Dynamic>> = [];
	static var landingsTaken:Array<Node<Dynamic>> = [];
	static final memos:Array<Node<Dynamic>> = [];
	static final renders:Array<Node<Dynamic>> = [];
	static final effects:Array<Node<Dynamic>> = [];
	// (applies on the screen: effects whose run joined no transaction)
	static var applies:Array<Node<Dynamic>> = [];
	static var appliesTaken:Array<Node<Dynamic>> = [];
	// (the transactions done with, nothing pointing at them: reused)
	static final spareTx:Array<Tx> = [];
	// (the applies being run, a list per nesting)
	static final batches:Array<Array<Node<Dynamic>>> = [];
	static var batchDepth = 0;
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

	public static function flush()
		if (!running) run();

	static function run() {
		running = true;
		asked = false;
		// (the loop in a function of its own: locals inside a try are boxed)
		try loop() catch (e:Dynamic) resetThrowing(e);
		running = false;
		world = null;
		if (hasFailure) rethrow();
	}

	// (a throw out of the flush: the queues emptied first)
	static function resetThrowing(e:Dynamic) {
		reset();
		throw e;
	}

	// (the first error a flush met, after it ran what it could)
	static function rethrow() {
		var e = failure;
		reset();
		throw e;
	}

	static function loop() {
		while (writes.length > 0 || landings.length > 0 || memos.length > 0 || renders.length > 0 || effects.length > 0
			|| applies.length > 0) {
			if (landings.length > 0) {
				var ls = landings;
				landings = landingsTaken;
				landingsTaken = ls;
				for (n in ls) {
					var tx = n.pendingIn != null ? n.pendingIn.find() : null;
					if (tx == null || tx.committed) tx = newTx();
					n.pendingIn = null;
					world = tx;
					n.land();
					// (what waits in it runs again in its world: a mount over what it staged can show now)
					var bs = tx.find().blocked;
					for (i in 0...bs.length)
						if (i < bs.length && !bs[i].disposed) bs[i].mark(Node.DIRTY);
					drain();
					settle();
				}
				ls.resize(0);
			}
			if (writes.length > 0) {
				ticks++;
				world = newTx();
				var ws = writes;
				writes = writesTaken;
				writesTaken = ws;
				for (n in ws)
					n.stageWrite(world);
				ws.resize(0);
				drain();
				settle();
			}
			// (what is stale outside a transaction: verdict readers after a commit)
			drain();
			if (applies.length > 0) {
				// (those a commit has not applied since)
				var as = applies;
				applies = appliesTaken;
				appliesTaken = as;
				var batch = takeBatch();
				for (n in as)
					if (n.toApply) batch.push(n);
				as.resize(0);
				runApplies(batch);
				giveBatch(batch);
			}
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

	// (parents first: a parent running again disposes its old children before
	// they run; each batch the queue's nodes so far, sorted in place by depth
	// (stable: those of one depth in the order they were queued), then run,
	// those it queues the next batch)
	static function runQueue(q:Array<Node<Dynamic>>) {
		var start = 0;
		try {
			while (start < q.length) {
				var end = q.length;
				sortByDepth(q, start, end);
				for (i in start...end) {
					var n = q[i];
					n.queued = false;
					n.updateIfNecessary();
				}
				start = end;
			}
		} catch (e:Dynamic) {
			q.resize(0);
			throw e;
		}
		q.resize(0);
	}

	// (an insertion sort: a queue is mostly in order already)
	static function sortByDepth(q:Array<Node<Dynamic>>, start:Int, end:Int) {
		for (i in start + 1...end) {
			var n = q[i];
			if (q[i - 1].depth <= n.depth) continue;
			var j = i;
			while (j > start && q[j - 1].depth > n.depth) {
				q[j] = q[j - 1];
				j--;
			}
			q[j] = n;
		}
	}

	// (a transaction: a spare one, else new)
	static function newTx():Tx
		return spareTx.length > 0 ? spareTx.pop() : new Tx();

	// (a list for applies to run: reused, one per nesting)
	static function takeBatch():Array<Node<Dynamic>> {
		if (batchDepth == batches.length) batches.push([]);
		return batches[batchDepth++];
	}

	static function giveBatch(b:Array<Node<Dynamic>>) {
		b.resize(0);
		batchDepth--;
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
		// (one nothing else points at: reused)
		if (!t.shared && t.into == null) {
			t.reset();
			spareTx.push(t);
		}
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
		batchDepth = 0;
		for (b in batches)
			b.resize(0);
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
