package helder.cli;

import haxe.io.Path;
import helder.async.*;
import helder.async.http.Http;
import helder.async.http.WebSocket;
import helder.cli.BuildCommand.Lines;
import helder.cli.Compiler.CompileServer;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `helder dev [host | web] [entry]`: the dev loop, ported from @hxmc/cli's
// dev.mjs. The compiler stays resident (CompileServer, --server-connect);
// what the last build read is watched (SampledWatcher: the module files
// Deps writes, their directories, and assets/), and a change builds again
// with -D hxmc.dev. A build with errors changes
// nothing: the last good build keeps running, the errors show here (and in
// the page's overlay). A build that compiles reloads the program, its state
// carried over by key (helder.dev.Hot's snapshot):
// - natively, the program started with HXMC_DEV=<host:port> (our socket for
//   it, JSON lines) and HXMC_DEV_SNAPSHOT=<file>. On Linux (glibc) it runs
//   in the dev host (helder.dev.DevHost, built once and cached): each build
//   a shared library, a reload {"type":"reload","snapshot","library"}: the
//   build writes its snapshot, disposes and returns, the host loads the new
//   one in the same process (the window and GL context kept). Elsewhere
//   (HELDER_DEV_HOST=0 too) {"type":"reload","snapshot"}: the program writes
//   it and exits, the new build starts with it;
// - web: a page at http://127.0.0.1:<port>/ (page.html) running the module
//   with its packages' browser modules, told over a WebSocket at /__hxmc/ws
//   ({"type":"reload"}, {"type":"error","message"}, {"type":"ok"}): it swaps
//   the new build in, in the same page.
// The program answers {"type":"saved"} and {"type":"frame"} (its first
// frame: the reload's time, from the change seen). Natively a program with
// helder.devtools' agent (HXMC_DEV_PROTOCOL=1) speaks JSON-RPC instead
// (src/helder/devtools/README.md): Runtime.hello, Runtime.reload answered
// once saved, Runtime.ready; Devtools relays it to the tools connected at
// /__helder/devtools on the HTTP port (natively too: bin/dev/devtools.json
// names it).
class DevCommand {
	static final usage = [
		"helder dev [host | web] [entry] [--port <n>] [--host <address>] [-- program arguments...]",
		"",
		"  entry: a project directory (the default: .), an example's directory or a .hx file",
		"  --port: the page's (web; 4321, else the next free one)",
	].join("\n");

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
	static var socket:Null<Socket> = null;
	static var saved = false;
	static var appPort = 0;
	static var programArgs:Array<String> = [];
	static var hostExe:Null<String> = null;
	static var hostReady = false;
	static var libCount = 0;
	// web: the pages connected
	static final clients:Array<WebSocket> = [];

