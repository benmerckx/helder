package helder.compiler.service;

import helder.async.*;
import helder.compiler.service.Diagnostic;
import helder.compiler.service.LiteralEdit.Sources;
import sys.FileSystem;

using StringTools;

// The compiler as a library (README.md): one in-process API for the studio,
// the CLI and later the web's worker, over a compilation server kept warm.
//
//   var s = Service.start(task, {tool: Compiler.tool()});
//   s.check(words, cwd, changed)        -> {ok, diagnostics, ms}: typed, nothing written
//   s.build(words, cwd, changed)        -> {ok, diagnostics, messages, printed, ms}
//   s.edit(running, changed)            -> Patched (live literals: nothing built) or Build (why)
//   s.reload(running, params)           -> whether the running program took the new build
//   s.stop()
//
// words are a build's compiler arguments (helder.cli.Entry.args() and the
// output's: `--custom-target hxmc=<out>`, -D hxmc.dev for a dev build);
// changed, the files changed since the last request (the server compares
// files' times, which two saves in one second share). A running program is
// what `helder dev` (or the studio) holds: its devtools connection, as a
// function sending a request and handing over its response.
class Service {
	public final server:Resident;
	// the live literals' tables of dev builds (null: none asked: literals())
	public var sources(default, null):Null<Sources> = null;

	function new(server)
		this.server = server;

	// a warm compiler: tool its executable (helder's: helder.cli.Compiler.tool()),
	// env its environment, std hxmc's std given last to each build; null: it
	// did not start (fail: why)
	@:coroutine public static function start(task:Node, options:{tool:String, ?env:Map<String, String>, ?std:String}, ?fail:String->Void):Null<Service> {
		var s = Resident.start(task, options.tool, options.env ?? Process.environment(), options.std, fail);
		return s == null ? null : new Service(s);
	}

	// files changed since the last request (each told to the server)
	@:coroutine public function invalidate(files:Array<String>, cwd:String)
		for (f in files)
			if (f.endsWith(".hx") && FileSystem.exists(f)) server.invalidate(f, cwd);

	// the program typed (and a frontend's own check: tsgo's), nothing written: its diagnostics
	@:coroutine public function check(words:Array<String>, cwd:String, ?changed:Array<String>):{ok:Bool, diagnostics:Array<Diagnostic>, ms:Int} {
		if (changed != null) invalidate(changed, cwd);
		var t0 = haxe.Timer.stamp();
		var r = server.request(words.concat(["--no-output"]), cwd);
		return {ok: r.ok, diagnostics: Diagnostics.parse(r.messages), ms: Math.round((haxe.Timer.stamp() - t0) * 1000)};
	}

	// a build (its output named by words: --custom-target hxmc=<out>); a dev
	// build with literals() on also writes its sources' live literals' tables
	@:coroutine public function build(words:Array<String>, cwd:String, ?changed:Array<String>):{ok:Bool, diagnostics:Array<Diagnostic>, messages:String, printed:String, ms:Int} {
		if (changed != null) invalidate(changed, cwd);
		var t0 = haxe.Timer.stamp();
		var dev = words.contains("hxmc.dev");
		var r = server.request(dev && sources != null ? words.concat(["-D", "helder.literals=" + sources.dir]) : words, cwd);
		if (r.ok && dev && sources != null) sources.update();
		return {ok: r.ok, diagnostics: Diagnostics.parse(r.messages), messages: r.messages, printed: r.printed, ms: Math.round((haxe.Timer.stamp() - t0) * 1000)};
	}

	// live literals on: dev builds write their tables into dir
	public function literals(dir:String) {
		sources = new Sources(dir);
	}

	// files saved while a build runs: when only live literals' values changed
	// (LiteralEdit), patched in the running program (Hot.literals, its
	// answer within 2 s); else, or when it cannot take them (a literal read
	// once, not bound), a build's (why)
	@:coroutine public function edit(running:Running, changed:Array<String>):Edit {
		if (sources == null) return Build("live literals are off");
		var all = [];
		for (f in changed) {
			var why = null;
			var p = FileSystem.exists(f) ? sources.patches(f, w -> why = w) : null;
			if (p == null) return Build(haxe.io.Path.withoutDirectory(f) + ": " + (why ?? "removed"));
			all = all.concat(p);
		}
		if (all.length == 0) return Unchanged;
		var answer:Dynamic = null;
		if (!running({method: "Hot.literals", params: {set: all}}, r -> answer = r)) return Build("no program connected to patch");
		var t0 = haxe.Timer.stamp();
		while (answer == null && haxe.Timer.stamp() - t0 < 2) Async.delay(0.002);
		var r:Dynamic = answer == null ? null : answer.result;
		if (r == null) return Build("the program did not take the literals (" + (answer?.error?.message ?? "no answer") + ")");
		var stale:Array<String> = r.stale == null ? [] : r.stale;
		if (stale.length > 0) return Build('${stale.length} read once, not bound: ${stale.join(", ")}');
		sources.took(all);
		return Patched(all);
	}

	// the running program reloaded with a build (params: Runtime.reload's,
	// the snapshot's file and a dev host's library): whether it saved its
	// state and handed over within seconds
	@:coroutine public function reload(running:Running, params:Dynamic, seconds = 10.0):Bool {
		var answer:Dynamic = null;
		if (!running({method: "Runtime.reload", params: params}, r -> answer = r)) return false;
		var t0 = haxe.Timer.stamp();
		while (answer == null && haxe.Timer.stamp() - t0 < seconds) Async.delay(0.002);
		return answer != null && answer.error == null;
	}

	@:coroutine public function stop()
		server.stop();
}

// a running program: a request sent to it (false: none connected), its response handed to done
typedef Running = haxe.coro.Coroutine<(request:{method:String, params:Dynamic}, done:Dynamic->Void) -> Bool>;

enum Edit {
	// live literals patched (their ids and sources), nothing built
	Patched(literals:Array<{id:String, source:String}>);
	// saved as it was
	Unchanged;
	// a build's (why)
	Build(why:String);
}
