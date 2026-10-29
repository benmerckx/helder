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

	function caught(n:Node<Dynamic>) {
		if (waiting.contains(n)) return;
		waiting.push(n);
		version.update(v -> v + 1);
	}

	function released(n:Node<Dynamic>) {
		if (!waiting.remove(n)) return;
		version.update(v -> v + 1);
	}

	public static function loading<T>(fn:Void->T, fallback:Void->T):Memo<T> {
		var b = new Boundary(Owner.current);
		var content = Node.within(b, null, () -> Node.computed(fn, null, false));
		return new Memo(Node.computed(() -> {
			b.version.read();
			if (b.armed && b.waiting.length > 0) return fallback();
			var v = try content.read() catch (e:NotReady) {
				if (!b.armed) throw e;
				return fallback();
			}
			// (content shown: disarmed)
			if (b.waiting.length == 0) b.armed = false;
			v;
		}, null, false));
	}

	// the core of `<Errored>` (Solid 2's F-12): an error thrown under it
	// (its content's, a render effect's) shows fallback(error, reset); a
	// value not ready is not an error, it passes
	public static function errored<T>(fn:Void->T, fallback:(error:Void->Dynamic, reset:Void->Void)->T):Memo<T> {
		var b = new Owner(Owner.current);
		var failure = Node.signal((null : Dynamic), {ownedWrite: true});
		var content:Null<Node<T>> = null;
		function reset() {
			failure.write(null);
			if (content != null) content.mark(Node.DIRTY);
		}
		b.onError = e -> failure.write(e);
		content = Node.within(b, null, () -> Node.computed(fn, null, false));
		return new Memo(Node.computed(() -> {
			var e = failure.read();
			if (e != null) return fallback(() -> e, reset);
			try content.read() catch (e:NotReady) throw e catch (e:Dynamic) fallback(() -> e, reset);
		}, null, false));
	}
}
