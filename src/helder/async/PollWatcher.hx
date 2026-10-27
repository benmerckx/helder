package helder.async;

// A Watcher by scanning: each directory's files, recursively, every
// `interval` seconds, by modification time and size (natively to the
// nanosecond, hxmc.NativeSys.statTimes, one call; on Eval stat's seconds),
// and the content's hash for a small file whose mtime is too recent to tell
// a later edit from it (natively within 10 ms, the file system's clock
// being coarser than the wall clock; on Eval within 3 s). A batch comes once
// nothing changed for `debounce` seconds.
//
//   var w = new PollWatcher(["src", "assets"]);
//   while (true) for (path in w.next()) trace(path);
class PollWatcher implements Watcher {
	static inline var RECENT_BYTES = 1 << 20;
	// (how long ago an mtime must be for the key to be trusted alone)
	static inline var TRUST = #if (target.name == "hxmc") 0.01 #else 3.0 #end;

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
			if (sys.FileSystem.isDirectory(p)) walk(p, out) else {
				#if (target.name == "hxmc")
				var t = hxmc.NativeSys.statTimes(p);
				if (t == null) continue;
				var key = Std.int(t[2]) + "." + Std.int(t[3]) + " " + t[6], mtime = t[2] + t[3] / 1e9, size = t[6];
				#else
				var s = try sys.FileSystem.stat(p) catch (_:Dynamic) continue;
				var key = s.mtime.getTime() + " " + s.size, mtime = s.mtime.getTime() / 1000, size:Float = s.size;
				#end
				var old = files?.get(p);
				// (the hash kept once the file is no longer recent)
				var hash = size < RECENT_BYTES && Sys.time() - mtime < TRUST ? " " + (try haxe.crypto.Crc32.make(sys.io.File.getBytes(p)) catch (_:Dynamic) 0)
					: old != null && StringTools.startsWith(old, key + " ") ? old.substr(key.length) : "";
				out.set(p, key + hash);
			}
		}
	}
}
