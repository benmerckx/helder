package helder.cli;

import helder.cli.ExitPolicy;
import helder.cli.Style.Tone;
import haxe.io.Path;
import helder.async.*;
import helder.async.http.Http;
import helder.async.http.WebSocket;
import helder.cli.BuildCommand.Lines;
import helder.cli.Compiler.CompileServer;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `helder dev [entry] [--target host | web | android | ios] [-d <device>] [-- args]`: the dev loop, ported from @hxmc/cli's
// dev.mjs. The compiler stays resident (CompileServer, --server-connect);
// what the last build read is watched (SampledWatcher: the module files
// Deps writes, their directories, and assets/), and a change builds again
// with -D hxmc.dev. A build with errors changes
// nothing: the last good build keeps running, the errors show here (and in
// the page's overlay). A build that compiles reloads the program, its state
// carried over by key (helder.dev.Hot's snapshot):
// - natively, the program started with HXMC_DEV=<host:port> (our socket for
//   it, JSON lines) and HXMC_DEV_SNAPSHOT=<file>. On Linux (glibc), Windows
//   and macOS it runs in the dev host (helder.dev.DevHost, built once and
//   cached): each build a shared library (.so, .dll, .dylib) under a name of
//   its own (<out>.dev/<n>.<ext>: a loaded library is not written over, and
//   Windows locks it), a reload {"type":"reload","snapshot","library"}: the
//   build writes its snapshot, disposes and returns, the host loads the new
//   one in the same process (the window and the GPU device or context kept).
//   With HELDER_DEV_HOST=0, or when the host does not build,
//   {"type":"reload","snapshot"}: the program writes it and exits, the new
//   build starts with it;
// - web: a page at http://127.0.0.1:<port>/ (page.html) running the module
//   with its packages' browser modules, told over a WebSocket at /__hxmc/ws
//   ({"type":"reload"}, {"type":"error","message"}, {"type":"ok"}): it swaps
//   the new build in, in the same page;
// - a phone (--target android, ios: -d's device, else the one there is):
//   the first build is the dev host's app (-D hxmc.dev-host), installed and
//   started there. Android's APK is built for our socket (-D
//   hxmc.dev-server=127.0.0.1:<port>, adb reverse'd), and a later build
//   sends only its library: {"type":"reload","snapshot":"-","fetch":n},
//   the app asks for "lib <n>" on a connection of its own, writes it into
//   its files and hands over to it in the same process; its output is
//   logcat's. The simulator's app gets HXMC_DEV (SIMCTL_CHILD_), a later
//   build is a dylib it loads from this machine's files ({"type":"reload",
//   "snapshot","library"}), its output simctl's (--console). Closing the
//   app there ends nothing (ExitPolicy's Mobile): the next build installs
//   and starts it again.
// The program answers {"type":"saved"} and {"type":"frame"} (its first
// frame: the reload's time, from the change seen). Natively a program with
// helder.devtools' agent (HXMC_DEV_PROTOCOL=1) speaks JSON-RPC instead
// (src/helder/devtools/README.md): Runtime.hello, Runtime.reload answered
// once saved, Runtime.ready; Devtools relays it to the tools connected at
// /__helder/devtools on the HTTP port (natively too: bin/dev/devtools.json
// names it). When the program ends by itself, ExitPolicy decides: closed
// (exit code 0) ends the session, a crash waits for a change.
class DevCommand {
	static var e:Entry;
	static var out:String;
	static var server:CompileServer;
	static var web:Bool;
	static var hosted:Bool;
	static var cwd:String;
	static var snapshot:String;
	// the last build's errors (null: it compiled)
	static var lastError:Null<String> = null;
	static var building = false;
	static var built = false;
	// the reload being measured: when the change was seen, the build's time
	static var timing:Null<{seen:Float, build:Int}> = null;
	// natively: the program, its connection, whether it said saved
	static var child:Null<Child> = null;
	// (a signal: helder dev ending)
	static var stopping = false;
	// where the program runs (ExitPolicy)
	static var platform:ExitPolicy.Platform = Desktop;
	// android, ios: the phone's platform, its device (null: this machine, web)
	static var mobile:Null<String> = null;
	static var device:Null<Devices.Device> = null;
	// the phone's app installed and connected when this build began: the
	// build swapped into it (Android: its library, fetched; the simulator: a
	// dylib), else the whole app built, installed and started
	static var swapping = false;
	static var installed = false;
	// Android: the libraries the app fetches ("lib <n>"), the latest only
	static var fetchable:Null<{n:String, bytes:haxe.io.Bytes}> = null;
	// the phone's output: logcat (Android), simctl launch --console (iOS)
	static var phoneLog:Null<Process> = null;
	static var socket:Null<Socket> = null;
	static var saved = false;
	static var appPort = 0;
	static var programArgs:Array<String> = [];
	static var hostExe:Null<String> = null;
	static var hostReady = false;
	static var libCount = 0;
	// (the libraries handed over from, deleted once the host has closed them)
	static final stale:Array<String> = [];
	// the program's executable (out without the host)
	static var exeOut = "";
	// web: the pages connected
	static final clients:Array<WebSocket> = [];

