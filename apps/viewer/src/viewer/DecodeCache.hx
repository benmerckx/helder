package viewer;

import viewer.Decode.Decoded;

// Decoded images kept by path within a memory budget. want(paths) names
// what is needed, nearest first (the image shown, then its neighbours):
// the missing ones are decoded in that order, a few at a time (decode:
// helder.jobs in the app, at once in tests), and when the kept pixels pass
// the budget the ones farthest from the image shown go first (those no
// longer wanted before them); the image shown is never evicted. drop
// forgets a file (changed on disk). side is the side decodes are asked at
// (a JPEG decoded smaller, at the size shown: 0 all of it); refine decodes
// the one shown again whole when the view needs its pixels (a zoom), the
// smaller one shown meanwhile.
class DecodeCache {
	public var budget:Float;
	// decodes at a time
	public var parallel = 2;
	// the decoded pixels' bytes kept
	public var used(default, null) = 0.0;
	// called when a decode lands (the shell redraws)
	public var onReady:Null<String->Void>;

	final decode:(path:String, side:Int, done:Decoded->Void) -> Void;
	// the side new decodes are asked at (0: whole)
	public var side = 0;
	final entries = new Map<String, Entry>();
	var order:Array<String> = [];
	var running = 0;

	public function new(decode:(path:String, side:Int, done:Decoded->Void) -> Void, budget = 768 * 1048576.0) {
		this.decode = decode;
		this.budget = budget;
	}

	// its decode, when it landed (null: not yet, or not wanted)
	public function get(path:String):Null<Decoded> {
		var e = entries.get(path);
		return e == null ? null : e.decoded;
	}

	public function has(path:String):Bool
		return entries.exists(path);

	public function keys():Array<String>
		return [for (k in entries.keys()) k];

	// what is needed now, nearest first
	public function want(paths:Array<String>) {
		order = paths.copy();
		// (those evicted while wanted may come back now: the order is another)
		for (e in [for (e in entries) e])
			if (e.evicted) entries.remove(e.path);
		for (p in paths)
			if (!entries.exists(p)) entries.set(p, new Entry(p));
		evict();
		pump();
	}

	// path's decode again at a larger side (0: whole), when it was decoded
	// smaller than that (true: one started)
	public function refine(path:String, side:Int):Bool {
		var e = entries.get(path);
		if (e == null || e.decoded == null || e.refining || e.side == 0 || (side > 0 && side <= e.side)) return false;
		var d0 = e.decoded;
		if (d0.pixelsWidth >= d0.width) return false;
		e.refining = true;
		decode(path, side, d -> {
			e.refining = false;
			if (e.dropped || entries.get(path) != e || d.error != null) {
				Decode.release(d);
				return;
			}
			Decode.release(e.decoded);
			used -= e.bytes;
			e.decoded = d;
			e.side = side;
			e.bytes = Decode.bytesOf(d);
			used += e.bytes;
			evict();
			if (onReady != null && entries.get(path) == e) onReady(path);
		});
		return true;
	}

	public function drop(path:String) {
		var e = entries.get(path);
		if (e == null) return;
		entries.remove(path);
		if (e.decoded != null) {
			used -= e.bytes;
			// (its pixels off the heap: freed now)
			Decode.release(e.decoded);
			e.decoded = null;
		}
		// (a decode under way lands in an entry no longer kept: ignored)
		e.dropped = true;
	}

	public function clear()
		for (k in keys())
			drop(k);

	// (the next wanted ones not started, while there is room)
	function pump() {
		for (p in order) {
			if (running >= parallel) return;
			var e = entries.get(p);
			if (e == null || e.started) continue;
			e.started = true;
			e.running = true;
			running++;
			e.side = side;
			decode(p, side, d -> {
				running--;
				e.running = false;
				if (!e.dropped) {
					e.decoded = d;
					e.bytes = Decode.bytesOf(d);
					used += e.bytes;
					evict();
					if (onReady != null && entries.get(p) == e) onReady(p);
				}
				pump();
			});
		}
	}

	// (over the budget: the farthest decoded, not the one shown; the
	// unwanted first, then from the end of the order)
	function evict() {
		while (used > budget) {
			var victim:Null<Entry> = null, rank = -1;
			for (e in entries) {
				if (e.decoded == null) continue;
				var r = order.indexOf(e.path);
				if (r == 0) continue;
				var k = r < 0 ? 1 << 30 : r;
				if (k > rank) {
					rank = k;
					victim = e;
				}
			}
			if (victim == null) return;
			drop(victim.path);
			// (still wanted: not decoded again until the order changes, so
			// that a budget too small for every neighbour does not loop)
			if (rank < 1 << 30) {
				var tomb = new Entry(victim.path);
				tomb.started = tomb.evicted = true;
				entries.set(victim.path, tomb);
			}
		}
		// (the not-yet-started that are no longer wanted)
		for (e in [for (e in entries) e])
			if (!e.started && order.indexOf(e.path) < 0) entries.remove(e.path);
	}
}

private class Entry {
	public final path:String;
	public var started = false;
	public var running = false;
	public var refining = false;
	public var side = 0;
	public var evicted = false;
	public var dropped = false;
	public var decoded:Null<Decoded> = null;
	public var bytes = 0.0;

	public function new(path:String)
		this.path = path;
}
