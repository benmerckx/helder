import Compiler;
import Wasi;
import js.Syntax;
import js.lib.Uint8Array;

// make landing-check: the page's builds in node, through the same code the
// worker runs (Compiler over Wasi): every example built for the page (as
// its live builds: -D hxmc.dev) by a compiler of its own, then the first
// one rebuilt after an edit to it and to a file it uses, asked for a hover
// and a completion, broken on purpose, and built for every native target.
//
//   node --stack-size=65500 bin/landing/check.js <site dir> [example id ...]
class Check {
	static final fs:Dynamic = Syntax.code("require('fs')");
	static var failed = 0;

	static function out(s:String)
		Syntax.code("console.log({0})", s);

	static function read(dir:String, f:String):Uint8Array
		return new Uint8Array(fs.readFileSync(dir + "/" + f));

	static function main() {
		var argv:Array<String> = Syntax.code("process.argv.slice(2)");
		var dir = argv.length > 0 ? argv[0] : "bin/landing";
		var only = argv.slice(1);
		var manifest:Manifest = haxe.Json.parse(fs.readFileSync(dir + "/manifest.json", "utf8"));
		var memfs = new MemFS();
		memfs.mount("/lib", Pack.unpack(read(dir, "std.pack")));
		memfs.mount("/lib/src", Pack.unpack(read(dir, "src.pack")));
		var module = new js.lib.webassembly.Module(read(dir, "reactor.wasm"));
		// (a compiler per program, as the page's worker has)
		var c:Compiler = null;
		var examples = [for (e in manifest.examples) if (only.length == 0 || only.contains(e.id)) e];

		function check(what:String, e:Example, a:Answer, ok:Bool, ?size:Int) {
			out('${StringTools.rpad(e.id, " ", 20)} ${StringTools.rpad(what, " ", 22)} ${ok ? "ok" : "FAILED"} ${StringTools.lpad(Std.string(Math.round(a.ms)), " ", 6)} ms${size != null ? "  " + size + " B" : ""}');
			if (!ok) {
				failed++;
				out(a.log.join("\n"));
			}
		}
		function build(e:Example, target:String, dev:Bool, what:String) {
			var a = c.request(Compiler.buildArgs(e, target, dev));
			var bytes = memfs.read(Compiler.output(e, target, dev) + (StringTools.startsWith(target, "windows") ? ".exe" : ""));
			check(what, e, a, a.ok && bytes != null, bytes?.length);
		}

		for (e in examples) {
			c = new Compiler(module, memfs);
			build(e, "wasm32-wasi", true, "page");
		}
		var e = examples[0];
		c = new Compiler(module, memfs);
		build(e, "wasm32-wasi", true, "page, again");
		var file = "/lib/src/" + e.source, text = memfs.readText(file);
		var at = text.indexOf("function main()");
		memfs.writeText(file, text.substr(0, at) + "/* edited */ " + text.substr(at));
		build(e, "wasm32-wasi", true, "page, edited");
		memfs.writeText(file, text);
		// (a file it uses: a shader's, whose macro keeps state in the server)
		if (e.sources.length > 0) {
			var used = "/lib/src/" + e.sources[0], usedText = memfs.readText(used);
			memfs.writeText(used, usedText + "\n// edited\n");
			build(e, "wasm32-wasi", true, "page, " + e.sources[0].split("/").pop() + " edited");
			memfs.writeText(used, usedText);
		}
		var offset = new js.html.TextEncoder().encode(text.substr(0, at + 11)).length;
		var hover = c.request(Compiler.displayArgs(e, "display/hover", file, offset));
		check("hover", e, hover, hover.json != null);
		var line = text.indexOf("\n", at + 15);
		var completion = c.request(Compiler.displayArgs(e, "display/completion", file, new js.html.TextEncoder().encode(text.substr(0, line)).length, {wasAutoTriggered: false}));
		check("completion", e, completion, completion.json != null && completion.json.items.length > 0);
		memfs.writeText(file, text.substr(0, at) + "function main() { oops " + text.substr(at + 15));
		var broken = c.request(Compiler.buildArgs(e, "wasm32-wasi", true));
		check("broken: an error", e, broken, !broken.ok && broken.messages.length > 0 && broken.messages[0].file == file);
		memfs.writeText(file, text);
		for (t in manifest.targets) {
			memfs.mount("/lib/rt", Pack.unpack(read(dir, 'rt/$t.pack')));
			build(e, t, false, t);
		}
		// the compiler for browsers without exnref (node runs the legacy instructions natively)
		var legacy = new js.lib.webassembly.Module(read(dir, "reactor-legacy.wasm"));
		c = new Compiler(legacy, memfs);
		build(e, "wasm32-wasi", true, "page, legacy compiler");
		if (failed > 0) {
			out('landing: $failed checks failed');
			Syntax.code("process.exit(1)");
		}
	}
}