	@:coroutine public static function run(task:Node, args:Array<String>):Int {
		var rest = [], port = Std.parseInt(Sys.getEnv("HELDER_DEV_PORT") ?? "") ?? 4321, address = "127.0.0.1";
		var i = 0;
		while (i < args.length) {
			var a = args[i++];
			switch a {
				case "--":
					programArgs = args.slice(i);
					break;
				case "--port" if (i < args.length): port = Std.parseInt(args[i++]) ?? port;
				case "--host" if (i < args.length): address = args[i++];
				case "-h" | "--help":
					Sys.println(usage);
					return 0;
				case _ if (a.startsWith("-")):
					Sys.println('helder dev: unknown option $a\n\n$usage');
					return 2;
				case _: rest.push(a);
			}
		}
		e = try Entry.resolve(rest) catch (err:Dynamic) {
			Sys.println('helder dev: $err');
			return 2;
		}
		web = e.isWeb();
		if (!web && e.target != Compiler.hostTarget()) {
			Sys.println('helder dev: ${e.target} is not this machine (${Compiler.hostTarget()}); helder build ${e.target} builds for it');
			return 2;
		}
		if (web) e.target = "web";
		cwd = Sys.getCwd();
		hosted = !web && e.target.startsWith("linux-") && Sys.getEnv("HELDER_DEV_HOST") != "0";
		out = e.out("dev/" + (web ? "web" : e.target));
		if (hosted) out = Path.withoutExtension(out) + ".so";
		var dir = Path.directory(out) == "" ? "." : Path.directory(out);
		TestCommand.mkdirs(dir);
		snapshot = FileSystem.fullPath(dir) + '/${e.name}.snapshot';
		try FileSystem.deleteFile(snapshot) catch (_:Dynamic) {};
		try FileSystem.deleteFile(depsFile()) catch (_:Dynamic) {};
		server = CompileServer.start(task);
		if (server == null) {
			Sys.println("helder dev: the compilation server did not start (" + Compiler.tool() + ")");
			return 1;
		}
		var http = listen(address, port);
		if (http == null) {
			Sys.println('helder dev: no free port from $port');
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
			log('http://$at:${http.port}/ (${e.main}; watching ${e.sources.join(", ")})');
		} else {
			var app = Server.listen("127.0.0.1", 0);
			appPort = app.port;
			task.async(_ -> while (true) {
				var s = app.accept();
				task.async(_ -> connection(s));
			});
			if (hosted) {
				TestCommand.mkdirs(libDir());
				for (f in FileSystem.readDirectory(libDir())) try FileSystem.deleteFile('${libDir()}/$f') catch (_:Dynamic) {};
				task.async(_ -> buildHost());
			}
			log('${e.main} (watching ${e.sources.join(", ")}; devtools at ws://$at:${http.port}/__helder/devtools)');
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

	static function log(s:String)
		Sys.println("helder dev: " + s);

	// a build, then the program reloaded (or the errors shown)
	@:coroutine static function rebuild(task:Node, seen:Null<Float>) {
		building = true;
		// (natively: the running executable moved aside, it cannot be written over)
		var aside = out + ".running";
		var moved = !web && !hosted && child != null && FileSystem.exists(out) && (try {
			FileSystem.rename(out, aside);
			true;
		} catch (_:Dynamic) false);
		// (a Haxe string in the macro call: forward slashes, a Windows path's
		// backslashes would be escapes)
		var deps = (FileSystem.fullPath(Path.directory(out)) + "/" + Path.withoutDirectory(depsFile())).split("\\").join("/");
		var extra = ["-D", 'helder.name=${e.name}', "--macro", 'helder.cli.Deps.write("$deps")'];
		if (hosted) extra = extra.concat(["-D", "hxmc.shared", "-D", "hxmc.dev-host", "-D", "hxmc.exports=hxmc_dev_run,hxmc_dev_state", "helder.dev.Hosted"]);
		var r = try BuildCommand.build(e, out, Dev, server, extra) catch (err:haxe.Exception) {
			Sys.println("helder dev: " + err.message);
			Sys.exit(1);
			null;
		}
		if (moved && !FileSystem.exists(out)) FileSystem.rename(aside, out);
		if (!r.ok) {
			lastError = r.messages == "" ? "the build failed" : r.messages;
			log('error (build ${r.ms} ms); ' + (built ? "the last good build keeps running" : "waiting for a change"));
			if (web) broadcast(haxe.Json.stringify({type: "error", message: lastError}));
			building = false;
			Devtools.buildError(r.ms, lastError);
			return;
		}
		var wasError = lastError != null;
		lastError = null;
		timing = seen == null ? null : {seen: seen, build: r.ms};
		log((seen == null ? "built" : "rebuilt") + ' in ${r.ms} ms (${BuildCommand.size(out)})');
		building = false;
		Devtools.built(r.ms, BuildCommand.size(out));
		var first = !built;
		built = true;
		if (web) {
			if (wasError) broadcast('{"type":"ok"}');
			if (clients.length > 0) {
				if (!first || wasError) broadcast('{"type":"reload"}');
			} else timing = null;
		} else if (hosted) swapHosted(task) else reloadNative(task);
	}

	// the first frame of a reloaded build
	@:coroutine public static function measured() {
		if (timing == null) return;
		var ms = Math.round((haxe.Timer.stamp() - timing.seen) * 1000), build = timing.build;
		log('reloaded in $ms ms (build $build ms)');
		timing = null;
		Devtools.reloaded(ms, build);
	}

	// --- natively

	// the program's connection (JSON lines: @hxmc/cli's {"type"}, or the devtools' protocol)
	@:coroutine static function connection(s:Socket) {
		socket = s;
		var r = new Reader(s), line;
		try while ((line = r.readLine()) != null) {
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
	@:coroutine static function askReload(snapshot:String, ?library:String) {
		var params:Dynamic = library == null ? {snapshot: snapshot} : {snapshot: snapshot, library: library};
		if (!Devtools.request("Runtime.reload", params, r -> if (r.error == null) saved = true))
			send(library == null ? {type: "reload", snapshot: snapshot} : {type: "reload", snapshot: snapshot, library: library});
	}

	@:coroutine static function start(task:Node, withSnapshot:Bool, ?lib:String) {
		// (the program's environment set around the spawn, as hxmc's processRun takes none: removable once it does)
		Sys.putEnv("HXMC_DEV", '127.0.0.1:$appPort');
		Sys.putEnv("HXMC_DEV_PROTOCOL", Std.string(Devtools.PROTOCOL));
		if (withSnapshot || hosted) Sys.putEnv("HXMC_DEV_SNAPSHOT", snapshot);
		var p = try hosted ? new Process(hostExe, [lib].concat(programArgs)) : new Process(Path.isAbsolute(out) ? out : './$out', programArgs) catch (err:haxe.Exception) {
			log('the program did not start: ${err.message}');
			null;
		}
		Sys.putEnv("HXMC_DEV", null);
		Sys.putEnv("HXMC_DEV_PROTOCOL", null);
		Sys.putEnv("HXMC_DEV_SNAPSHOT", null);
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
			if (child == c) {
				child = null;
				log('the program ended (${c.code}); it starts again with the next build');
				Devtools.exited(c.code);
			}
		});
	}

	// the program's output, printed, and kept as log entries (Devtools)
	@:coroutine static function output(s:Stream.Source, err:Bool) {
		var r = new Reader(s), line;
		while ((line = r.readLine()) != null) {
			if (err) Sys.stderr().writeString(line + "\n") else Sys.println(line);
			Devtools.output(line, err);
		}
	}

	// the program snapshots and exits; the new build starts with its state
	@:coroutine static function reloadNative(task:Node) {
		var old = child, withSnapshot = false;
		if (old != null) {
			child = null;
			if (socket != null) {
				try FileSystem.deleteFile(snapshot) catch (_:Dynamic) {};
				saved = false;
				askReload(snapshot);
				// (a program that does not answer: stopped, a cold start)
				if (!until(() -> saved || old.exited, 3)) old.p.kill();
				withSnapshot = saved && FileSystem.exists(snapshot);
			} else old.p.kill();
			until(() -> old.exited, 3);
		}
		start(task, withSnapshot);
	}

	// the dev host: the running build snapshots, disposes and hands over to the new library
	@:coroutine static function swapHosted(task:Node) {
		until(() -> hostReady, 600);
		if (hostExe == null) return;
		var lib = '${libDir()}/${++libCount}.so';
		FileSystem.rename(out, lib);
		// (two builds back: closed by the host)
		try FileSystem.deleteFile('${libDir()}/${libCount - 2}.so') catch (_:Dynamic) {};
		var c = child;
		if (c != null && socket != null) {
			try FileSystem.deleteFile(snapshot) catch (_:Dynamic) {};
			saved = false;
			askReload(snapshot, FileSystem.fullPath(lib));
			until(() -> saved || c.exited, 10);
			if (!c.exited) return;
		} else if (c != null) {
			// (a program that has not connected: stopped, a cold start)
			child = null;
			c.p.kill();
			until(() -> c.exited, 3);
		}
		start(task, FileSystem.exists(snapshot), FileSystem.fullPath(lib));
	}

	static function libDir():String
		return Path.withoutExtension(out) + ".dev";

	// the dev host's executable, built once (by its sources' hash and the compiler's)
	@:coroutine static function buildHost() {
		var src = e.helder + "/helder/dev";
		var tool = Compiler.tool();
		var key = File.getContent('$src/DevHost.hx') + (FileSystem.exists(tool) ? Std.string(FileSystem.stat(tool).mtime.getTime()) : tool);
		var home = Sys.getEnv("XDG_CACHE_HOME") ?? (Sys.getEnv("HOME") ?? ".") + "/.cache";
		var dir = '$home/helder/dev-host';
		var exe = '$dir/host-' + haxe.crypto.Md5.encode(key).substr(0, 16);
		if (!FileSystem.exists(exe)) {
			TestCommand.mkdirs(dir);
			var tmp = exe + "." + Std.random(1 << 30);
			var p = new Process(tool, ["-cp", e.helder, "-main", "helder.dev.DevHost", "-D", "hxmc.libc=glibc", "--custom-target", 'hxmc=$tmp']);
			p.closeStdin();
			var lines = [];
			Async.scope(t -> {
				t.async(_ -> Lines.collect(p.stdout, lines));
				t.async(_ -> Lines.collect(p.stderr, lines));
				null;
			});
			var code = p.wait();
			p.close();
			if (code != 0) {
				log("the dev host does not build:\n" + lines.join("\n"));
				hostReady = true;
				return;
			}
			FileSystem.rename(tmp, exe);
		}
		hostExe = exe;
		hostReady = true;
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
					Sys.println(j.text);
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

	public function new(p)
		this.p = p;
}