	@:coroutine public static function run(task:Node, o:Options):Int {
		var port = Std.parseInt(o.value("port") ?? Sys.getEnv("HELDER_DEV_PORT") ?? "") ?? 4321, address = o.value("host") ?? "127.0.0.1";
		programArgs = o.programArgs ?? [];
		e = try Entry.of(o) catch (err:Dynamic) {
			Term.err(Style.usage('helder dev: $err'));
			return 2;
		}
		web = e.isWeb();
		mobile = Options.mobile(e.target);
		if (mobile != null) {
			// (the device first: Android's ABI is the build's target; a simulator booted)
			try {
				device = mobile == "android" ? Android.device(o.device) : Ios.device(o.device);
				e.target = mobile == "android" ? Android.target(e.target, Android.abi(device.id)) : Ios.target(e.target, "dev");
				// (Android's runtime objects before the compile server starts: its HXMC_RT_DIR)
				Runtime.ensure(e.target);
				if (mobile == "ios") {
					Term.spin("booting " + device.name);
					Ios.boot(device);
					Term.done();
				}
			} catch (err:Dynamic) {
				Term.done();
				Term.err(Style.status("error", Fail, Std.string(err)));
				return 1;
			}
		} else if (!web && e.target != Compiler.hostTarget()) {
			Term.err(Style.usage('helder dev: ${e.target} is not this machine (${Compiler.hostTarget()}); helder build --target ${e.target} builds for it'));
			return 2;
		}
		// (a phone's: the app closed there does not end the session, ExitPolicy's Mobile)
		platform = web ? Web : mobile != null ? Mobile : Desktop;
		Term.out(Style.header("dev", [web ? "web" : e.target, e.main].concat(device == null ? [] : [device.name])));
		if (web) e.target = "web";
		cwd = Sys.getCwd();
		hosted = !web && mobile == null && Sys.getEnv("HELDER_DEV_HOST") != "0"
			&& (e.target.startsWith("linux-") || e.target.startsWith("windows-") || e.target.startsWith("macos-"));
		out = exeOut = switch mobile {
			case "android": Entry.clean('${e.root}/bin/dev/android/${e.name}.apk');
			case "ios": Entry.clean('${e.root}/bin/dev/ios-sim/${e.name}.app');
			case _: e.out("dev/" + (web ? "web" : e.target));
		}
		if (hosted) out = Path.withoutExtension(out) + libExt();
		var dir = Path.directory(out) == "" ? "." : Path.directory(out);
		TestCommand.mkdirs(dir);
		snapshot = FileSystem.fullPath(dir) + '/${e.name}.snapshot';
		try FileSystem.deleteFile(snapshot) catch (_:Dynamic) {};
		try FileSystem.deleteFile(depsFile()) catch (_:Dynamic) {};
		server = CompileServer.start(task);
		if (server == null) {
			Term.err(Style.status("error", Fail, "the compilation server did not start (" + Compiler.tool() + ")"));
			return 1;
		}
		// (ctrl-c, SIGTERM: the program and the compilation server stopped too.
		// Windows has no signals here (helder.async.Signals): ctrl-c reaches
		// every process of the console, the program's and the compiler's too)
		task.async(_ -> {
			var sig = Signals.next([Signal.SIGINT, Signal.SIGTERM]);
			shutdown(128 + sig);
		});
		var http = listen(address, port);
		if (http == null) {
			Term.err(Style.status("error", Fail, 'no free port from $port'));
			return 1;
		}
		task.async(_ -> Http.serve(http, serve));
		Devtools.main = e.main;
		Devtools.target = e.target;
		var at = address == "0.0.0.0" ? "localhost" : address;
		try File.saveContent('${e.root}/bin/dev/devtools.json',
			haxe.Json.stringify({port: http.port, host: at, path: "/__helder/devtools", protocol: Devtools.PROTOCOL, entry: e.main, target: e.target}))
		catch (_:Dynamic) {};
		if (web) {
			log(Style.status("serving", Info, Style.url('http://$at:${http.port}/')));
			log(Style.status("watching", Info, Style.path(e.sources.join(", "))));
		} else {
			var app = Server.listen("127.0.0.1", 0);
			appPort = app.port;
			task.async(_ -> while (true) {
				var s = app.accept();
				task.async(_ -> connection(s));
				// (the phone's app reached us, Android's through adb reverse: told
				// once it is the program's connection, not a library's fetch)
				if (mobile != null && !swapping) task.async(_ -> {
					Async.delay(0.2);
					if (socket == s) log(Style.status("connected", Info, 'the app on ${device.name}'));
				});
			});
			if (hosted) {
				TestCommand.mkdirs(libDir());
				for (f in FileSystem.readDirectory(libDir())) try FileSystem.deleteFile('${libDir()}/$f') catch (_:Dynamic) {};
				task.async(_ -> buildHost());
			}
			log(Style.status("watching", Info, Style.path(e.sources.join(", "))));
			log(Style.status("devtools", Quiet, Style.path('ws://$at:${http.port}/__helder/devtools')));
		}
		var w = new SampledWatcher();
		rebuild(task, null);
		watch(w);
		while (true) {
			var changed = w.next();
			// (seen within the tick: half of it on average, and the debounce)
			var seen = haxe.Timer.stamp() - 0.07;
			for (f in changed)
				if (f.endsWith(".hx") && FileSystem.exists(f)) server.invalidate(f, cwd);
			rebuild(task, seen);
			watch(w);
		}
		return 0;
	}

