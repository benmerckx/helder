import haxe.Json;
import helder.async.*;
import helder.async.http.Http;
import helder.async.http.WebSocket;

// A dev server's moving parts at once, on one thread's loop (helder.async):
// a directory served over HTTP, a WebSocket at /ws told of each change to
// a file in it ({"changed": [paths]}), and a child process whose output is
// streamed (printed, and sent to the sockets: {"out": line}). GET /quit ends
// it all: the root task cancelled, every connection, the watcher and the
// child with it.
//
//   AsyncDev <dir> <port> [command args...]
class AsyncDev {
	static final clients:Array<WebSocket> = [];

	static function main() {
		var args = Sys.args();
		if (args.length < 2) {
			Sys.println("AsyncDev <dir> <port> [command args...]");
			Sys.exit(2);
		}
		var dir = args[0], port = Std.parseInt(args[1]), command = args.slice(2);
		var t0 = haxe.Timer.stamp();
		try Async.run(app -> {
			var server = Server.listen("127.0.0.1", port);
			Sys.println('listening on http://127.0.0.1:${server.port}/');
			app.async(_ -> Http.serve(server, req -> {
				if (req.path == "/quit") {
					// (once the answer is out)
					app.async(_ -> {
						Async.delay(0.05);
						app.cancel();
					});
					return Response.text("bye\n");
				}
				if (req.path == "/ws" && WebSocket.wants(req)) {
					var ws = WebSocket.upgrade(req);
					clients.push(ws);
					while (ws.receive() != null) {}
					clients.remove(ws);
					return null;
				}
				return Http.file(dir, req.path) ?? Response.text("not found\n", 404);
			}));
			app.async(_ -> {
				var w = new PollWatcher([dir], 0.1, 0.05);
				while (true) {
					var changed = w.next();
					Sys.println("changed: " + changed.join(" "));
					broadcast(Json.stringify({changed: changed}));
				}
			});
			if (command.length > 0) app.async(_ -> {
				var p = new Process(command[0], command.slice(1));
				var out = new Reader(p.stdout);
				try {
					var line;
					while ((line = out.readLine()) != null) {
						Sys.println("[child] " + line);
						broadcast(Json.stringify({out: line}));
					}
					Sys.println("[child] exited with " + p.wait());
				} catch (e:haxe.exceptions.CancellationException) {
					p.kill();
					p.close();
					throw e;
				}
				p.close();
			});
			server;
		}) catch (e:haxe.exceptions.CancellationException) {}
		Sys.println('stopped after ${Math.round((haxe.Timer.stamp() - t0) * 10) / 10}s');
	}

	@:coroutine static function broadcast(message:String) {
		for (ws in clients.copy())
			try ws.send(message) catch (_:haxe.Exception) clients.remove(ws);
	}
}
