package helder.cli;

import helder.cli.Style.Tone;
import haxe.io.Bytes;
import haxe.io.Path;
import helder.async.*;
import sys.FileSystem;

using StringTools;

// The compiler: helder's (hxmc's with helder's frontends: TypeScript, markup
// in any function), built from helder's sources by typescript(); without
// them (or node to build it), hxmc's native one from the platform package beside
// @hxmc/cli (node_modules/@hxmc/<os>-<cpu>, found from the working
// directory up, then from the CLI's own directory up), given what
// @hxmc/cli's launcher (hxmc/bootstrap/launcher.mjs) gives it: upstream's
// std (HAXE_STD_PATH) and hxmc's (HXMC_STD), so that no node runs (the
// runtime objects it finds itself). HAXE names another one
// (run as it is); without a platform package, node_modules/.bin/haxe (the
// launcher, under node), else `haxe` on the PATH.
class Compiler {
	static var found:Null<String> = null;

	public static function tool():String {
		if (found == null) found = find();
		return found;
	}

	static function find():String {
		var env = Sys.getEnv("HAXE");
		if (env != null && env != "") return env;
		var hxmc = native();
		var build = locate("src/helder/compiler/build.mjs") ?? locate("node_modules/helder/src/helder/compiler/build.mjs");
		if (build == null) return hxmc;
		return try own(Path.directory(Path.directory(Path.directory(build)))) catch (err:Dynamic) {
			Term.err(Style.status("warning", Warn, '$err\nhxmc\'s compiler instead: markup only in classes that implement helder.view.Markup'));
			hxmc;
		}
	}

	static var helders:Null<String> = null;

	static function native():String {
		var win = Sys.systemName() == "Windows";
		var cli = locate("node_modules/@hxmc/cli/package.json");
		if (cli != null) {
			var dir = Path.directory(Path.directory(cli));
			if ((Sys.getEnv("HXMC_STD") ?? "") == "") Sys.putEnv("HXMC_STD", '$dir/cli/hxmc/bootstrap/hxmc-std');
			var plat = platformPackage(), exe = '$dir/$plat/' + (win ? "haxe.exe" : "haxe");
			if (FileSystem.exists(exe)) {
				if ((Sys.getEnv("HAXE_STD_PATH") ?? "") == "") Sys.putEnv("HAXE_STD_PATH", '$dir/cli/haxe/upstream/std');
				// (the runtime objects: the compiler finds its own beside itself,
				// <its dir>/<target>/rt.o, and the other platform packages of its
				// version, cross builds', HXMC_RT_DIR's added: hxmc #93; Android's,
				// not on npm, fetched by Runtime.ensure into HXMC_RT_DIR)
				return exe;
			}
		}
		var bin = locate("node_modules/.bin/" + (win ? "haxe.cmd" : "haxe"));
		Term.err(Style.status("warning", Warn, 'no native compiler (node_modules/@hxmc/${platformPackage()}): ${bin ?? "haxe"} instead, through node'));
		return bin ?? (win ? "haxe.cmd" : "haxe");
	}

	// helder's compiler in tool()'s place (TypeScript programs, helder.typescript):
	// hxmc's compiler with helder's hooks and frontends (helder.compiler),
	// built once per hxmc version and per its sources into the user's cache by
	// src/helder/compiler/build.mjs
	// (node: it fetches hxmc's compiler sources until npm ships them)
	public static function typescript(helder:String) {
		tool();
		if (helders != null) return;
		found = own(helder);
	}

	// (helder's compiler, built by build.mjs from helder's sources; hxmc's
	// native compiler's environment set first: its std)
	static function own(helder:String):String {
		var node = Sys.getEnv("HELDER_NODE") ?? "node";
		var p = new sys.io.Process(node, ['$helder/helder/compiler/build.mjs']);
		var exe = StringTools.trim(p.stdout.readAll().toString()), err = p.stderr.readAll().toString(), code = p.exitCode();
		p.close();
		if (code != 0 || !FileSystem.exists(exe)) throw 'helder\'s compiler does not build:\n$err';
		// (its first build in this cache: what it fetched and built)
		for (line in err.split("\n")) if (line != "") Term.err(Style.status("compiler", Info, line));
		helders = exe;
		return exe;
	}

	// hxmc's std, which a compilation server's builds are given last (as the
	// compiler gives its own builds: hxmc.HaxeMain), null if not known
	public static function hxmcStd():Null<String> {
		tool();
		var d = Sys.getEnv("HXMC_STD");
		return d != null && d != "" && FileSystem.exists(d) ? d : null;
	}

	// the first rel under the working directory or one above it, else under the CLI's directory or one above
	public static function locate(rel:String):Null<String> {
		for (start in [Sys.getCwd(), Path.directory(Sys.programPath())]) {
			var d = FileSystem.fullPath(start);
			while (d != null && d != "") {
				var p = Path.join([d, rel]);
				if (FileSystem.exists(p)) return p;
				var up = Path.directory(d);
				if (up == d || up == "") break;
				d = up;
			}
		}
		return null;
	}