	// what the last build read: its module files under the sources (Deps;
	// before any build typed, every .hx file there), their directories, the
	// assets and the overrides
	static function watch(w:SampledWatcher) {
		var roots = [for (s in e.sources) if (FileSystem.exists(s)) FileSystem.fullPath(s)];
		var under = (f:String) -> Lambda.exists(roots, r -> f.startsWith(r + "/") || f.startsWith(r + "\\"));
		var files = [], dirs = [];
		function walk(d:String, all:Bool)
			for (n in (try FileSystem.readDirectory(d) catch (_:Dynamic) [])) {
				var p = '$d/$n';
				if (n.startsWith(".") || n == "bin" || n == "node_modules") continue;
				if (FileSystem.isDirectory(p)) {
					dirs.push(p);
					walk(p, all);
				} else if (all || n.endsWith(".hx")) files.push(p);
			}
		var deps = try File.getContent(depsFile()).split("\n") catch (_:Dynamic) null;
		if (deps == null) for (r in roots) {
			dirs.push(r);
			walk(r, false);
		} else for (f in deps) if (f != "" && under(f)) {
			files.push(f);
			var d = Path.directory(f);
			if (!dirs.contains(d)) dirs.push(d);
		}
		if (FileSystem.exists('${e.root}/assets')) {
			var a = FileSystem.fullPath('${e.root}/assets');
			dirs.push(a);
			walk(a, true);
		}
		for (f in [e.hxml, '${e.root}/package.json']) if (f != null && FileSystem.exists(f)) files.push(FileSystem.fullPath(f));
		w.watch(files, dirs);
	}

	static function depsFile():String
		return Path.withoutExtension(out) + ".deps";

	// a status line (a terminal gone, its pipe closed: nothing printed, the rest goes on)
	static function log(s:String)
		Term.out(s);

	// helder dev ended: the spinner, the program and the compilation server
	// stopped, then the exit code
	@:coroutine static function shutdown(code:Int) {
		stopping = true;
		Term.done();
		var c = child;
		child = null;
		if (c != null && !c.exited) c.p.stop();
		// (a phone's output: logcat, simctl; the app itself stays)
		var l = phoneLog;
		phoneLog = null;
		if (l != null) l.stop(1);
		server.stop();
		Sys.exit(code);
	}

