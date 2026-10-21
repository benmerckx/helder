import js.Browser.window;
import js.lib.Promise;

// What the visitor keeps in this browser. Their edits to the examples'
// sources live in IndexedDB (database "universe", store "edits": a file's
// path under /lib/src => {text, at}), saved as they type and given back
// when they come again; the worlds they visited and the targets they went
// native on in localStorage. Without storage (a private window, blocked
// site data) everything works, nothing stays.
class Store {
	static var db:Null<Promise<Dynamic>>;

	static function open():Promise<Dynamic> {
		if (db != null) return db;
		return db = new Promise((resolve, reject) -> {
			try {
				var r:Dynamic = (cast window).indexedDB.open("universe", 1);
				r.onupgradeneeded = () -> r.result.createObjectStore("edits");
				r.onsuccess = () -> resolve(r.result);
				r.onerror = () -> reject(r.error);
			} catch (e:Dynamic) reject(e);
		});
	}

	static function request<T>(mode:String, f:Dynamic->Dynamic):Promise<T> {
		return open().then(d -> new Promise<T>((resolve, reject) -> {
			var r:Dynamic = f(d.transaction("edits", mode).objectStore("edits"));
			r.onsuccess = () -> resolve(r.result);
			r.onerror = () -> reject(r.error);
		}));
	}

	// the edited text of each of the paths that has one
	public static function edits(paths:Array<String>):Promise<Map<String, String>> {
		var out = new Map<String, String>();
		return Promise.all([
			for (p in paths)
				request("readonly", s -> s.get(p)).then((v:Dynamic) -> if (v != null) out.set(p, v.text))
		]).then(_ -> out, _ -> out);
	}

	public static function save(path:String, text:String):Promise<Dynamic>
		return request("readwrite", s -> s.put({text: text, at: Date.now().getTime()}, path)).catchError(_ -> null);

	public static function forget(path:String):Promise<Dynamic>
		return request("readwrite", s -> s.delete(path)).catchError(_ -> null);

	// ---- progress (localStorage) ----

	public static var progress(get, null):{visited:Array<String>, native:Array<String>, counts:haxe.DynamicAccess<Int>};

	static function get_progress() {
		if (progress != null) return progress;
		progress = {visited: [], native: [], counts: {}};
		try {
			var s:Dynamic = haxe.Json.parse(window.localStorage.getItem("universe:v1") ?? "{}");
			if (s.visited != null) progress.visited = s.visited;
			if (s.native != null) progress.native = s.native;
			if (s.counts != null) progress.counts = s.counts;
		} catch (_:Dynamic) {}
		return progress;
	}

	public static function keep()
		try window.localStorage.setItem("universe:v1", haxe.Json.stringify(progress)) catch (_:Dynamic) {}
}
