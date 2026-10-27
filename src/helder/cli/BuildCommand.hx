package helder.cli;

import helder.async.*;
import sys.FileSystem;

using StringTools;

// `helder build [target] [entry]`: a release build (-dce full) into
// bin/<target>/<name>, its compile time and size printed; for web the page
// and its modules beside the module (bin/web/<name>.html). `helder run
// [entry] [-- args...]`: the same for this machine, then run.
class BuildCommand {
	static final usage = [
		"helder build [target] [entry] [-o <output>]",
		"helder run [entry] [-o <output>] [-- program arguments...]",
		"",
		"  target   host (the default: this machine), web (wasm32-wasi and its page),",
		"           or an hxmc target: " + Entry.TARGETS.slice(2).join(", "),
		"  entry    a project directory (package.json, src/Main.hx; the default: .),",
		"           an example's directory (its main file) or a .hx file",
	].join("\n");

	@:coroutine public static function run(args:Array<String>, andRun:Bool):Int {
		var rest = [], out:Null<String> = null, programArgs = [];
		var i = 0;
		while (i < args.length) {
			var a = args[i++];
			switch a {
				case "--":
					programArgs = args.slice(i);
					break;
				case "-o" | "--out" if (i < args.length): out = args[i++];
				case "-h" | "--help":
					Sys.println(usage);
					return 0;
				case _ if (a.startsWith("-")):
					Sys.println('helder: unknown option $a\n\n$usage');
					return 2;
				case _: rest.push(a);
			}
		}
		var e = try Entry.resolve(rest) catch (err:Dynamic) {
			Sys.println('helder: $err');
			return 2;
		}
		if (andRun && e.isWeb()) {
			Sys.println("helder run: this machine's targets only (helder dev web serves a page)");
			return 2;
		}
		var exe = out ?? e.out(e.target);
		var r = build(e, exe, Release);
		if (!r.ok) return 1;
		if (e.target == "web") Page.write(e.helder, exe, e.name);
		if (!andRun) return 0;
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
		if (r.messages != "") (r.ok ? Sys.stdout() : Sys.stderr()).writeString(r.messages + "\n");
		if (mode == Release) {
			if (r.ok) Sys.println('helder: $exe built in ${secs(ms)} (${size(exe)})');
			else Sys.println('helder: $exe: the build failed (${secs(ms)})');
		}
		return {ok: r.ok, ms: ms, messages: r.messages};
	}

	public static function secs(ms:Int):String
		return ms < 1000 ? '$ms ms' : Math.round(ms / 100) / 10 + " s";

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
			if (err) Sys.stderr().writeString(line + "\n") else Sys.println(line);
		}
	}

	@:coroutine public static function collect(s:Stream.Source, into:Array<String>) {
		var r = new Reader(s), line;
		while ((line = r.readLine()) != null) into.push(line);
	}
}