	// a build, then the program reloaded (or the errors shown)
	@:coroutine static function rebuild(task:Node, seen:Null<Float>) {
		building = true;
		// (natively: the running executable moved aside, it cannot be written over)
		var aside = out + ".running";
		var moved = !web && !hosted && mobile == null && child != null && FileSystem.exists(out) && (try {
			FileSystem.rename(out, aside);
			true;
		} catch (_:Dynamic) false);
		// (a Haxe string in the macro call: forward slashes, a Windows path's
		// backslashes would be escapes)
		var deps = (FileSystem.fullPath(Path.directory(out)) + "/" + Path.withoutDirectory(depsFile())).split("\\").join("/");
		var extra = ["-D", 'helder.name=${e.name}', "--macro", 'helder.cli.Deps.write("$deps")'];
		if (hosted) extra = extra.concat(["-D", "hxmc.shared", "-D", "hxmc.dev-host", "-D", "hxmc.exports=hxmc_dev_run,hxmc_dev_state", "helder.dev.Hosted"]);
		// (Windows: a DLL at a base of its own, not the one the running build's DLL has, nor the build's before)
		if (hosted && e.target.startsWith("windows-")) extra = extra.concat(["-D", "hxmc.dll-base=" + ["0x10000000", "0x30000000", "0x50000000"][(libCount + 1) % 3]]);
		// (a phone: the dev host's app, built for this server; once it runs
		// and is connected, each build a library swapped into it)
		swapping = installed && socket != null;
		if (mobile != null) extra = extra.concat(["-D", "hxmc.dev-host", "-D", "hxmc.exports=hxmc_dev_run,hxmc_dev_state"]);
		if (mobile == "android") extra = extra.concat(["-D", 'hxmc.dev-server=127.0.0.1:$appPort']);
		var artifact = switch mobile {
			case "android": swapping ? Android.library(out) : out;
			case "ios" if (swapping): '${libDir()}/next.dylib';
			case _: out;
		}
		var r = try switch mobile {
			case "android": Android.build(e, out, Dev, server, extra, true, !swapping);
			case "ios" if (swapping): BuildCommand.build(e, artifact, Dev, server, extra.concat(["-D", "hxmc.shared"]));
			case "ios": Ios.build(e, out, Dev, server, extra);
			case _: BuildCommand.build(e, out, Dev, server, extra);
		} catch (err:Dynamic) {
			Term.done();
			Term.err(Style.status("error", Fail, err is haxe.Exception ? (err : haxe.Exception).message : Std.string(err)));
			Sys.exit(1);
			null;
		}
		if (moved && !FileSystem.exists(out)) FileSystem.rename(aside, out);
		if (!r.ok) {
			lastError = r.messages == "" ? "the build failed" : r.messages;
			log(Style.status("failed", Fail, 'in ${Style.time(r.ms)}' + Style.dim(Style.sep() + (built ? "the last good build keeps running" : "waiting for a change"))));
			if (web) broadcast(haxe.Json.stringify({type: "error", message: lastError}));
			building = false;
			Devtools.buildError(r.ms, lastError);
			return;
		}
		var wasError = lastError != null;
		lastError = null;
		timing = seen == null ? null : {seen: seen, build: r.ms};
		log(Style.status(seen == null ? "built" : "rebuilt", Ok, 'in ${Style.time(r.ms)}' + Style.dim(Style.sep() + BuildCommand.size(artifact))));
		building = false;
		Devtools.built(r.ms, BuildCommand.size(artifact));
		var first = !built;
		built = true;
		if (web) {
			if (wasError) broadcast('{"type":"ok"}');
			if (clients.length > 0) {
				if (!first || wasError) broadcast('{"type":"reload"}');
			} else timing = null;
		} else if (mobile == "android") swapAndroid(task) else if (mobile == "ios") swapSimulator(task) else if (hosted) swapHosted(task) else reloadNative(task);
	}

	// the first frame of a reloaded build
	@:coroutine public static function measured() {
		if (timing == null) return;
		var ms = Math.round((haxe.Timer.stamp() - timing.seen) * 1000), build = timing.build;
		log(Style.status("reloaded", Ok, 'in ${Style.time(ms)}' + Style.dim(Style.sep() + 'build $build ms')));
		timing = null;
		Devtools.reloaded(ms, build);
	}

	// --- natively

