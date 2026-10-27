package helder.async;

// A Watcher by scanning: each directory's files, recursively, every
// `interval` seconds, by modification time and size, and the content's hash
// for a small file changed in the last seconds (hxmc's and Eval's stat give
// seconds: an edit that keeps the size within the same second; remove it
// once hxmc's stat has sub-second times). A batch comes once nothing changed
// for `debounce` seconds.
//
//   var w = new PollWatcher(["src", "assets"]);
//   while (true) for (path in w.next()) trace(path);
class PollWatcher implements Watcher {
	static inline var RECENT_BYTES = 1 << 20;

	final dirs:Array<String>;
	final interval:Float;
	final debounce:Float;
	final ignore:Null<String->Bool>;
	var files:Map<String, String>;
	var closed = false;

	// ignore(path): left out (and its directory's contents), e.g. bin/ or .git
	public function new(dirs:Array<String>, interval = 0.2, debounce = 0.1, ?ignore:String->Bool) {
		this.dirs = dirs;
		this.interval = interval;
		this.debounce = debounce;
		this.ignore = ignore;
		files = scan();
	}

	@:coroutine public function next():Array<String> {
		var changed = new Map<String, Bool>();
		var quiet = 0.0;
		while (true) {
			if (closed) return [];
			Async.delay(interval);
			var now = scan();
			var any = false;
			for (p => v in now)
				if (files.get(p) != v) {
					changed.set(p, true);
					any = true;
				}
			for (p in files.keys())
				if (!now.exists(p)) {
					changed.set(p, true);
					any = true;
				}
			files = now;
			if (any) quiet = 0 else if (changed.iterator().hasNext()) {
				quiet += interval;
				if (quiet >= debounce) {
					var out = [for (p in changed.keys()) p];
					out.sort(Reflect.compare);
					return out;
				}
			}
		}
	}

	public function close()
		closed = true;

	// path => "mtime size"
	function scan():Map<String, String> {
		var out = new Map();
		for (d in dirs)
			walk(d, out);
		return out;
	}

	function walk(dir:String, out:Map<String, String>) {
		var names = try sys.FileSystem.readDirectory(dir) catch (_:Dynamic) return;
		for (n in names) {
			var p = dir + "/" + n;
			if (ignore != null && ignore(p)) continue;
			var s = try sys.FileSystem.stat(p) catch (_:Dynamic) continue;
			if (sys.FileSystem.isDirectory(p)) walk(p, out) else {
				var key = s.mtime.getTime() + " " + s.size;
				var old = files?.get(p);
				// (the hash kept once the file is no longer recent)
				var hash = s.size < RECENT_BYTES && Date.now().getTime() - s.mtime.getTime() < 3000 ? " " + (try haxe.crypto.Crc32.make(sys.io.File.getBytes(p)) catch (_:Dynamic) 0)
					: old != null && StringTools.startsWith(old, key + " ") ? old.substr(key.length) : "";
				out.set(p, key + hash);
			}
		}
	}
}
