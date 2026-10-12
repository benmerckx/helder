import Protocol;
import js.Syntax;
import js.html.DedicatedWorkerGlobalScope;
import js.html.TextDecoder;
import js.lib.Promise;
import js.lib.Uint8Array;
import js.lib.WebAssembly;

// Runs the compiler (hih.js + hih.wasm + hih.data, from site/build.sh). Each
// request gets a fresh instance, so the program's static state starts clean;
// the compiled wasm module is reused between instances.

/** the Emscripten module of hih.js */
typedef Hih = {
	var ENV:haxe.DynamicAccess<String>;
	var FS:{
		function mkdir(path:String):Void;
		function writeFile(path:String, data:String):Void;
		function chdir(path:String):Void;
		function readFile(path:String):Uint8Array;
	};
	function callMain(args:Array<String>):Int;
}

class Worker {
	static final scope:DedicatedWorkerGlobalScope = Syntax.code("self");
	static var wasmModule:Promise<js.lib.webassembly.Module>;
	static var moduleReady:js.lib.webassembly.Module->Void;

	static function main() {
		scope.importScripts("hih.js");
		wasmModule = new Promise((resolve, _) -> moduleReady = resolve);
		scope.onmessage = (e) -> onRequest(e.data);
	}

	static function post(reply:Reply, ?transfer:Array<Dynamic>) {
		scope.postMessage(reply, transfer != null ? transfer : []);
	}

	/** stdout or stderr, byte by byte: Emscripten's default print only passes on
		complete lines, and the compiler ends a --display reply without a newline */
	static function lineWriter(emit:String->Void) {
		final decoder = new TextDecoder();
		var bytes:Array<Int> = [];
		function flush() {
			if (bytes.length > 0) emit(decoder.decode(new Uint8Array(bytes)));
			bytes = [];
		}
		return {
			write: (b:Null<Int>) -> if (b == null || b == 10) flush() else bytes.push(b & 0xFF),
			flush: flush,
		};
	}

	/** a compiler instance with `code` as /work/`file`; `run` calls its main */
	static function instance(file:String, code:String, print:String->Void, printErr:String->Void):Promise<{hih:Hih, run:Array<String>->Int}> {
		final out = lineWriter(print), err = lineWriter(printErr);
		final created:Promise<Hih> = Syntax.code("createHih({0})", {
			noInitialRun: true,
			instantiateWasm: (imports:Dynamic, done:(js.lib.webassembly.Instance, js.lib.webassembly.Module) -> Void) -> {
				wasmModule.then((m) -> WebAssembly.instantiate(m, imports).then((inst) -> done(inst, m)));
				return {};
			},
			stdout: out.write,
			stderr: err.write,
			preRun: [(m:Hih) -> {
				m.ENV["HAXE_STD_PATH"] = "/lib/haxe/std/";
				m.FS.mkdir("/work");
				m.FS.writeFile("/work/" + file, code);
				m.FS.chdir("/work");
			}],
		});
		return created.then((hih) -> {
			hih: hih,
			run: (args:Array<String>) -> {
				var status = 0, error:Dynamic = null;
				try status = hih.callMain(args) catch (e:Dynamic) error = e;
				out.flush();
				err.flush();
				if (error != null) {
					if (error.name != "ExitStatus") throw error;
					status = error.status;
				}
				return status;
			}
		});
	}

	static function readZip(hih:Hih):Null<js.lib.ArrayBuffer> {
		return try hih.FS.readFile("/out.zip").buffer catch (_:Dynamic) null;
	}

	static function onRequest(m:Request) {
		if (m.type == "module") {
			// the module compiled once by the page
			moduleReady(m.module);
			return;
		}
		final failed = (e:Dynamic) -> post({type: "failed", id: m.id, message: "The compiler instance failed: " + Ui.error(e)});
		try handle(m).catchError(failed) catch (e:Dynamic) failed(e);
	}

	static function handle(m:Request):Promise<Void> {
		switch m.type {
			case "warmup":
				return instance("Main.hx", "", (_) -> {}, (_) -> {}).then((_) -> post({type: "ready"}));
			case "display" | "check":
				final lines = [];
				final add = (line:String) -> lines.push(line);
				return instance(m.file, m.code, add, add).then((c) -> {
					var args = ["-cp", ".", "--main", m.main, "--no-output", "-D", "disable-parallelism", "-D", "message.reporting=classic"];
					if (m.type == "display") args = args.concat(["--display", haxe.Json.stringify(m.request)]);
					final t0 = scope.performance.now();
					final status = c.run(args);
					post({type: m.type, id: m.id, status: status, output: lines.join("\n"), ms: scope.performance.now() - t0});
				});
			case _:
				return instance(m.file, m.code, (text) -> post({type: "out", text: text}), (text) -> post({type: "err", text: text})).then((c) -> {
					final args = ["-cp", ".", "--main", m.main, "-D", "disable-parallelism"]
						.concat(m.mode == "run" ? ["--interp"] : ["--hxb", "/out.zip", "--no-output"]);
					final t0 = scope.performance.now();
					final status = c.run(args);
					final ms = scope.performance.now() - t0;
					final zip = m.mode == "hxb" && status == 0 ? readZip(c.hih) : null;
					post({type: "done", status: status, ms: ms, zip: zip}, zip != null ? [zip] : []);
				});
		}
	}
}
