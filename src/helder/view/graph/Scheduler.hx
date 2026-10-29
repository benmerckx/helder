package helder.view.graph;

// When writes are committed and effects run (DESIGN.md 2, Writes and
// commits; 6, 1): a write queues its node; a flush commits every pending
// write, runs the computes of the effects that are now stale (render
// effects first), then their applies, again until nothing is left. A
// flush comes from flush(), or, after a write outside one, from `later`
// (helder.async's loop: when the task running ends, as Solid 2's
// microtask; unset, nothing flushes until flush() is called).
@:allow(helder.view.graph)
class Scheduler {
	// how a flush is asked for after a write (the loop's: at the end of its task)
	public static var later:Null<(Void->Void)->Void> = null;

	static final writes:Array<Node<Dynamic>> = [];
	static final renders:Array<Node<Dynamic>> = [];
	static final effects:Array<Node<Dynamic>> = [];
	static final applies:Array<Node<Dynamic>> = [];
	static var running = false;
	// (inside flush(fn): its writes wait for its own flush)
	static var holding = 0;
	static var asked = false;
	static var failure:Null<Dynamic> = null;
	static var hasFailure = false;

	public static function flush() {
		if (running) return;
		running = true;
		asked = false;
		try {
			while (writes.length > 0 || renders.length > 0 || effects.length > 0 || applies.length > 0) {
				if (writes.length > 0) {
					var ws = writes.copy();
					writes.resize(0);
					for (n in ws)
						n.commit();
				}
				runQueue(renders);
				runQueue(effects);
				if (applies.length > 0) {
					// (render effects' applies before the others')
					var as = applies.copy();
					applies.resize(0);
					for (n in as)
						if (n.kind == Node.RENDER && n.toApply) n.runApply();
					for (n in as)
						if (n.toApply) n.runApply();
				}
			}
		} catch (e:Dynamic) {
			reset();
			throw e;
		}
		running = false;
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

	static function runQueue(q:Array<Node<Dynamic>>) {
		var i = 0;
		while (i < q.length) {
			var n = q[i++];
			n.queued = false;
			n.updateIfNecessary();
		}
		q.resize(0);
	}

	static function enqueueWrite(n:Node<Dynamic>) {
		writes.push(n);
		ask();
	}

	// a stale effect: its compute to run
	static function enqueue(n:Node<Dynamic>) {
		if (n.queued) return;
		n.queued = true;
		(n.kind == Node.RENDER ? renders : effects).push(n);
		ask();
	}

	// an effect computed: its apply to run
	static function enqueueApply(n:Node<Dynamic>) {
		if (n.toApply) return;
		n.toApply = true;
		applies.push(n);
		ask();
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
		for (q in [writes, renders, effects, applies]) {
			for (n in q) {
				n.queued = false;
				n.toApply = false;
				n.hasPending = false;
			}
			q.resize(0);
		}
		failure = null;
		hasFailure = false;
	}
}
