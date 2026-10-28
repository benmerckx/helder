package helder.cli;

import haxe.Json;
import helder.async.*;
import helder.async.http.WebSocket;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `helder inspect [--tree] [--log] [--frames] [--state]`: a small tool on
// the devtools protocol (src/helder/devtools/README.md), connected to a
// running `helder dev` (bin/dev/devtools.json, from here up, or --port):
// the ui tree and the state Hot keeps printed once, the log (from what
// helder dev kept) and the frames' stats streamed until the dev server
// ends. The devtools app comes later; this proves the protocol.
class Inspect {
	static var ws:WebSocket;
	static var nextId = 1;
	static final waiting = new Map<Int, Dynamic>();

	@:coroutine public static function run(task:Node, o:Options):Int {
		var tree = o.has("tree"), state = o.has("state"), log = o.has("log"), frames = o.has("frames");
		var port = Std.parseInt(o.value("port") ?? "") ?? -1, dir = o.positionals[0] ?? ".";
		if (!tree && !state && !frames) log = true;
		var host = "127.0.0.1", path = "/__helder/devtools";
		if (port < 0) {
			var f = find(dir);
			if (f == null) {
				Sys.println("helder inspect: no bin/dev/devtools.json here or above (is helder dev running?); --port names its port");
				return 1;
			}
			var info:Dynamic = Json.parse(File.getContent(f));
			port = info.port;
			path = info.path ?? path;
			if (info.host != null && info.host != "localhost") host = info.host;
		}
		ws = try WebSocket.connect(host, port, path) catch (e:haxe.Exception) {
			Sys.println('helder inspect: no helder dev at $host:$port (${e.message})');
			return 1;
		}
		var reading = task.async(_ -> read(log, frames));
		var hello = call("Runtime.hello", {protocol: Devtools.PROTOCOL, client: "helder inspect"});
		if (hello.error != null) {
			Sys.println('helder inspect: ${hello.error.message}');
			return 1;
		}
		var p = hello.result.program;
		Sys.println('helder inspect: ${hello.result.entry} (${hello.result.target}' + (p == null ? ", no program connected" : "") + ")");
		if (tree) {
			var r = call("Ui.getTree", {});
			if (r.error != null) Sys.println('helder inspect: ${r.error.message}') else for (u in (r.result.uis : Array<Dynamic>)) {
				Sys.println('ui ${u.width}x${u.height}');
				node(u.root, 0);
				if (u.overlay.children.length > 0) node(u.overlay, 0);
			}
		}
		if (state) {
			var r = call("Runtime.state", {});
			if (r.error != null) Sys.println('helder inspect: ${r.error.message}') else {
				for (k in (r.result.kept : Array<Dynamic>)) Sys.println('kept ${k.key} (${k.bytes} bytes)');
				for (k in (r.result.notKept : Array<String>)) Sys.println('not kept $k (not data)');
				for (k in (r.result.dropped : Array<String>)) Sys.println('dropped $k (nothing asked for it)');
			}
		}
		if (!log && !frames) {
			ws.close();
			return 0;
		}
		if (log) for (e in (call("Log.enable", {}).result.entries : Array<Dynamic>)) entry(e);
		if (frames) call("Frame.enable", {interval: 1000});
		reading.await();
		return 0;
	}

	// bin/dev/devtools.json from dir up
	static function find(dir:String):Null<String> {
		var d = FileSystem.fullPath(dir);
		while (d != null && d != "") {
			var f = '$d/bin/dev/devtools.json';
			if (FileSystem.exists(f)) return f;
			var up = haxe.io.Path.directory(d);
			if (up == d || up == "") break;
			d = up;
		}
		return null;
	}

	@:coroutine static function call(method:String, params:Dynamic):Dynamic {
		var id = nextId++;
		ws.send(Json.stringify({jsonrpc: "2.0", id: id, method: method, params: params}));
		while (!waiting.exists(id)) {
			if (ws.closed) return {error: {message: "helder dev closed the connection"}};
			Async.delay(0.01);
		}
		var r = waiting.get(id);
		waiting.remove(id);
		return r;
	}

	@:coroutine static function read(log:Bool, frames:Bool) {
		var text;
		while ((text = try ws.receive() catch (_:haxe.Exception) null) != null) {
			var m:Dynamic = try Json.parse(text) catch (_:Dynamic) null;
			if (m == null) continue;
			if (m.method == null) {
				waiting.set(Std.int(m.id), m);
				continue;
			}
			switch (m.method : String) {
				case "Log.entry" if (log): entry(m.params);
				case "Frame.stats" if (frames): stats(m.params);
				case "Runtime.reloaded": Sys.println('-- reloaded in ${m.params.ms} ms');
				case "Runtime.exited": Sys.println('-- the program ended (${m.params.code})');
				case _:
			}
		}
		Sys.println("helder inspect: helder dev ended");
	}

	static function entry(e:Dynamic) {
		var at = e.position;
		var text = at == null ? e.message : '${at.file}:${at.line}: ${e.message}';
		Sys.println(e.level == "error" && e.source != "build" ? '[${e.source}] $text' : text);
	}

	// a batch: its frames' times (mean, longest), work, GC bytes, collections, pauses
	static function stats(p:Dynamic) {
		var dt:Array<Float> = p.dt, work:Array<Float> = p.work, bytes:Array<Float> = p.gcBytes;
		var n = dt.length;
		if (n == 0) return;
		var sum = (a:Array<Float>) -> Lambda.fold(a, (x, s) -> x + s, 0.0);
		var max = Lambda.fold(dt, (x, m) -> Math.max(x, m), 0.0);
		var r = (x:Float) -> Math.round(x * 100) / 100;
		Sys.println('frames ${p.first}-${p.first + n - 1}: ${r(sum(dt) / n)} ms (longest ${r(max)}), work ${r(sum(work) / n)} ms, '
			+ '${Math.round(sum(bytes) / n)} GC bytes a frame, ${sum(p.gcCollections)} collections (${r(sum(p.gcPauseMs))} ms), agent ${p.agentBytes} bytes');
	}

	static function node(n:Dynamic, depth:Int) {
		var s = n.style;
		var line = StringTools.lpad("", " ", depth * 2) + '${n.tag} #${n.id} ${n.x},${n.y} ${n.width}x${n.height}';
		if (s.direction != "column") line += ' ${s.direction}';
		if (s.display != "flex") line += ' ${s.display}';
		if (s.background != "#00000000") line += ' bg ${s.background}';
		if (n.text != null) line += ' "${n.text}"';
		Sys.println(line);
		for (c in (n.children : Array<Dynamic>)) node(c, depth + 1);
	}
}
