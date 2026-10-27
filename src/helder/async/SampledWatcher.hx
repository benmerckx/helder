package helder.async;

import haxe.io.Bytes;

// A Watcher of a given set of files and directories (what the last build
// read), polled as esbuild's watcher polls (pkg/api/watcher.go): every
// `interval` seconds it checks the 16 paths that changed last, then the
// next slice of all paths in a shuffled order, max(64, ceil(n / 20)) of
// them, so that a large set is covered about every 20 ticks (2 s) and the
// file being edited is seen within a tick. A path found changed joins the
// recent ones (the oldest drops out).
//
// A file's check is its stamp, taken when it is watched: natively its mtime
// and ctime to the nanosecond and its size (hxmc.NativeSys.statTimes, one
// call), on Eval its inode, size, mtime and mode (stat: seconds). When the
// mtime is too recent to tell a later edit from it (within 10 ms natively,
// the file system's clock being coarser than the wall clock; 2 s on Eval),
// its content too. A directory's check is its sorted entries: a file added
// or removed there. A batch comes `debounce` seconds after the first
// change, with what else changed among the recent paths by then.
//
//   var w = new SampledWatcher();
//   w.watch(files, dirs);          // after each build: the set replaced
//   var changed = w.next();
class SampledWatcher implements Watcher {
	static inline var RECENT = 16;
	static inline var MIN_PER_TICK = 64;
	static inline var TICKS_PER_PASS = 20;

	final interval:Float;
	final debounce:Float;
	var entries = new Map<String, Entry>();
	var recent:Array<String> = [];
	var queue:Array<String> = [];
	var perTick = MIN_PER_TICK;
	var closed = false;

	public function new(interval = 0.1, debounce = 0.02) {
		this.interval = interval;
		this.debounce = debounce;
	}

	// the set replaced: these files and directories, as they are now; a
	// path watched before keeps its state (taken when it was first watched,
	// or when next() reported it): a change while the build ran is seen next
	public function watch(files:Array<String>, dirs:Array<String>) {
		var old = entries;
		entries = new Map();
		function add(p:String, dir:Bool) {
			if (entries.exists(p)) return;
			var o = old.get(p);
			entries.set(p, o != null && o.dir == dir ? o : Entry.of(p, dir));
		}
		for (d in dirs) add(d, true);
		for (f in files) add(f, false);
		recent = [for (r in recent) if (entries.exists(r)) r];
		queue = [];
	}

	public function paths():Int
		return Lambda.count(entries);

	@:coroutine public function next():Array<String> {
		while (true) {
			if (closed) return [];
			Async.delay(interval);
			var dirty = tick();
			if (dirty == null) continue;
			// (editors saving several files: what else changed by then, among the recent ones)
			if (debounce > 0) Async.delay(debounce);
			var out = [dirty];
			for (r in recent) if (r != dirty && entries.get(r).changed(r)) out.push(r);
			for (p in out) entries.set(p, Entry.of(p, entries.get(p).dir));
			return out;
		}
	}

	// one tick: the recent paths, then a slice of the rest; the first changed one, else null
	public function tick():Null<String> {
		if (queue.length == 0) {
			queue = [for (p in entries.keys()) p];
			for (i in 0...queue.length - 1) {
				var j = i + Std.random(queue.length - i);
				var t = queue[i];
				queue[i] = queue[j];
				queue[j] = t;
			}
			perTick = Std.int(Math.max(MIN_PER_TICK, Math.ceil(queue.length / TICKS_PER_PASS)));
		}
		for (i in 0...recent.length) {
			var p = recent[i];
			if (entries.get(p).changed(p)) {
				recent.splice(i, 1);
				recent.push(p);
				return p;
			}
		}
		var n = queue.length < perTick ? queue.length : perTick;
		for (_ in 0...n) {
			var p = queue.pop();
			var e = entries.get(p);
			if (e != null && e.changed(p)) {
				recent.remove(p);
				recent.push(p);
				if (recent.length > RECENT) recent.shift();
				return p;
			}
		}
		return null;
	}

	public function close()
		closed = true;
}

private class Entry {
	// (how long ago an mtime must be for its stamp to be trusted alone)
	static inline var TRUST = #if (target.name == "hxmc") 0.01 #else 2.0 #end;

	public final dir:Bool;
	// a file's stamp (null: missing), its content when the stamp cannot be trusted alone; a directory's entries
	final stamp:Null<Array<Float>>;
	final content:Null<Bytes>;
	final entries:String;

	function new(dir, stamp, content, entries = "") {
		this.dir = dir;
		this.stamp = stamp;
		this.content = content;
		this.entries = entries;
	}

	public static function of(path:String, dir:Bool):Entry {
		if (dir) return new Entry(true, null, null, listing(path));
		var t = stampOf(path);
		if (t == null) return new Entry(false, null, null);
		var recent = Sys.time() - mtime(t) < TRUST;
		return new Entry(false, t, recent ? (try sys.io.File.getBytes(path) catch (_:Dynamic) null) : null);
	}

	// natively: mtime s, ns, ctime s, ns, size; Eval: inode, size, mtime (ms), mode
	static function stampOf(path:String):Null<Array<Float>> {
		#if (target.name == "hxmc")
		var t = hxmc.NativeSys.statTimes(path);
		return t == null ? null : t.slice(2);
		#else
		var s = try sys.FileSystem.stat(path) catch (_:Dynamic) null;
		return s == null ? null : [s.ino, s.size, s.mtime.getTime(), s.mode];
		#end
	}

	// (seconds since the epoch)
	static inline function mtime(t:Array<Float>):Float
		return #if (target.name == "hxmc") t[0] + t[1] / 1e9 #else t[2] / 1000 #end;

	static function listing(path:String):String {
		var names = try sys.FileSystem.readDirectory(path) catch (_:Dynamic) return "-";
		names.sort(Reflect.compare);
		return names.join("\n");
	}

	public function changed(path:String):Bool {
		if (dir) return listing(path) != entries;
		var t = stampOf(path);
		if (t == null || stamp == null) return t != stamp;
		for (i in 0...t.length)
			if (t[i] != stamp[i]) return true;
		if (content == null) return false;
		// (the same stamp, too recent at the build to be trusted alone: the content)
		var now = try sys.io.File.getBytes(path) catch (_:Dynamic) return true;
		return now.compare(content) != 0;
	}
}
