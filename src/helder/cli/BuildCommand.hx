package helder.cli;

import helder.cli.Style.Tone;
import haxe.io.Path;
import helder.async.*;
import sys.FileSystem;

using StringTools;

// `helder build [entry] [--target <t>] [-o <path>]`: a release build (-dce
// full) into bin/<target>/<name>, its compile time and size printed; for
// web the page and its modules beside the module (bin/web/<name>.html);
// for android an APK (Android: bin/android/<name>.apk), for ios an .ipa
// and for ios-sim an .app (Ios: bin/ios/<name>.ipa, bin/ios-sim/<name>.app).
// `helder run [entry] [-o <path>] [-- args...]`: the same for this machine,
// then run; with --target android or ios on a device (-d, else the one
// there is: Devices.pick), installed and started there, its output here.
// (Their options: Options.)
class BuildCommand {
	@:coroutine public static function run(o:Options, andRun:Bool):Int {
		var e = try Entry.of(o) catch (err:Dynamic) {
			Term.err(Style.usage('helder ${o.command}: $err'));
			return 2;
		}
		var host = Compiler.hostTarget();
		var mobile = Options.mobile(e.target);
		if (mobile != null) {
			var code = andRun ? runMobile(o, e, mobile) : buildMobile(o, e, mobile);
			return code;
		}
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

	// an APK, an .ipa or an .app (android without a device: a phone's ABI)
	@:coroutine static function buildMobile(o:Options, e:Entry, mobile:String):Int {
		e.target = mobile == "android" ? Android.target(e.target, null) : Ios.target(e.target, "build");
		Term.out(Style.header("build", [e.target, e.main]));
		var r = try {
			if (mobile == "android") Runtime.ensure(e.target);
			mobile == "android" ? Android.build(e, o.out ?? Android.out(e), Release) : Ios.build(e, o.out ?? Ios.out(e), Release);
		} catch (err:Dynamic) {
			Term.err(Style.status("error", Fail, Std.string(err)));
			return 1;
		}
		return r.ok ? 0 : 1;
	}

	// built for the device, installed and started there; its output until it ends
	@:coroutine static function runMobile(o:Options, e:Entry, mobile:String):Int {
		try {
			if (mobile == "android") {
				var d = Android.device(o.device);
				e.target = Android.target(e.target, Android.abi(d.id));
				Term.out(Style.header("run", [e.target, e.main, d.name]));
				Runtime.ensure(e.target);
				var apk = o.out ?? Android.out(e);
				if (!Android.build(e, apk, Release).ok) return 1;
				var id = App.android(e.name, e.config).id;
				Term.spin("installing on " + d.name);
				Android.install(d.id, apk);
				Term.done();
				var log = Android.logcat(d.id);
				Android.start(d.id, id, Android.activity(apk));
				Term.out(Style.status("running", Info, '$id on ${d.name}' + Style.dim(Style.sep() + "its output: logcat's hxmc")));
				Async.scope(task -> {
					if (log != null) task.async(_ -> Lines.forward(log.stdout, false));
					// (until its process ends: polled; a start that never shows one, 10 s)
					task.async(_ -> {
						var seen = false, t0 = haxe.Timer.stamp();
						while (true) {
							var running = Android.pid(d.id, id) != "";
							if (running) seen = true;
							if (seen && !running || !seen && haxe.Timer.stamp() - t0 > 10) break;
							Async.delay(1);
						}
						// (logcat's last lines first)
						Async.delay(0.5);
						if (log != null) log.stop(1);
					});
					null;
				});
				if (log != null) log.close();
				Term.out(Style.status("closed", Quiet, '$id ended'));
				return 0;
			}
			var d = Ios.device(o.device);
			e.target = Ios.target(e.target, "run");
			Term.out(Style.header("run", [e.target, e.main, d.name]));
			var app = o.out ?? Ios.out(e);
			if (!app.endsWith(".app")) throw '$app: the simulator installs an .app';
			if (!Ios.build(e, app, Release).ok) return 1;
			Term.spin("booting and installing on " + d.name);
			Ios.boot(d);
			Ios.install(d.id, app);
			Term.done();
			var id = Ios.id(e);
			Term.out(Style.status("running", Info, '$id on ${d.name}'));
			var p = Ios.launch(d.id, id);
			p.closeStdin();
			Async.scope(task -> {
				task.async(_ -> Lines.forward(p.stdout, false));
				task.async(_ -> Lines.forward(p.stderr, true));
				null;
			});
			var code = p.wait();
			p.close();
			return code;
		} catch (err:Dynamic) {
			Term.done();
			Term.err(Style.status("error", Fail, Std.string(err)));
			return 1;
		}
	}

	// one build by the compiler (a server's when given), its time and size
	// printed; pack (after a build that compiled) makes what the build is
	// for from its output (an APK, a bundle) and names it, a thrown message
	// its failure
	@:coroutine public static function build(e:Entry, exe:String, mode:Mode, ?server:Compiler.CompileServer, ?extra:Array<String>,
			?pack:Void->String):{ok:Bool, ms:Int, messages:String} {
		TestCommand.mkdirs(Path.directory(exe));
		TestCommand.mkdirs(Path.directory(manifest(exe)));
		var words = e.args().concat(switch mode {
			case Release: ["-dce", "full"];
			case Dev: ["-D", "hxmc.dev", "-D", "disable-hxb-cache"];
		}).concat(extra ?? []);
		// (the files the program names and keeps: helder.asset's Bundle writes them there)
		var m = manifest(exe);
		try FileSystem.deleteFile(m) catch (_:Dynamic) {};
		words = words.concat(["--macro", 'helder.asset.Bundle.use("${FileSystem.fullPath(Path.directory(m)).split("\\").join("/")}/${Path.withoutDirectory(m)}")']);
		words = words.concat(["--custom-target", 'hxmc=$exe']);
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
		var shown = exe;
		if (r.ok && pack != null) shown = try pack() catch (err:Dynamic) {
			r = {ok: false, messages: Std.string(err)};
			exe;
		}
		var ms = Math.round((haxe.Timer.stamp() - t0) * 1000);
		Term.done();
		if (r.messages != "") Term.write(Diagnostics.format(r.messages), !r.ok);
		if (mode == Release) {
			if (r.ok) Term.out(Style.status("built", Ok, Style.path(shown) + ' in ${Style.time(ms)}' + Style.dim(Style.sep() + size(shown))));
			else Term.err(Style.status("failed", Fail, Style.path(shown) + ' in ${Style.time(ms)}'));
		}
		return {ok: r.ok, ms: ms, messages: r.messages};
	}

	// the assets' manifest of a build's output (helder.asset.Bundle's:
	// {target, dev, assets: [{key, file, sync, bytes}]}: full paths of this
	// machine), in helder's cache, not beside the output (what is shipped)
	public static function manifest(exe:String):String {
		var full = FileSystem.fullPath(Path.directory(exe) == "" ? "." : Path.directory(exe)).split("\\").join("/") + "/" + Path.withoutDirectory(exe);
		return DevCommand.cache() + "/assets/" + haxe.crypto.Md5.encode(full).substr(0, 16) + "-" + Path.withoutDirectory(exe) + ".json";
	}

	// the files of a build's manifest (none when it wrote none)
	public static function assets(exe:String):Array<{key:String, file:String, sync:Bool, bytes:Int}> {
		var m = manifest(exe);
		if (!FileSystem.exists(m)) return [];
		var j:Dynamic = haxe.Json.parse(sys.io.File.getContent(m));
		return j.assets;
	}

	// a file's size, or a directory's (an .app: its files')
	public static function size(path:String):String {
		var n = bytes(path);
		return n < 1024 * 1024 ? Math.round(n / 1024) + " KB" : Math.round(n / 1024 / 102.4) / 10 + " MB";
	}

	static function bytes(path:String):Float {
		if (!FileSystem.exists(path)) return 0;
		if (!FileSystem.isDirectory(path)) return FileSystem.stat(path).size;
		var n = 0.0;
		for (f in FileSystem.readDirectory(path)) n += bytes('$path/$f');
		return n;
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
