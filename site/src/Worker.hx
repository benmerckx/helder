// Runs the compiler (hih.js + hih.wasm + hih.data, from site/build.sh).
// Each request gets a fresh instance: the program's static state starts
// clean; the compiled wasm module is reused between instances.
//
// Messages in:
//   {type: "warmup"}
//   {type: "compile", mode: "run" | "hxb", file, main, code}
//   {type: "display", id, file, main, code, request}   (a JSON-RPC display request)
//   {type: "check", id, file, main, code}              (type-check only, for diagnostics)
import js.Syntax;
import js.html.DedicatedWorkerGlobalScope;
import js.html.TextDecoder;
import js.lib.Promise;
import js.lib.Uint8Array;
import js.lib.WebAssembly;

class Worker {
	static var scope:DedicatedWorkerGlobalScope;
	static var wasmModule:Dynamic = null;
	static var moduleReady:Dynamic->Void = null;
	static var modulePromise:Promise<Dynamic>;

	static function main() {
		scope = Syntax.code("self");
		scope.importScripts("hih.js");
		modulePromise = new Promise((resolve, _) -> moduleReady = resolve);
		scope.onmessage = onmessage;
	}

	static function instantiateWasm(imports:Dynamic, done:(Dynamic, Dynamic) -> Void):Dynamic {
		final ready:Promise<Dynamic> = wasmModule != null ? Promise.resolve(wasmModule) : modulePromise;
		ready.then((m) -> WebAssembly.instantiate(m, imports)).then((inst) -> done(inst, wasmModule));
		return {};
	}

	// stdout/stderr byte by byte: Emscripten's default print only passes on complete
	// lines, and the compiler ends a --display reply without a newline
	static function lineWriter(emit:String->Void) {
		final decoder = new TextDecoder();
		var bytes:Array<Int> = [];
		final flush = function():Void {
			if (bytes.length > 0) emit(decoder.decode(new Uint8Array(bytes)));
			bytes = [];
		};
		final write = function(b:Null<Int>):Void {
			if (b == null || b == 10) flush();
			else bytes.push(b < 0 ? b + 256 : b);
		};
		return {write: write, flush: flush};
	}

	static function instance(file:String, code:String, print:String->Void, printErr:String->Void):Promise<Dynamic> {
		final out = lineWriter(print), err = lineWriter(printErr);
		final create:Dynamic = Syntax.code("createHih");
		final created:Promise<Dynamic> = create({
			noInitialRun: true,
			instantiateWasm: instantiateWasm,
			stdout: out.write,
			stderr: err.write,
			preRun: [(m:Dynamic) -> {
				m.ENV.HAXE_STD_PATH = "/lib/haxe/std/";
				m.FS.mkdir("/work");
				m.FS.writeFile("/work/" + file, code);
				m.FS.chdir("/work");
			}],
		});
		return created.then((mod:Dynamic) -> {
			mod.flushOutput = () -> {
				out.flush();
				err.flush();
			};
			return mod;
		});
	}

	static function run(mod:Dynamic, args:Array<String>):Int {
		var status:Int;
		try {
			status = mod.callMain(args);
		} catch (err:Dynamic) {
			mod.flushOutput();
			if (Js.truthy(err) && err.name == "ExitStatus") return err.status;
			Syntax.code("throw {0}", err);
			return -1;
		}
		mod.flushOutput();
		return status;
	}

	static function onmessage(e:js.html.MessageEvent) {
		final m:Dynamic = e.data;
		if (m.type == "module") {
			// the module compiled once by the page (Playground.hx)
			wasmModule = m.module;
			if (moduleReady != null) moduleReady(m.module);
			return;
		}
		final failed = (err:Dynamic) -> {
			scope.postMessage({type: "failed", id: m.id, message: "The compiler instance failed: " + Js.str(Js.truthy(err) && Js.truthy(err.message) ? err.message : err)});
		};
		try {
			handle(m).catchError(failed);
		} catch (err:Dynamic) {
			failed(err);
		}
	}

	static function handle(m:Dynamic):Promise<Dynamic> {
		if (m.type == "warmup") {
			return instance("Main.hx", "", (_) -> {}, (_) -> {}).then((_) -> {
				scope.postMessage({type: "ready"});
				return null;
			});
		}
		if (m.type == "display" || m.type == "check") {
			final lines:Array<String> = [];
			return instance(m.file, m.code, (t) -> lines.push(t), (t) -> lines.push(t)).then((mod) -> {
				final args:Array<String> = ["-cp", ".", "--main", m.main, "--no-output", "-D", "disable-parallelism", "-D", "message.reporting=classic"];
				if (m.type == "display") {
					args.push("--display");
					args.push(haxe.Json.stringify(m.request));
				}
				final t0 = scope.performance.now();
				final status = run(mod, args);
				scope.postMessage({type: m.type, id: m.id, status: status, output: lines.join("\n"), ms: scope.performance.now() - t0});
				return null;
			});
		}
		return instance(m.file, m.code, (text) -> scope.postMessage({type: "out", text: text}), (text) -> scope.postMessage({type: "err", text: text})).then((mod) -> {
			final args:Array<String> = ["-cp", ".", "--main", m.main, "-D", "disable-parallelism"];
			if (m.mode == "run") args.push("--interp");
			else {
				args.push("--hxb");
				args.push("/out.zip");
				args.push("--no-output");
			}
			final t0 = scope.performance.now();
			final status = run(mod, args);
			final ms = scope.performance.now() - t0;
			var zip:Dynamic = null;
			if (m.mode == "hxb" && status == 0) {
				try {
					zip = mod.FS.readFile("/out.zip").buffer;
				} catch (err:Dynamic) {}
			}
			scope.postMessage({type: "done", status: status, ms: ms, zip: zip}, Js.truthy(zip) ? [zip] : []);
			return null;
		});
	}
}
