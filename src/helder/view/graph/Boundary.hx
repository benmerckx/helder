package helder.view.graph;

import helder.view.graph.Awaitable.NotReady;

// The core of `<Loading>` (Graph.loadingBoundary; DESIGN.md 2, Holds,
// Solid 2's F-4 and F-5): armed until it has shown content, it catches
// what is pending under it (its content read directly, a render effect of
// its content that reads a value not ready): no transaction waits for
// that, the boundary shows its fallback until it settles. Once it has
// shown content it is disarmed: what is pending under it is forwarded,
// held like any reader, the content kept.
@:allow(helder.view.graph)
class Boundary extends Owner {
	var armed = true;
	// (an error boundary showing its fallback: its content is behind it)
	var erroring = false;
	// the render effects of its content it caught, waiting
	final waiting:Array<Node<Dynamic>> = [];
	// (a change in what it caught: its output reads it to run again)
	final version:Node<Int>;

	function new(parent:Null<Owner>) {
		super(parent);
		version = Node.signal(0, {ownedWrite: true});
	}

	// the armed boundary nearest above n, if any (a disarmed one first: none, it forwards)
	static function catching(n:Node<Dynamic>):Null<Boundary> {
		var o = n.parent;
		while (o != null) {
			if (o is Boundary) {
				var b:Boundary = cast o;
				return b.armed ? b : null;
			}
			o = o.parent;
		}
		return null;
	}

	// (the effects of its content whose applies wait for its reveal)
	final held:Array<Node<Dynamic>> = [];

	// the boundary above n that shows its fallback, if any: n's content is behind it
	static function hiding(n:Node<Dynamic>):Null<Boundary> {
		var o = n.parent;
		while (o != null) {
			if (o is Boundary) {
				var b:Boundary = cast o;
				if ((b.armed && b.waiting.length > 0) || b.erroring) return b;
			}
			o = o.parent;
		}
		return null;
	}

	function hold(n:Node<Dynamic>)
		if (!held.contains(n)) held.push(n);

	function caught(n:Node<Dynamic>) {
		if (waiting.contains(n)) return;
		waiting.push(n);
		version.update(v -> v + 1);
	}

	function released(n:Node<Dynamic>) {
		if (!waiting.remove(n)) return;
		version.update(v -> v + 1);
		// (revealed: what waited behind the fallback applies)
		if (waiting.length == 0) reveal();
	}

	// (its content shown again: what waited behind the fallback applies)
	function reveal() {
		if (held.length == 0) return;
		var hs = held.copy();
		held.resize(0);
		for (h in hs)
			if (!h.disposed) Scheduler.enqueueApply(h);
	}

	public static function loading<T>(fn:Void->T, fallback:Void->T):Memo<T> {
		var b = new Boundary(Owner.current);
		var slot = new Slot<T>(Owner.current);
		var content = Node.within(b, null, () -> Node.computed(fn, null, false));
		var output = Node.computed(() -> {
			b.version.read();
			if (b.armed && b.waiting.length > 0) return slot.show(fallback);
			// (caught, the read joined nothing: the fallback derives from no hold)
			var run = Node.runner, world = run.world, joined = run.joined;
			var v = try content.read() catch (e:NotReady) {
				if (!b.armed) throw e;
				run.world = world;
				run.joined = joined;
				return slot.show(fallback);
			} catch (e:Dynamic) {
				// (an error is an answer: it ends the first wait as a value does)
				b.armed = false;
				slot.hide();
				throw e;
			}
			// (content shown: disarmed)
			if (b.waiting.length == 0) b.armed = false;
			slot.hide();
			v;
		}, null, false);
		output.catcher = true;
		return new Memo(output);
	}

	// the core of `<Errored>` (Solid 2's F-12): an error thrown under it
	// (its content's, a render effect's) shows fallback(error, reset); a
	// value not ready is not an error, it passes
	public static function errored<T>(fn:Void->T, fallback:(error:Void->Dynamic, reset:Void->Void)->T):Memo<T> {
		var b = new Boundary(Owner.current);
		b.armed = false;
		// (the error shown, set at once: the output reads it again; one from its
		// content's own value goes when the content has a value again, one from
		// an effect under it stays until reset)
		var failure:Dynamic = null, failed = false, fromContent = false;
		// (what the fallback reads: the error, a new one reaching it without a rebuild)
		var shownError = Node.signal((null : Dynamic), {ownedWrite: true});
		var slot = new Slot<T>(Owner.current);
		var content:Null<Node<T>> = null, output:Null<Node<T>> = null;
		function reset() {
			failure = null;
			failed = false;
			b.erroring = false;
			if (content != null) content.mark(Node.DIRTY);
			if (output != null) output.mark(Node.DIRTY);
		}
		function show(e:Dynamic):T {
			if (slot.showing) shownError.write(e) else shownError.value = e;
			return slot.show(() -> fallback(() -> shownError.read(), reset));
		}
		b.onError = e -> {
			if (failed && failure == e) return;
			failure = e;
			failed = true;
			b.erroring = true;
			// (the content's own error: its output, reading it, says so)
			fromContent = false;
			if (output != null) output.mark(Node.DIRTY);
		};
		content = Node.within(b, null, () -> Node.computed(fn, null, false));
		output = Node.computed(() -> {
			// (the content read first, always: its own error, or its recovery)
			var v:Null<T> = null, waiting = false;
			try v = content.read() catch (e:NotReady) waiting = true catch (e:Dynamic) {
				failure = e;
				failed = true;
				b.erroring = true;
				fromContent = true;
				return show(e);
			}
			// (an effect's error under it: shown until reset)
			if (failed && !fromContent) return show(failure);
			if (waiting) {
				// (a wait is not an answer: the error shown stays)
				if (failed) return show(failure);
				throw NotReady.instance;
			}
			failed = false;
			failure = null;
			if (b.erroring) {
				b.erroring = false;
				b.reveal();
			}
			slot.hide();
			v;
		}, null, false);
		output.catcher = true;
		return new Memo(output);
	}
}

// (a boundary's fallback: a memo made when it shows, in an owner of its own,
// kept while it shows (run again only when what it reads changes),
// disposed when the content shows again)
private class Slot<T> {
	final parent:Null<Owner>;
	var owner:Null<Owner> = null;
	var node:Null<Node<T>> = null;

	public var showing(get, never):Bool;

	inline function get_showing()
		return owner != null;

	public function new(parent)
		this.parent = parent;

	public function show(make:Void->T):T {
		if (owner == null) {
			owner = new Owner(parent);
			node = Node.within(owner, null, () -> Node.computed(make, null, false));
		}
		return node.read();
	}

	public function hide() {
		if (owner == null) return;
		var o = owner;
		owner = null;
		node = null;
		o.dispose();
	}
}
