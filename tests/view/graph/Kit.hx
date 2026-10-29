package view.graph;

import helder.view.graph.Awaitable;
import helder.view.graph.Compute;
import helder.view.graph.Graph.*;

// Async helpers for the ported async tests: Solid's promises, deferreds,
// fetchers and fake timers as Laters answered by hand. An answer lands at
// the next flush (nothing flushes by itself), so "await ...; flush()"
// becomes "answer; flush()".
class Kit {
	// Promise.resolve(v): answered already, lands at the next flush
	public static function resolved<T>(v:T):Later<T> {
		var l = new Later<T>();
		l.resolve(v);
		return l;
	}

	// Promise.reject(e)
	public static function rejected<T>(e:Dynamic):Later<T> {
		var l = new Later<T>();
		l.reject(e);
		return l;
	}

	// a computation that returns a value or an Awaitable, as Solid's
	// `v > 1 ? promise : v` (async only when it returns an Awaitable)
	public static function either<T>(f:Void->Dynamic):Compute<T>
		return cast (_ -> f() : Null<T>->Dynamic);

	// action(function* () { write(); yield promise }) without action: the
	// write held by an async gate that a render effect reads (read: what the
	// write changes); the function returned releases it (the promise resolving)
	public static function hold(write:Void->Void, read:Void->Void):Void->Void {
		var gate = new Later<Bool>();
		var armed = false;
		root(_ -> {
			var g = memo(() -> {
				read();
				armed ? gate : resolved(true);
			});
			renderEffect(() -> g(), _ -> {});
		});
		flush();
		armed = true;
		write();
		flush();
		return () -> gate.resolve(true);
	}

	// the value a read returns, or what it throws
	public static function attempt(f:Void->Dynamic):Dynamic
		return try f() catch (e:haxe.Exception) e.message catch (e:Dynamic) e;
}

// deferredFetcher(compute): fetch(arg) asks, resolveAll() answers every
// open ask with compute(arg); calls counts the asks (vi.fn)
class Fetcher<A, T> {
	final compute:A->T;
	var open:Array<{later:Later<T>, arg:A}> = [];

	public var calls(default, null) = 0;

	public function new(compute:A->T)
		this.compute = compute;

	public function fetch(arg:A):Later<T> {
		calls++;
		var l = new Later<T>();
		open.push({later: l, arg: arg});
		return l;
	}

	public var pending(get, never):Int;

	inline function get_pending()
		return open.length;

	public function resolveAll() {
		var asks = open;
		open = [];
		for (a in asks)
			a.later.resolve(compute(a.arg));
	}

	public function rejectAll(e:Dynamic) {
		var asks = open;
		open = [];
		for (a in asks)
			a.later.reject(e);
	}

	// "await new Promise(r => setTimeout(r, 0))" over immediately resolving
	// promises: answer and flush until nothing is asked any more
	public function settle() {
		flush();
		var rounds = 0;
		while (open.length > 0 && rounds++ < 20) {
			resolveAll();
			flush();
		}
	}
}

// Solid's manual clock: delay(ms, v) answers v when advanceTo passes its
// due time, in due order, a flush after each; text() records each value a
// render effect publishes with the time it landed, frames() groups them.
class Clock {
	public var now(default, null) = 0;

	var timers:Array<{at:Int, seq:Int, run:Void->Void}> = [];
	var seq = 0;

	public final log:Array<String> = [];
	public final when:Array<Int> = [];

	public function new() {}

	public function delay<T>(ms:Int, v:T):Later<T> {
		var l = new Later<T>();
		timers.push({at: now + ms, seq: seq++, run: () -> l.resolve(v)});
		return l;
	}

	public function advanceTo(t:Int) {
		while (true) {
			timers.sort((a, b) -> a.at != b.at ? a.at - b.at : a.seq - b.seq);
			var next = timers[0];
			if (next == null || next.at > t) break;
			timers.shift();
			now = next.at;
			next.run();
			flush();
		}
		now = t;
		flush();
	}

	// a text node: a render effect publishing each value (distinct: each new one)
	public function text(fn:Void->String, distinct = true) {
		var last:Null<String> = null;
		renderEffect(fn, v -> {
			if (distinct && v == last) return;
			last = v;
			log.push(v);
			when.push(now);
		});
	}

	// one entry per time, its values sorted: "t: a | b"
	public function frames():Array<String> {
		var times:Array<Int> = [];
		var byTime = new Map<Int, Array<String>>();
		for (i in 0...log.length) {
			var t = when[i];
			if (!byTime.exists(t)) {
				times.push(t);
				byTime.set(t, []);
			}
			byTime.get(t).push(log[i]);
		}
		return [
			for (t in times) {
				var vs = byTime.get(t);
				vs.sort(Reflect.compare);
				'$t: ${vs.join(" | ")}';
			}
		];
	}
}