	// npm's name of this machine's platform package (linux-x64)
	static function platformPackage():String {
		var t = hostTarget().split("-");
		return ["linux" => "linux", "macos" => "darwin", "windows" => "win32"][t[0]] + "-" + (t[1] == "arm64" ? "arm64" : "x64");
	}

	// hxmc's name of this machine (linux-x86_64)
	public static function hostTarget():String {
		#if (target.name == "hxmc")
		var os = ["linux", "macos", "windows", "wasi"][hxmc.unsafe.Mem.os()];
		return os + "-" + (hxmc.unsafe.Mem.arm() ? "arm64" : "x86_64");
		#else
		return (Sys.systemName() == "Windows" ? "windows" : Sys.systemName() == "Mac" ? "macos" : "linux") + "-x86_64";
		#end
	}

	// a compilation server for `--connect` (`haxe --wait <port>`): its port and
	// process (`process.stop()` ends it), null if none started
	@:coroutine public static function start():Null<{port:Int, process:Process}> {
		// (a free port: one the system gives, closed again)
		var s = Server.listen("127.0.0.1", 0);
		var port = s.port;
		s.close();
		var p = try new Process(tool(), ["--wait", Std.string(port)]) catch (_:haxe.Exception) return null;
		p.closeStdin();
		// (ready once it accepts a connection: one without a request leaves it running)
		for (_ in 0...50) {
			try {
				Socket.connect("127.0.0.1", port).close();
				return {port: port, process: p};
			} catch (_:haxe.Exception) {}
			Async.delay(0.1);
		}
		p.stop();
		p.close();
		return null;
	}
}

// The compiler as a resident compilation server the CLI drives, as
// @hxmc/cli's dev.mjs does: `--server-connect`, the server connecting to a
// port of ours and taking its requests on that one connection (arguments
// one per line, after their length, a 32-bit little-endian integer; the
// answer after its length too, in lines: \x01 output, \x02 failure, any
// other a message). A request at a time.
class CompileServer {
	final process:Process;
	final socket:Socket;
	final reader:Reader;
	final lock = new Lock();
	// the server's own output, the last of it (when it stops)
	public var output(default, null) = "";

	function new(process, socket) {
		this.process = process;
		this.socket = socket;
		reader = new Reader(socket);
	}

	// started, and connected (null: it did not connect)
	@:coroutine public static function start(task:Node):Null<CompileServer> {
		var link = Server.listen("127.0.0.1", 0);
		// (a resident compiler keeps what it makes: a large nursery and old space spare it collections)
		// (tool() first: it sets the compiler's variables, the std's)
		var tool = Compiler.tool(), env = Process.environment();
		for (k => v in ["RT_OLD_MB" => "4096", "RT_MINOR_KB" => "32768"])
			if (!env.exists(k)) env.set(k, v);
		var p = try new Process(tool, ["--server-connect", '127.0.0.1:${link.port}'], {env: env}) catch (e:haxe.Exception) {
			link.close();
			Term.err(Style.status("error", Fail, '$tool: ${e.message}'));
			return null;
		}
		p.closeStdin();
		var sock = try Async.timeout(30, _ -> link.accept()) catch (_:haxe.Exception) null;
		link.close();
		if (sock == null) {
			p.stop();
			p.close();
			return null;
		}
		var s = new CompileServer(p, sock);
		for (pipe in [p.stdout, p.stderr])
			task.async(_ -> {
				var r = new Reader(pipe), line;
				while ((line = r.readLine()) != null) s.output = (s.output + line + "\n").substr(-8192);
			});
		return s;
	}

	// a build: its words, run in cwd; whether it compiled, its messages (errors and warnings)
	@:coroutine public function request(words:Array<String>, cwd:String):{ok:Bool, messages:String} {
		lock.acquire();
		try {
			var std = Compiler.hxmcStd();
			var body = Bytes.ofString(["--cwd", cwd].concat(words).concat(std == null || words[0] == "--display" ? [] : ["-cp", std]).join("\n"));
			var head = Bytes.alloc(4);
			head.setInt32(0, body.length);
			socket.write(head, 0, 4);
			socket.write(body, 0, body.length);
			var n = reader.readBytes(4).getInt32(0);
			var answer = reader.readBytes(n).toString();
			lock.release();
			var ok = true, messages = [];
			for (line in answer.split("\n")) {
				if (line.startsWith("\x01")) {
					var text = line.substr(1).split("\x01").join("\n");
					Term.write(text.endsWith("\n") ? text.substr(0, text.length - 1) : text);
				}
				else if (line.startsWith("\x02")) ok = false;
				else if (line != "") messages.push(line);
			}
			return {ok: ok, messages: messages.join("\n")};
		} catch (e:haxe.Exception) {
			lock.release();
			throw new haxe.Exception("the compilation server stopped\n" + output.substr(-2000));
		}
	}

	// a file changed: the server compares a file's time, which two saves in one second share
	@:coroutine public function invalidate(file:String, cwd:String)
		request(["--display", haxe.Json.stringify({jsonrpc: "2.0", id: 1, method: "server/invalidate", params: {file: file}})], cwd);

	// its connection closed, then the process asked to end (SIGTERM) and
	// ended (SIGKILL) if it has not within 2 s
	@:coroutine public function stop() {
		socket.close();
		process.stop();
		process.close();
	}
}