	// the program's connection (JSON lines: @hxmc/cli's {"type"}, or the devtools' protocol)
	@:coroutine static function connection(s:Socket) {
		var before = socket;
		socket = s;
		var r = new Reader(s), line;
		try while ((line = r.readLine()) != null) {
			// (Android: a build's library asked for on a connection of its own, the bytes then the end)
			if (line.startsWith("lib ")) {
				if (socket == s) socket = before;
				var f = fetchable;
				if (f != null && f.n == line.substr(4).trim()) s.write(f.bytes, 0, f.bytes.length);
				s.close();
				return;
			}
			var m:Dynamic = try haxe.Json.parse(line) catch (_:Dynamic) null;
			if (m == null) continue;
			if (m.jsonrpc != null) {
				if (socket == s) Devtools.fromProgram(m, line);
				continue;
			}
			if (m.type == "frame") measured();
			if (m.type == "saved" && socket == s) saved = true;
		} catch (_:haxe.Exception) {}
		if (socket == s) {
			socket = null;
			Devtools.programGone();
		}
		s.close();
	}

	// a reload asked of the program: Runtime.reload when it speaks the protocol
	// (library: the dev host's next build, a file here; fetch: Android's, the
	// app asks for it on a connection of its own: "lib <fetch>")
	@:coroutine static function askReload(snapshot:String, ?library:String, ?fetch:String) {
		var params:Dynamic = {snapshot: snapshot};
		if (library != null) params.library = library;
		if (fetch != null) params.fetch = fetch;
		if (!Devtools.request("Runtime.reload", params, r -> if (r.error == null) saved = true)) {
			params.type = "reload";
			send(params);
		}
	}

	@:coroutine static function start(task:Node, withSnapshot:Bool, ?lib:String) {
		// (helder dev ending: no program started meanwhile, by a reload in flight)
		if (stopping) return;
		var env = Process.environment();
		env.set("HXMC_DEV", '127.0.0.1:$appPort');
		env.set("HXMC_DEV_PROTOCOL", Std.string(Devtools.PROTOCOL));
		if (withSnapshot || hosted) env.set("HXMC_DEV_SNAPSHOT", snapshot) else env.remove("HXMC_DEV_SNAPSHOT");
		var options = {env: env};
		var p = try hosted ? new Process(hostExe, [lib].concat(programArgs), options) : new Process(Path.isAbsolute(out) ? out : './$out', programArgs, options) catch (err:haxe.Exception) {
			Term.err(Style.status("error", Fail, 'the program did not start: ${err.message}'));
			null;
		}
		if (p == null) return;
		p.closeStdin();
		var c = new Child(p);
		child = c;
		saved = false;
		task.async(_ -> output(p.stdout, false));
		task.async(_ -> output(p.stderr, true));
		task.async(_ -> {
			c.code = p.wait();
			c.exited = true;
			p.close();
			if (child != c) return;
			child = null;
			switch ExitPolicy.decide(platform, c.code, c.replaced, stopping) {
				case Ignore:
				case WaitForChange:
					Term.err(Style.status("crashed", Fail, 'the program exited with code ${c.code}' + Style.dim("; the next change builds and starts it again")));
					Devtools.exited(c.code);
				case EndSession:
					// (ctrl-c reaches the program too, which may end first: the signal's exit code then)
					Async.delay(0.1);
					if (stopping) return;
					log(Style.status("closed", Quiet, "the program exited; stopping"));
					Devtools.exited(c.code);
					shutdown(0);
			}
		});
	}

	// the program's output, printed, and kept as log entries (Devtools)
	@:coroutine static function output(s:Stream.Source, err:Bool) {
		var r = new Reader(s), line;
		while ((line = r.readLine()) != null) {
			if (err) Term.err(line) else Term.out(line);
			Devtools.output(line, err);
		}
	}

	// the program snapshots and exits; the new build starts with its state
	@:coroutine static function reloadNative(task:Node) {
		var old = child, withSnapshot = false;
		if (old != null) {
			old.replaced = true;
			child = null;
			if (socket != null) {
				try FileSystem.deleteFile(snapshot) catch (_:Dynamic) {};
				saved = false;
				askReload(snapshot);
				// (a program that does not answer: stopped, a cold start)
				if (!until(() -> saved || old.exited, 3)) old.p.stop(1);
				withSnapshot = saved && FileSystem.exists(snapshot);
			} else old.p.stop(1);
			until(() -> old.exited, 3);
		}
		start(task, withSnapshot);
	}

