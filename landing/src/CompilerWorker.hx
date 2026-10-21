import Compiler;
import Protocol;
import Wasi;
import js.Syntax;
import js.lib.Promise;
import js.lib.Uint8Array;

// The compiler's worker (worker.js): the resident compiler (Compiler,
// reactor.wasm) over a MemFS of the std and the packages' sources,
// downloaded once; each target's runtime objects downloaded the first time a
// download asks for that target. One compiler per program (the last two
// kept): a server's macros keep state across builds (gfx's shader
// registry), right for the builds of one program, wrong for another's. Requests that arrive while the compiler
// works wait; when it is free, of the waiting builds of one program only the
// last is made and of the display requests only the last answered (the
// others: Superseded), so typing never queues work nobody wants.
class CompilerWorker {
	static var manifest:Manifest;
	// the compiler's module: the one this browser's exception handling runs (CompilerClient.module)
	static var file = "reactor.wasm";
	static var module:js.lib.webassembly.Module;
	static var fs:MemFS;
	static var compilers:Array<{id:String, compiler:Compiler}> = [];
	static var ready:Promise<Bool>;
	static final runtimes = new Map<String, Promise<Bool>>();
	// (the shipped bytes of each edited file: put back when its edit goes)
	static final originals = new Map<String, Uint8Array>();
	static var queue:Array<Request> = [];
	static var pumping = false;

	static function post(r:Reply, ?transfer:Array<Dynamic>)
		Syntax.code("self.postMessage({0}, {1})", r, transfer == null ? [] : transfer);

	static function main() {
		Syntax.code("self.onmessage = {0}", (e:{data:Request}) -> {
			var m = e.data;
			if (m.type == Init) {
				if (m.module != null) file = m.module;
				start().then(_ -> post({type: Ready}), fail.bind(null));
			}
			else {
				queue.push(m);
				if (!pumping) {
					pumping = true;
					// (after every message already sent is in the queue)
					Syntax.code("setTimeout({0}, 0)", pump);
				}
			}
		});
	}

	static function fail(id:Null<Int>, e:Dynamic)
		post({type: Failed, id: id, message: Fail.describe(e)});

	// a file of the site, its download reported as it goes (sizes from the
	// manifest: a server's Content-Length is the compressed size)
	static function load(path:String, what:String):Promise<Uint8Array> {
		return Syntax.code("fetch(new URL({0}, self.location.href))", path).then(r -> {
			if (!r.ok) throw '$path: ${r.status}';
			var total:Int = manifest.sizes.exists(path) ? manifest.sizes[path] : 0;
			var reader = r.body.getReader(), chunks:Array<Uint8Array> = [], loaded = 0, last = 0.0;
			function next():Promise<Uint8Array> {
				return reader.read().then(c -> {
					if (c.done) {
						post({type: Progress, what: what, loaded: loaded, total: loaded});
						var b = new Uint8Array(loaded), at = 0;
						for (x in chunks) {
							b.set(x, at);
							at += x.length;
						}
						return Promise.resolve(b);
					}
					chunks.push(c.value);
					loaded += c.value.length;
					var now:Float = Syntax.code("performance.now()");
					if (now - last > 60) {
						last = now;
						post({type: Progress, what: what, loaded: loaded, total: total});
					}
					return next();
				});
			}
			return next();
		});
	}

	static function start():Promise<Bool> {
		if (ready != null) return ready;
		return ready = Syntax.code("fetch(new URL('manifest.json', self.location.href))").then(r -> r.json()).then(m -> {
			manifest = m;
			Promise.all([load(file, "compiler"), load("std.pack", "std"), load("src.pack", "sources")]);
		}).then((b:Array<Uint8Array>) -> {
			fs = new MemFS();
			fs.mount("/lib", Pack.unpack(b[1]));
			fs.mount("/lib/src", Pack.unpack(b[2]));
			return js.lib.WebAssembly.compile(b[0]).then(m -> {
				module = m;
				// (the first program's compiler started now: its setup off the first build's time)
				compilers.push({id: "", compiler: new Compiler(module, fs)});
				true;
			});
		});
	}

