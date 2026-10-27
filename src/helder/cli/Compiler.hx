package helder.cli;

import haxe.io.Bytes;
import haxe.io.Path;
import helder.async.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The compiler: hxmc's native one from the platform package beside
// @hxmc/cli (node_modules/@hxmc/<os>-<cpu>, found from the working
// directory up, then from the CLI's own directory up), given what
// @hxmc/cli's launcher (hxmc/bootstrap/launcher.mjs) gives it: upstream's
// std (HAXE_STD_PATH), hxmc's (HXMC_STD) and the runtime objects'
// directories (HXMC_RT_DIR), so that no node runs. HAXE names another one
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
		var win = Sys.systemName() == "Windows";
		var cli = locate("node_modules/@hxmc/cli/package.json");
		if (cli != null) {
			var dir = Path.directory(Path.directory(cli));
			if ((Sys.getEnv("HXMC_STD") ?? "") == "") Sys.putEnv("HXMC_STD", '$dir/cli/hxmc/bootstrap/hxmc-std');
			var plat = platformPackage(), exe = '$dir/$plat/' + (win ? "haxe.exe" : "haxe");
			if (FileSystem.exists(exe)) {
				if ((Sys.getEnv("HAXE_STD_PATH") ?? "") == "") Sys.putEnv("HAXE_STD_PATH", '$dir/cli/haxe/upstream/std');
				// (this machine's runtime objects, then the other platform packages' (cross
				// builds), HXMC_RT_DIR's, and the npm cache's, as rtDirs() has them)
				var dirs = ['$dir/$plat'];
				for (n in (try FileSystem.readDirectory(dir) catch (_:Dynamic) []))
					if (n != plat && n != "cli" && FileSystem.isDirectory('$dir/$n')) dirs.push('$dir/$n');
				var own = Sys.getEnv("HXMC_RT_DIR") ?? "";
				if (own != "") dirs.push(own);
				var version = try haxe.Json.parse(File.getContent(cli)).version catch (_:Dynamic) "";
				dirs.push(cacheBase() + "/npm/" + version);
				Sys.putEnv("HXMC_RT_DIR", dirs.join(win ? ";" : ":"));
				return exe;
			}
		}
		var bin = locate("node_modules/.bin/" + (win ? "haxe.cmd" : "haxe"));
		Sys.println('helder: no native compiler (node_modules/@hxmc/${platformPackage()}): ${bin ?? "haxe"} instead, through node');
		return bin ?? (win ? "haxe.cmd" : "haxe");
	}

	// hxmc's std, which a compilation server's builds are given last (as the
	// compiler gives its own builds: hxmc.HaxeMain), null if not known
	public static function hxmcStd():Null<String> {
		tool();
		var d = Sys.getEnv("HXMC_STD");
		return d != null && d != "" && FileSystem.exists(d) ? d : null;
	}

	// the first rel under the working directory or one above it, else under the CLI's directory or one above
	static function locate(rel:String):Null<String> {
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

	// the module cache's base (launcher.mjs's cacheBase)
	static function cacheBase():String {
		var own = Sys.getEnv("HXMC_CACHE");
		if (own != null && own != "") return own;
		var home = Sys.getEnv("HOME") ?? Sys.getEnv("USERPROFILE") ?? ".";
		return switch Sys.systemName() {
			case "Windows": (Sys.getEnv("LOCALAPPDATA") ?? '$home/AppData/Local') + "/hxmc/cache";
			case "Mac": '$home/Library/Caches/hxmc';
			case _:
				var xdg = Sys.getEnv("XDG_CACHE_HOME");
				(xdg != null && xdg.startsWith("/") ? xdg : '$home/.cache') + "/hxmc";
		}
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

	// a compilation server for `--connect` (`haxe --wait <port>`): its port, null if none started
	@:coroutine public static function start():Null<Int> {
		// (a free port: one the system gives, closed again)
		var s = Server.listen("127.0.0.1", 0);
		var port = s.port;
		s.close();
		var p = try new Process(tool(), ["--wait", Std.string(port)]) catch (_:haxe.Exception) return null;
		p.closeStdin();
		// (ready once it answers a request: one without any ends hxmc's server,
		// which hxmc a85b139 fixes; that one also finds the runtime objects
		// without the HXMC_RT_DIR find() sets: both removable with its nightly)
		for (_ in 0...50) {
			try {
				var c = Socket.connect("127.0.0.1", port);
				c.writeString("--version\n\x00");
				var answer = new Reader(c).readAll().toString();
				c.close();
				if (answer.length > 0) return port;
			} catch (_:haxe.Exception) {}
			Async.delay(0.1);
		}
		p.kill();
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
		// (a resident compiler keeps what it makes: a large nursery and old space spare it collections;
		// set around the spawn, as hxmc's processRun takes no environment: removable once it does)
		var env = ["RT_OLD_MB" => "4096", "RT_MINOR_KB" => "32768"];
		var saved = [for (k => v in env) k => Sys.getEnv(k)];
		for (k => v in env) if (saved[k] == null) Sys.putEnv(k, v);
		var p = try new Process(Compiler.tool(), ["--server-connect", '127.0.0.1:${link.port}']) catch (e:haxe.Exception) {
			link.close();
			Sys.println('helder: ${Compiler.tool()}: ${e.message}');
			return null;
		}
		for (k => v in saved) if (v == null) Sys.putEnv(k, null);
		p.closeStdin();
		var sock = try Async.timeout(30, _ -> link.accept()) catch (_:haxe.Exception) null;
		link.close();
		if (sock == null) {
			p.kill();
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
				if (line.startsWith("\x01")) Sys.print(line.substr(1).split("\x01").join("\n"));
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

	public function stop() {
		socket.close();
		process.kill();
		process.close();
	}
}
