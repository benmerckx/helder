package helder.compiler.service;

import haxe.io.Bytes;
import helder.async.*;

using StringTools;

// helder's compiler as a resident compilation server (`--server-connect`:
// it connects to a port of ours and takes its requests on that one
// connection: arguments one per line, after their length, a 32-bit
// little-endian integer; the answer after its length too, in lines: \x01
// output, \x02 failure, any other a message). A request at a time; what
// stays warm between them is the server's (the typed modules, hxmc's
// lowered bodies and objects). Native: a process and a socket (the wasm
// build of the compiler will answer the same requests in a worker, Backend
// in README.md).
class Resident {
	final process:Process;
	final socket:Socket;
	final reader:Reader;
	final lock = new Lock();
	// hxmc's std, given last to each build (as the compiler gives its own builds)
	final std:Null<String>;
	// the server's own output, the last of it (when it stops)
	public var output(default, null) = "";
	// each line of the server's own output (its stats, its crashes)
	public var onOutput:Null<String->Void> = null;

	function new(process, socket, std) {
		this.process = process;
		this.socket = socket;
		this.std = std;
		reader = new Reader(socket);
	}

	// started (tool: the compiler's executable; env: its environment), and
	// connected; null: it did not connect (fail: why)
	@:coroutine public static function start(task:Node, tool:String, env:Map<String, String>, ?std:String, ?fail:String->Void):Null<Resident> {
		var link = helder.async.Server.listen("127.0.0.1", 0);
		// (a resident compiler keeps what it makes: a large nursery and old space spare it collections)
		for (k => v in ["RT_OLD_MB" => "4096", "RT_MINOR_KB" => "32768"])
			if (!env.exists(k)) env.set(k, v);
		var p = try new Process(tool, ["--server-connect", '127.0.0.1:${link.port}'], {env: env}) catch (e:haxe.Exception) {
			link.close();
			if (fail != null) fail('$tool: ${e.message}');
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
		var s = new Resident(p, sock, std);
		for (pipe in [p.stdout, p.stderr])
			task.async(_ -> {
				var r = new Reader(pipe), line;
				while ((line = r.readLine()) != null) {
					s.output = (s.output + line + "\n").substr(-8192);
					if (s.onOutput != null) s.onOutput(line);
				}
			});
		return s;
	}

	// a build: its words, run in cwd; whether it compiled, what it printed
	// (\x01 lines, joined), its messages (errors and warnings, the compiler's text)
	@:coroutine public function request(words:Array<String>, cwd:String):{ok:Bool, printed:String, messages:String} {
		lock.acquire();
		try {
			var body = Bytes.ofString(["--cwd", cwd].concat(words).concat(std == null || words[0] == "--display" ? [] : ["-cp", std]).join("\n"));
			var head = Bytes.alloc(4);
			head.setInt32(0, body.length);
			socket.write(head, 0, 4);
			socket.write(body, 0, body.length);
			var n = reader.readBytes(4).getInt32(0);
			var answer = reader.readBytes(n).toString();
			lock.release();
			var ok = true, messages = [], printed = [];
			for (line in answer.split("\n")) {
				if (line.startsWith("\x01")) {
					var text = line.substr(1).split("\x01").join("\n");
					printed.push(text.endsWith("\n") ? text.substr(0, text.length - 1) : text);
				} else if (line.startsWith("\x02")) ok = false;
				else if (line != "") messages.push(line);
			}
			return {ok: ok, printed: printed.join("\n"), messages: messages.join("\n")};
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
