package helder.cli;

import helder.cli.Style.Tone;
import helder.async.*;
import sys.FileSystem;

using StringTools;

// `helder build [entry] [--target <t>] [-o <path>]`: a release build (-dce
// full) into bin/<target>/<name>, its compile time and size printed; for
// web the page and its modules beside the module (bin/web/<name>.html).
// `helder run [entry] [-o <path>] [-- args...]`: the same for this machine,
// then run. (Their options: Options.)
class BuildCommand {
	@:coroutine public static function run(o:Options, andRun:Bool):Int {
		var e = try Entry.of(o) catch (err:Dynamic) {
			Term.err(Style.usage('helder ${o.command}: $err'));
			return 2;
		}
		var host = Compiler.hostTarget();
		if (andRun && e.isWeb()) {
			Term.err(Style.usage("helder run: this machine only (helder dev --target web serves a page; helder build --target web builds one)"));
			return 2;
		}
		if (andRun && e.target != host) {
			Term.err(Style.usage('helder run: ${e.target} is not this machine ($host); helder build --target ${e.target} builds for it'));
			return 2;
		}
		Term.out(Style.header(o.command, [e.target, e.main]));
		var out = o.out, programArgs = o.programArgs ?? [];
		var exe = out ?? e.out(e.target);
		var r = build(e, exe, Release);
		if (!r.ok) return 1;
		if (e.target == "web") Page.write(e.helder, exe, e.name);
		if (!andRun) return 0;
		Term.out(Style.status("running", Info, Style.path(exe + (programArgs.length == 0 ? "" : " " + programArgs.join(" ")))));
		var p = new Process(exe.contains("/") || exe.contains("\\") ? exe : './$exe', programArgs);
		p.closeStdin();
		Async.scope(task -> {
			task.async(_ -> Lines.forward(p.stdout, false));
			task.async(_ -> Lines.forward(p.stderr, true));
			null;
		});
		var code = p.wait();
		p.close();
		return code;
	}

	// one build by the compiler (a server's when given), its time and size printed
	@:coroutine public static function build(e:Entry, exe:String, mode:Mode, ?server:Compiler.CompileServer, ?extra:Array<String>):{ok:Bool, ms:Int, messages:String} {
		TestCommand.mkdirs(haxe.io.Path.directory(exe));
		var words = e.args().concat(switch mode {
			case Release: ["-dce", "full"];
			case Dev: ["-D", "hxmc.dev", "-D", "disable-hxb-cache"];
		}).concat(extra ?? []).concat(["--custom-target", 'hxmc=$exe']);
		var t0 = haxe.Timer.stamp();
		Term.spin("building " + e.name);
		var r = if (server != null) server.request(words, Sys.getCwd()) else {
			var p = new Process(Compiler.tool(), words);
			p.closeStdin();
			var lines = [];
			Async.scope(task -> {
				task.async(_ -> Lines.collect(p.stdout, lines));
				task.async(_ -> Lines.collect(p.stderr, lines));
				null;
			});
			var code = p.wait();
			p.close();
			{ok: code == 0, messages: lines.join("\n")};
		}
		var ms = Math.round((haxe.Timer.stamp() - t0) * 1000);
		Term.done();
		if (r.messages != "") Term.write(Diagnostics.format(r.messages), !r.ok);
		if (mode == Release) {
			if (r.ok) Term.out(Style.status("built", Ok, Style.path(exe) + ' in ${Style.time(ms)}' + Style.dim(Style.sep() + size(exe))));
			else Term.err(Style.status("failed", Fail, Style.path(exe) + ' in ${Style.time(ms)}'));
		}
		return {ok: r.ok, ms: ms, messages: r.messages};
	}

	public static function size(path:String):String {
		var n = FileSystem.exists(path) ? FileSystem.stat(path).size : 0;
		return n < 1024 * 1024 ? Math.round(n / 1024) + " KB" : Math.round(n / 1024 / 102.4) / 10 + " MB";
	}
}

enum Mode {
	Release;
	Dev;
}

// a child's output (lines), forwarded or kept
class Lines {
	@:coroutine public static function forward(s:Stream.Source, err:Bool, ?prefix:String) {
		var r = new Reader(s), line;
		while ((line = r.readLine()) != null) {
			if (prefix != null) line = prefix + line;
			if (err) Term.err(line) else Term.out(line);
		}
	}

	@:coroutine public static function collect(s:Stream.Source, into:Array<String>) {
		var r = new Reader(s), line;
		while ((line = r.readLine()) != null) into.push(line);
	}
}