	// the dev host: the running build snapshots, disposes and hands over to the new library
	@:coroutine static function swapHosted(task:Node) {
		until(() -> hostReady, 600);
		if (hostExe == null) {
			// (no host: a program per build, this one built again as an executable)
			hosted = false;
			out = exeOut;
			log(Style.status("note", Quiet, "without the dev host: each build a new process, its state carried over"));
			rebuild(task, null);
			return;
		}
		var lib = '${libDir()}/${++libCount}${libExt()}';
		FileSystem.rename(out, lib);
		// (the builds before the last: closed by the host; a file still loaded,
		// which Windows does not delete, tried again after the next build)
		if (libCount > 2) stale.push('${libDir()}/${libCount - 2}${libExt()}');
		for (f in stale.copy())
			if (!FileSystem.exists(f) || (try {
				FileSystem.deleteFile(f);
				true;
			} catch (_:Dynamic) false)) stale.remove(f);
		var c = child;
		if (c != null && socket != null) {
			try FileSystem.deleteFile(snapshot) catch (_:Dynamic) {};
			saved = false;
			// (the host hands over to the new build; if it ends meanwhile, that was the reload's)
			c.replaced = true;
			askReload(snapshot, native(FileSystem.fullPath(lib)));
			until(() -> saved || c.exited, 10);
			if (!c.exited) {
				c.replaced = false;
				return;
			}
		} else if (c != null) {
			// (a program that has not connected: stopped, a cold start)
			c.replaced = true;
			child = null;
			c.p.stop(1);
			until(() -> c.exited, 3);
		}
		start(task, FileSystem.exists(snapshot), native(FileSystem.fullPath(lib)));
	}

	// --- a phone

	// Android: the running app (the dev host, its activity keeping the
	// window, the GPU context and the input queue) fetches the new build's
	// library into its files and hands over to it in the same process; no
	// app connected (the first build, or it was closed): the APK installed
	// (again), the port reversed, the app started
	@:coroutine static function swapAndroid(task:Node) {
		var s = socket;
		if (swapping && s != null) {
			var n = Std.string(++libCount);
			fetchable = {n: n, bytes: File.getBytes(Android.library(out))};
			saved = false;
			askReload("-", null, n);
			until(() -> saved || socket != s, 10);
			return;
		}
		try {
			var id = App.android(e.name, e.config, true).id;
			// (gone while its library was built: the APK of that library)
			if (swapping) Android.pack(e, Android.library(out), out, true);
			Term.spin("installing on " + device.name);
			Android.install(device.id, out);
			Android.reverse(device.id, appPort);
			if (phoneLog == null) {
				phoneLog = Android.logcat(device.id);
				var l = phoneLog;
				if (l != null) task.async(_ -> output(l.stdout, false));
			}
			Android.start(device.id, id, Android.activity(out));
			Term.done();
			installed = true;
			log(Style.status("started", Ok, '$id on ${device.name}' + Style.dim(Style.sep() + "its output: logcat's hxmc")));
		} catch (err:Dynamic) {
			Term.done();
			Term.err(Style.status("error", Fail, Std.string(err) + Style.dim("; the next change tries again")));
		}
	}