	// the program's compiler: its own, else a new one (the spare one first)
	static function compilerFor(e:Example):Compiler {
		var i = Lambda.findIndex(compilers, c -> c.id == e.id);
		if (i < 0) i = Lambda.findIndex(compilers, c -> c.id == "");
		var c = i >= 0 ? compilers.splice(i, 1)[0] : {id: e.id, compiler: new Compiler(module, fs)};
		c.id = e.id;
		compilers.unshift(c);
		if (compilers.length > 2) compilers.pop();
		return c.compiler;
	}

	static function runtime(target:String):Promise<Bool> {
		if (target == "wasm32-wasi") return Promise.resolve(true);
		if (!runtimes.exists(target))
			runtimes.set(target, load('rt/$target.pack', 'runtime $target').then(b -> {
				fs.mount("/lib/rt", Pack.unpack(b));
				true;
			}));
		return runtimes[target];
	}

	// the edits of a request in the file system, the files no longer edited as shipped
	static function apply(edits:Null<Edits>) {
		var want = edits == null ? new Edits() : edits;
		for (path => bytes in originals)
			if (!want.exists(path)) {
				fs.write("/lib/src/" + path, bytes);
				originals.remove(path);
			}
		for (path => text in want) {
			if (!originals.exists(path)) originals.set(path, fs.read("/lib/src/" + path));
			if (fs.readText("/lib/src/" + path) != text) fs.writeText("/lib/src/" + path, text);
		}
	}

	// the waiting requests: the last build of each program, the last display request
	static function pump() {
		var waiting = queue;
		queue = [];
		var keep:Array<Request> = [];
		for (i in 0...waiting.length) {
			var m = waiting[i], later = false;
			for (j in i + 1...waiting.length) {
				var n = waiting[j];
				if (n.type == m.type && (m.type == Display || (n.example.id == m.example.id && n.target == m.target && n.dev == m.dev))) later = true;
			}
			if (later) post({type: Superseded, id: m.id}) else keep.push(m);
		}
		function next(i:Int) {
			if (i >= keep.length) {
				if (queue.length > 0) Syntax.code("setTimeout({0}, 0)", pump) else pumping = false;
				return;
			}
			var m = keep[i];
			start().then(_ -> m.type == Build ? runtime(m.target) : Promise.resolve(true)).then(_ -> {
				apply(m.edits);
				if (m.type == Build) build(m) else display(m);
			}).catchError(e -> fail(m.id, e)).then(_ -> next(i + 1));
		}
		next(0);
	}

	static function build(m:Request) {
		var compiler = compilerFor(m.example);
		var batch:Array<Array<Dynamic>> = [], last = 0.0;
		compiler.wasi.onOpen = (path, writing) -> {
			batch.push([path, writing]);
			var now:Float = Syntax.code("performance.now()");
			if (now - last > 40) {
				last = now;
				post({type: Files, files: batch});
				batch = [];
			}
		}
		var a = compiler.request(Compiler.buildArgs(m.example, m.target, m.dev));
		compiler.wasi.onOpen = (_, _) -> {};
		if (batch.length > 0) post({type: Files, files: batch});
		var out = Compiler.output(m.example, m.target, m.dev);
		var file = Compiler.file(m.example, m.target, m.dev);
		var bytes = a.ok ? fs.read(file) : null;
		// the files the program loads from beside it (Model.of's): <out>.assets.json
		var assets:Array<Array<Dynamic>> = [];
		var list = a.ok ? fs.readText(out + ".assets.json") : null;
		if (list != null) {
			var dir = out.substr(0, out.lastIndexOf("/"));
			for (rel in (haxe.Json.parse(list) : Array<String>)) {
				var b = fs.read('$dir/$rel');
				if (b != null) assets.push([rel, b.slice()]);
			}
		}
		var copy = bytes?.slice();
		var transfer:Array<Dynamic> = [for (x in assets) (x[1] : Uint8Array).buffer];
		if (copy != null) transfer.push(copy.buffer);
		post({
			type: Built, id: m.id, ok: a.ok && bytes != null, bytes: copy, file: file.substr(file.lastIndexOf("/") + 1), assets: assets,
			messages: a.messages, log: a.log, stdout: a.stdout, ms: a.ms,
		}, transfer);
	}

	static function display(m:Request) {
		var a = compilerFor(m.example).request(Compiler.displayArgs(m.example, m.method, m.file, m.offset, m.extra));
		post({type: Displayed, id: m.id, json: a.json, messages: a.messages, ms: a.ms});
	}
}
