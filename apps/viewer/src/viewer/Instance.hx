package viewer;

import helder.async.*;

// One viewer at a time: the first listens on a loopback port (helder.async's
// Server, a free one) and writes it, with a token of its own, to its store
// (helder.os.Store "helder-viewer-instance"); a later launch connects there
// and hands its file over ("open <token> <path>"; "ok" back), then ends. A
// port no one answers on (a viewer that crashed): this launch becomes the
// first. The first opens what it is handed and raises its window.
class Instance {
	static inline var STORE = "helder-viewer-instance";

	// the running viewer given the path (absolute); true when it took it
	@:coroutine public static function handOver(path:String):Bool {
		var store = try helder.os.Store.open(STORE) catch (_:Dynamic) null;
		if (store == null || !store.exists("port")) return false;
		var port = Std.parseInt(store.get("port")), token = store.get("token");
		if (port == null || token == null) return false;
		var s = try Socket.connect("127.0.0.1", port) catch (_:Dynamic) null;
		if (s == null) return false;
		var ok = try {
			s.writeString('open $token $path\n');
			new Reader(s).readLine() == "ok";
		} catch (_:Dynamic) false;
		s.close();
		return ok;
	}

	// this one the first: what later launches hand over goes to open
	public static function serve(open:String->Void) {
		var server = try Server.listen("127.0.0.1", 0) catch (_:Dynamic) null;
		if (server == null) return;
		var token = Std.string(Std.random(0x7FFFFFFF)) + Std.string(Std.random(0x7FFFFFFF));
		var store = try helder.os.Store.open(STORE) catch (_:Dynamic) null;
		if (store != null) {
			store.set("port", Std.string(server.port));
			store.set("token", token);
		}
		Async.launch(task -> while (true) {
			var s = server.accept();
			task.async(_ -> {
				var line = try new Reader(s).readLine() catch (_:Dynamic) null;
				var prefix = 'open $token ';
				if (line != null && StringTools.startsWith(line, prefix)) {
					open(line.substr(prefix.length));
					try s.writeString("ok\n") catch (_:Dynamic) {}
				}
				s.close();
			});
		});
	}

	// (closing: the next launch is the first)
	public static function leave() {
		var store = try helder.os.Store.open(STORE) catch (_:Dynamic) null;
		if (store != null) store.clear();
	}
}