	// the simulator: the running app (the dev host) loads the new build's
	// dylib from this machine's files and hands over to it; no app connected:
	// the app installed and launched, its output here (simctl --console)
	@:coroutine static function swapSimulator(task:Node) {
		var s = socket;
		if (swapping && s != null) {
			var lib = '${libDir()}/${++libCount}.dylib';
			FileSystem.rename('${libDir()}/next.dylib', lib);
			try FileSystem.deleteFile(snapshot) catch (_:Dynamic) {};
			saved = false;
			askReload(snapshot, FileSystem.fullPath(lib));
			until(() -> saved || socket != s, 10);
			return;
		}
		if (swapping) {
			// (gone while its dylib was built: the app built again, installed and launched)
			installed = false;
			rebuild(task, null);
			return;
		}
		try {
			var id = Ios.id(e);
			Term.spin("installing on " + device.name);
			Ios.install(device.id, out);
			Term.done();
			TestCommand.mkdirs(libDir());
			try FileSystem.deleteFile(snapshot) catch (_:Dynamic) {};
			// (the app before: ended by --terminate-running-process, not the user)
			var old = phoneLog;
			if (old != null) replacedLaunch = old;
			var p = Ios.launch(device.id, id, ["HXMC_DEV" => '127.0.0.1:$appPort', "HXMC_DEV_PROTOCOL" => Std.string(Devtools.PROTOCOL), "HXMC_DEV_SNAPSHOT" => snapshot]);
			p.closeStdin();
			phoneLog = p;
			installed = true;
			log(Style.status("started", Ok, '$id on ${device.name}'));
			task.async(_ -> output(p.stdout, false));
			task.async(_ -> output(p.stderr, true));
			task.async(_ -> {
				var code = p.wait();
				p.close();
				switch ExitPolicy.decide(Mobile, code, replacedLaunch == p, stopping) {
					case WaitForChange:
						if (phoneLog == p) phoneLog = null;
						log(Style.status("closed", Quiet, 'the app on ${device.name} ended' + Style.dim("; the next change starts it again")));
						Devtools.exited(code);
					case _:
				}
			});
		} catch (err:Dynamic) {
			Term.done();
			Term.err(Style.status("error", Fail, Std.string(err) + Style.dim("; the next change tries again")));
		}
	}

	// (the simulator's launch that a relaunch ended)
	static var replacedLaunch:Null<Process> = null;

	static function libDir():String
		return Path.withoutExtension(out) + ".dev";

	// a build's shared library: Windows' DLL, macOS's dylib, else ELF's
	static function libExt():String
		return e.target.startsWith("windows-") ? ".dll" : e.target.startsWith("macos-") ? ".dylib" : ".so";

	// a path as the system's loader takes it (Windows: backslashes)
	static function native(p:String):String
		return e.target.startsWith("windows-") ? p.split("/").join("\\") : p;

	// the dev host's executable, built once (by its sources' hash and the compiler's)
	@:coroutine static function buildHost() {
		var src = e.helder + "/helder/dev";
		var tool = Compiler.tool();
		var key = File.getContent('$src/DevHost.hx') + (FileSystem.exists(tool) ? Std.string(FileSystem.stat(tool).mtime.getTime()) : tool);
		var dir = cache() + "/dev-host";
		var win = e.target.startsWith("windows-");
		var exe = '$dir/host-' + haxe.crypto.Md5.encode(key).substr(0, 16) + (win ? ".exe" : "");
		if (!FileSystem.exists(exe)) {
			// (a cache not writable: the build fails, the program runs without the host)
			try TestCommand.mkdirs(dir) catch (_:Dynamic) {};
			var tmp = Path.withoutExtension(exe) + "." + Std.random(1 << 30) + (win ? ".exe" : "");
			var p = new Process(tool, ["-cp", e.helder, "-main", "helder.dev.DevHost"].concat(e.target.startsWith("linux-") ? ["-D", "hxmc.libc=glibc"] : [])
				.concat(["--custom-target", 'hxmc=$tmp']));
			p.closeStdin();
			var lines = [];
			Async.scope(t -> {
				t.async(_ -> Lines.collect(p.stdout, lines));
				t.async(_ -> Lines.collect(p.stderr, lines));
				null;
			});
			var code = p.wait();
			p.close();
			if (code != 0 || !FileSystem.exists(tmp)) {
				Term.err(Style.status("warning", Warn, "the dev host does not build:"));
				Term.write(Diagnostics.format(lines.join("\n")), true);
				hostReady = true;
				return;
			}
			// (another session's, built at the same time: kept)
			try FileSystem.rename(tmp, exe) catch (_:Dynamic) try FileSystem.deleteFile(tmp) catch (_:Dynamic) {};
		}
		hostExe = exe;
		hostReady = true;
	}

	// helder's cache (the dev host, the Android debug key): HELDER_CACHE, else
	// <the user's cache>/helder
	public static function cache():String {
		var env = Sys.getEnv("HELDER_CACHE");
		return env != null && env != "" ? env.split("\\").join("/") : cacheDir() + "/helder";
	}

