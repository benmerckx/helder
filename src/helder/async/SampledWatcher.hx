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
// A file's check is its stat key (inode, size, mtime, mode), taken when
// it is watched; when its mtime is too recent to tell a later edit from it
// (within 2 s: hxmc's and Eval's stat give seconds), its
// content instead. A directory's check is its sorted entries: a file added
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
	// (an mtime must be 2 s in the past for its stat key to be trusted: Entry.of)

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
	public final dir:Bool;
	// a file's stat key ("" missing), its content when the key cannot be trusted; a directory's entries
	final key:String;
	final content:Null<Bytes>;

	function new(dir, key, content) {
		this.dir = dir;
		this.key = key;
		this.content = content;
	}

	public static function of(path:String, dir:Bool):Entry {
		if (dir) return new Entry(true, listing(path), null);
		var s = try sys.FileSystem.stat(path) catch (_:Dynamic) null;
		if (s == null) return new Entry(false, "", null);
		var k = statKey(s);
		// (2 s: hxmc's stat has seconds)
		var recent = Date.now().getTime() - s.mtime.getTime() < 2000;
		return new Entry(false, k, recent ? (try sys.io.File.getBytes(path) catch (_:Dynamic) null) : null);
	}

	static function statKey(s:sys.FileStat):String
		return s.ino + " " + s.size + " " + s.mtime.getTime() + " " + s.mode;

	static function listing(path:String):String {
		var names = try sys.FileSystem.readDirectory(path) catch (_:Dynamic) return "-";
		names.sort(Reflect.compare);
		return names.join("\n");
	}

	public function changed(path:String):Bool {
		if (dir) return listing(path) != key;
		var s = try sys.FileSystem.stat(path) catch (_:Dynamic) null;
		if (s == null) return key != "";
		if (content == null) return statKey(s) != key;
		// (the key too recent at the build: the content, when the size is the same)
		if (s.size != content.length) return true;
		var now = try sys.io.File.getBytes(path) catch (_:Dynamic) return true;
		return now.compare(content) != 0;
	}
}
