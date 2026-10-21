import Compiler;
import Protocol;
import js.Syntax;
import js.html.Worker;
import js.lib.Promise;

// The page's side of the compiler's worker (CompilerWorker): requests as
// promises. A request a newer one replaced resolves to null.
class CompilerClient {
	public var onProgress:(what:String, loaded:Int, total:Int) -> Void = (_, _, _) -> {};
	public var onFiles:Array<Array<Dynamic>>->Void = _ -> {};
	public var onState:(state:String, text:String) -> Void = (_, _) -> {};
	public var state(default, null) = "asleep";

	var worker:Worker;
	var ready:Null<Promise<Bool>>;
	final pending = new Map<Int, {resolve:Dynamic->Void, reject:Dynamic->Void}>();
	final loads = new Map<String, {loaded:Int, total:Int}>();
	var nextId = 1;

	public function new() {}

	function set(s:String, text:String) {
		state = s;
		onState(s, text);
	}

	// the compiler this browser runs: reactor.wasm uses exception handling
	// with exnref (Chrome and Edge 137+, Firefox 131+, Safari 18.4+),
	// reactor-legacy.wasm the legacy instructions (Chrome and Edge 95+,
	// Firefox 100+, Safari 15.2+); each detected with a tiny module (a
	// function with an exnref local and a try_table; one with try and
	// catch_all), as site/client/Playground.hx does; ?eh=legacy or ?eh=exnref
	// forces one (tests). null: neither.
	public static final module:Null<String> = {
		var exnref = validates([0, 97, 115, 109, 1, 0, 0, 0, 1, 4, 1, 0x60, 0, 0, 3, 2, 1, 0, 10, 10, 1, 8, 1, 1, 0x69, 0x1f, 0x40, 0, 0x0b, 0x0b]);
		var legacy = validates([0, 97, 115, 109, 1, 0, 0, 0, 1, 4, 1, 0x60, 0, 0, 3, 2, 1, 0, 10, 8, 1, 6, 0, 0x06, 0x40, 0x19, 0x0b, 0x0b]);
		switch new js.html.URLSearchParams(js.Browser.window.location.search).get("eh") {
			case "legacy": legacy ? "reactor-legacy.wasm" : null;
			case "exnref": exnref ? "reactor.wasm" : null;
			case _: exnref ? "reactor.wasm" : legacy ? "reactor-legacy.wasm" : null;
		}
	};

	// a phone, or a machine with 4 GB or less: one compiler at a time (a ui
	// program's takes about 460 MB)
	public static final lowMemory:Bool = {
		var memory:Null<Float> = (cast js.Browser.navigator).deviceMemory;
		(memory != null && memory <= 4) || js.Browser.window.matchMedia("(pointer: coarse)").matches;
	};

	static function validates(bytes:Array<Int>):Bool
		return try js.lib.WebAssembly.validate(new js.lib.Uint8Array(bytes).buffer) catch (_:Dynamic) false;

	public static function supported():Bool
		return module != null;

	public function wake():Promise<Bool> {
		if (ready != null) return ready;
		if (!supported()) {
			set("asleep", "this browser cannot run the compiler");
			return ready = Promise.reject("This browser lacks WebAssembly exception handling: Chrome 95+, Firefox 100+ or Safari 15.2+ run the compiler.");
		}
		set("loading", "waking up…");
		worker = new Worker("worker.js");
		worker.onmessage = (e:{data:Reply}) -> {
			var m = e.data;
			switch m.type {
				case Progress:
					loads.set(m.what, {loaded: m.loaded, total: m.total});
					var loaded = 0, total = 0;
					for (l in loads) {
						loaded += l.loaded;
						total += Std.int(Math.max(l.total, l.loaded));
					}
					if (state == "loading") set("loading", 'downloading ${Math.round(loaded / 104857.6) / 10} / ${Math.round(total / 104857.6) / 10} MB');
					onProgress(m.what, loaded, total);
				case Files:
					onFiles(m.files);
				case Ready:
					settle(0, true);
				case Built | Displayed:
					settle(m.id, m);
				case Superseded:
					settle(m.id, null);
				case Failed:
					var p = pending.get(m.id ?? 0) ?? pending.get(0);
					if (p != null) {
						pending.remove(m.id ?? 0);
						p.reject(m.message);
					}
			}
		}
		ready = new Promise((resolve, reject) -> pending.set(0, {resolve: resolve, reject: reject})).then(_ -> {
			set("ready", "compiler ready · resident · 100% wasm");
			true;
		}, e -> {
			set("asleep", "the compiler failed to start");
			throw e;
		});
		worker.postMessage({type: Init, module: module, keep: lowMemory ? 1 : 2});
		return ready;
	}

	function settle(id:Int, v:Dynamic) {
		var p = pending.get(id);
		if (p == null) return;
		pending.remove(id);
		p.resolve(v);
	}

	function send(r:Request):Promise<Dynamic> {
		return wake().then(_ -> {
			var id = r.id = nextId++;
			var p = new Promise((resolve, reject) -> pending.set(id, {resolve: resolve, reject: reject}));
			worker.postMessage(r);
			p;
		});
	}

	// a build: null when a newer build of the same program replaced it
	public function build(e:Example, target:String, dev:Bool, edits:Edits):Promise<Null<Reply>>
		return send({type: Build, example: e, target: target, dev: dev, edits: edits}).then((r:Dynamic) -> (r : Null<Reply>));

	// a display request's JSON result (null: none, or replaced by a newer one)
	public function display(e:Example, method:String, file:String, offset:Int, edits:Edits, ?extra:Dynamic):Promise<Null<Dynamic>>
		return send({type: Display, example: e, method: method, file: file, offset: offset, extra: extra, edits: edits}).then((r:Null<Reply>) -> r?.json);
}