	// the user's cache: Windows' local application data, macOS's Library/Caches, else XDG's
	static function cacheDir():String {
		var home = Sys.getEnv("HOME") ?? Sys.getEnv("USERPROFILE") ?? ".";
		return switch Sys.systemName() {
			case "Windows": (Sys.getEnv("LOCALAPPDATA") ?? '$home/AppData/Local').split("\\").join("/");
			case "Mac": '$home/Library/Caches';
			case _: Sys.getEnv("XDG_CACHE_HOME") ?? '$home/.cache';
		}
	}

	@:coroutine static function send(m:Dynamic)
		sendLine(haxe.Json.stringify(m));

	// a line to the program
	@:coroutine public static function sendLine(line:String) {
		var s = socket;
		if (s != null) try s.writeString(line + "\n") catch (_:haxe.Exception) {}
	}

	// f() true within seconds (polled)
	@:coroutine static function until(f:Void->Bool, seconds:Float):Bool {
		var t0 = haxe.Timer.stamp();
		while (!f()) {
			if (haxe.Timer.stamp() - t0 > seconds) return false;
			Async.delay(0.005);
		}
		return true;
	}

	// --- web

	static function listen(address:String, port:Int):Null<Server> {
		for (p in port...port + 20)
			try return Server.listen(address, p) catch (_:Dynamic) {}
		return null;
	}

	@:coroutine static function broadcast(text:String)
		for (ws in clients.copy())
			try ws.send(text) catch (_:haxe.Exception) clients.remove(ws);

	@:coroutine static function serve(req:Request):Null<Response> {
		var p = req.path;
		if (p == "/__helder/devtools" && WebSocket.wants(req)) {
			Devtools.serve(WebSocket.upgrade(req));
			return null;
		}
		if (!web) return Response.text("helder dev: the devtools' WebSocket is at /__helder/devtools\n", 404);
		if (p == "/__hxmc/ws" && WebSocket.wants(req)) {
			var ws = WebSocket.upgrade(req);
			clients.push(ws);
			if (lastError != null) ws.send(haxe.Json.stringify({type: "error", message: lastError}));
			var m;
			while ((m = try ws.receive() catch (_:haxe.Exception) null) != null) {
				var j:Dynamic = try haxe.Json.parse(m) catch (_:Dynamic) null;
				if (j?.type == "frame") measured();
				if (j?.type == "log") {
					Term.out(j.text);
					Devtools.output(j.text, false);
				}
			}
			clients.remove(ws);
			return null;
		}
		if (p == "/" || p == "/index.html") {
			until(() -> built, 600);
			var pkgs = Page.packages(e.helder, out);
			var fonts = [for (f in Page.fonts(pkgs)) "/__hxmc/fonts/" + Path.withoutDirectory(f)];
			return Response.text(Page.html(e.name + " (helder dev)", "/__hxmc/app.wasm", "/__hxmc/pkg/helder/", pkgs, fonts, true), 200, "text/html; charset=utf-8");
		}
		if (p == "/__hxmc/app.wasm") {
			until(() -> !building && (built || lastError != null), 600);
			// (a swap after a build that failed: the running build stays)
			if (lastError != null && req.query.contains("swap")) return nostore(new Response(409));
			if (!FileSystem.exists(out)) return Response.text("no build\n", 404);
			var res = new Response(200, File.getBytes(out));
			res.headers.set("content-type", "application/wasm");
			return nostore(res);
		}
		if (p == "/__hxmc/os/browser.mjs") return nostore(Http.file(e.helder, "/helder/os/browser.mjs"));
		if (p.startsWith("/__hxmc/pkg/helder/") && p.endsWith(".mjs"))
			return nostore(Http.file(e.helder + "/helder", p.substr("/__hxmc/pkg/helder".length)));
		if (p.startsWith("/__hxmc/fonts/")) {
			var f = Lambda.find(Page.fonts(["text"]), f -> Path.withoutDirectory(f) == p.substr(14));
			if (f != null) return Http.file(Path.directory(f), "/" + Path.withoutDirectory(f));
		}
		// (the project's files: what the program fetches)
		return nostore(Http.file(e.root, p)) ?? Response.text("not found\n", 404);
	}

	static function nostore(r:Null<Response>):Null<Response> {
		if (r != null) r.headers.set("cache-control", "no-store");
		return r;
	}
}

private class Child {
	public final p:Process;
	public var exited = false;
	public var code = 0;
	// helder dev ends it itself (a reload): its exit is not the user's
	public var replaced = false;

	public function new(p)
		this.p = p;
}
