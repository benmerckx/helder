import Wasi;
import js.lib.DataView;
import js.lib.Uint8Array;
import js.html.TextDecoder;
import js.html.TextEncoder;

typedef Demo = {?canvas:Array<Int>, ?sound:Bool};

// an example, as manifest.json lists it (Build reads them from their headers)
typedef Example = {
	id:String,
	pkg:String,
	main:String,
	title:String,
	summary:String,
	tags:Array<String>,
	demo:Demo,
	// its file, and the files of its folder it uses: under /lib/src
	source:String,
	sources:Array<String>,
	// its class paths and defines
	args:Array<String>,
	// the browser modules it runs with (os's browser.mjs takes them)
	imports:Array<String>,
	fonts:Bool,
}

typedef Manifest = {
	hxmc:{version:String, rev:String},
	commit:String,
	targets:Array<String>,
	sizes:haxe.DynamicAccess<Int>,
	examples:Array<Example>,
}

// a message of the compiler's about a place in a file (classic reporting:
// file:line: characters a-b : message)
typedef Message = {file:String, line:Int, from:Int, to:Int, lines:Bool, text:String, warning:Bool};

// what a request answers: the program's output (stdout, --interp), the
// compiler's messages, the display's JSON result, whether it failed
typedef Answer = {ok:Bool, stdout:Array<String>, messages:Array<Message>, log:Array<String>, json:Null<Dynamic>, ms:Float};

// The compiler (reactor.wasm: compiler/Reactor.hx), resident: one instance
// over a MemFS, each build or display request a call into it. Typed modules
// and compiled objects stay in it between requests, so a build after an
// edit types and compiles only what changed.
class Compiler {
	public static final ENV = ["HAXE_STD_PATH" => "/lib/std", "HXMC_STD" => "/lib/hxmc-std", "HXMC_RT_DIR" => "/lib/rt", "PWD" => "/work", "HOME" => "/home"];

	public final fs:MemFS;
	public final wasi:Wasi;

	final instance:js.lib.webassembly.Instance;
	final defined = new Map<String, Int>();

	public function new(module:js.lib.webassembly.Module, fs:MemFS) {
		this.fs = fs;
		fs.mkdirs("/work");
		wasi = new Wasi(["haxe"], ENV, fs);
		instance = new js.lib.webassembly.Instance(module, {
			wasi_snapshot_preview1: wasi.imports,
			hxmc_web: {define: (name:Int, fn:Int) -> defined.set(cstring(name), fn)},
		});
		var code = wasi.start(instance);
		if (code != 0 || !defined.exists("request")) throw 'the compiler did not start ($code)';
	}

	function cstring(p:Int):String {
		var m = new Uint8Array(wasi.memory.buffer), e = p;
		while (m[e] != 0) e++;
		return new TextDecoder().decode(m.subarray(p, e));
	}

	function call(name:String, args:Array<Int>):Int {
		var exports:Dynamic = instance.exports;
		var f:haxe.Constraints.Function = exports.__indirect_function_table.get(defined[name]);
		return js.Syntax.code("{0}.apply(null, {1})", f, args);
	}

	// the server's answer to the arguments
	public function request(args:Array<String>):Answer {
		var b = new TextEncoder().encode(args.join("\n"));
		var p = call("__alloc", [b.length]);
		new Uint8Array(wasi.memory.buffer).set(b, p);
		var t0 = js.Lib.global.performance.now();
		var r = call("request", [p, b.length]);
		var ms = js.Lib.global.performance.now() - t0;
		call("__free", [p]);
		var n = new DataView(wasi.memory.buffer).getInt32(r, true);
		var text = new TextDecoder().decode(new Uint8Array(wasi.memory.buffer, r + 4, n));
		call("__free", [r]);
		return parse(text, ms);
	}

	static final MESSAGE = ~/^(.+\.hx):(\d+): (characters|lines) (\d+)-(\d+) : (.*)$/;

	// the server's answer: stdout lines marked \x01, \x02 before a failed
	// build's errors, the display's JSON-RPC reply, the messages
	static function parse(text:String, ms:Float):Answer {
		var a:Answer = {ok: true, stdout: [], messages: [], log: [], json: null, ms: ms};
		for (line in text.split("\n")) {
			if (StringTools.startsWith(line, "\x01")) {
				// (a build's stdout: the program's under --interp; the compiler's warnings otherwise)
				for (l in line.substr(1).split("\x01")) if (l != "") {
					if (MESSAGE.match(l)) message(a, l) else a.stdout.push(l);
				}
			} else if (line == "\x02") a.ok = false;
			else if (StringTools.startsWith(line, '{"jsonrpc"')) {
				var reply:Dynamic = try haxe.Json.parse(line) catch (_:Dynamic) null;
				if (reply != null && reply.result != null) a.json = reply.result.result;
			} else if (line != "") {
				if (MESSAGE.match(line)) message(a, line) else a.log.push(line);
			}
		}
		return a;
	}

	// a line MESSAGE matched
	static function message(a:Answer, line:String) {
		a.log.push(line);
		var text = MESSAGE.matched(6);
		var warning = StringTools.startsWith(text, "Warning");
		a.messages.push({
			file: MESSAGE.matched(1),
			line: Std.parseInt(MESSAGE.matched(2)),
			lines: MESSAGE.matched(3) == "lines",
			from: Std.parseInt(MESSAGE.matched(4)),
			to: Std.parseInt(MESSAGE.matched(5)),
			text: warning ? StringTools.trim(text.substr(text.indexOf(":") + 1)) : text,
			warning: warning,
		});
	}

	// where a build of an example for a target goes (-D hxmc.dev: the page's live builds)
	public static function output(e:Example, target:String, dev:Bool):String
		return '/work/out/${e.id}/$target${dev ? "-dev" : ""}/${e.main}';

	// the arguments of a build: the page's (wasm32-wasi, -D hxmc.dev: swapped
	// in live, legacy exception handling as the site's), or a download's
	public static function buildArgs(e:Example, target:String, dev:Bool):Array<String> {
		var a = e.args.concat([
			"-cp", "/lib/hxmc-std",
			"--custom-target", "hxmc=" + output(e, target, dev),
			"-D", "hxmc.target=" + target,
			"-D", "message.reporting=classic",
		]);
		if (target == "wasm32-wasi") a = a.concat(["-D", "hxmc.wasm-eh=legacy"]);
		if (StringTools.startsWith(target, "linux")) a = a.concat(["-D", "hxmc.libc=glibc"]);
		if (dev) a = a.concat(["-D", "hxmc.dev"]);
		return a;
	}

	// a display request (JSON-RPC: display/completion, display/hover,
	// display/signatureHelp, display/definition) at a byte offset of a file
	public static function displayArgs(e:Example, method:String, file:String, offset:Int, ?extra:Dynamic):Array<String> {
		var params:Dynamic = {file: file, offset: offset};
		if (extra != null) for (f in Reflect.fields(extra)) Reflect.setField(params, f, Reflect.field(extra, f));
		return e.args.concat([
			"-cp", "/lib/hxmc-std",
			"--custom-target", "hxmc=" + output(e, "wasm32-wasi", true),
			"-D", "hxmc.target=wasm32-wasi",
			"-D", "hxmc.dev",
			"-D", "message.reporting=classic",
			"--no-output",
			"--display", haxe.Json.stringify({jsonrpc: "2.0", id: 1, method: method, params: params}),
		]);
	}
}
