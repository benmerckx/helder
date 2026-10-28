package helder.cli;

import haxe.Json;
import helder.async.http.WebSocket;

// `helder dev` as the devtools' relay (src/helder/devtools/README.md): the
// program speaks JSON-RPC on its connection (helder.devtools.Agent), the
// tools on WebSockets at /__helder/devtools. A tool's request goes to the
// program under an id of ours and its response back to that tool by it;
// the program's notifications go to the tools that enabled their domain (a
// domain enabled in the program while one tool has it, again in each new
// build); the CLI's own: Runtime.hello, Log (the program's Log is always
// on: the last LOG entries kept, the program's output and the builds'
// errors among them, for a tool that comes late or after a crash), and
// the build's notifications (Runtime.built, buildError, reloaded,
// connected, exited).
class Devtools {
	public static inline var PROTOCOL = 1;
	static inline var LOG = 500;

	static final tools:Array<Tool> = [];
	// the domains the tools enabled, by how many (and the first one's params)
	static final counts = new Map<String, Int>();
	static final params = new Map<String, Dynamic>();
	static final log:Array<Dynamic> = [];
	// the program's requests in flight: a tool's (its id) or ours (a function)
	static final pending = new Map<Int, {?tool:Tool, ?id:Dynamic, ?done:Dynamic->Void}>();
	static var nextId = 1;
	// the program's connection speaks the protocol (its hello came); what it said
	public static var connected(default, null) = false;
	static var program:Dynamic = null;
	// what helder dev serves: its entry, target, and the last build
	public static var main = "";
	public static var target = "";
	static var build:Dynamic = null;

	// --- the program's side (DevCommand.connection)

	// a line of the protocol from the program
	@:coroutine public static function fromProgram(m:Dynamic, line:String) {
		if (m.method == "Runtime.hello" && m.id != null) {
			connected = true;
			program = m.params?.program;
			DevCommand.sendLine(Json.stringify({jsonrpc: "2.0", id: m.id, result: {protocol: PROTOCOL, server: "helder dev"}}));
			// (the log kept by us, then each domain a tool has on)
			request("Log.enable", {});
			for (d => n in counts) if (n > 0) request(d + ".enable", params.get(d));
			broadcast("Runtime", notification("Runtime.connected", {program: program, protocol: m.params?.protocol}));
			return;
		}
		if (m.method == null) {
			var p = pending.get(Std.int(m.id));
			if (p == null) return;
			pending.remove(Std.int(m.id));
			if (p.done != null) p.done(m);
			else if (p.tool != null) toTool(p.tool, m.error != null ? Json.stringify({jsonrpc: "2.0", id: p.id, error: m.error}) : Json.stringify({jsonrpc: "2.0", id: p.id, result: m.result}));
			return;
		}
		var method:String = m.method;
		if (method == "Log.entry") {
			entry(m.params);
			if (m.params.source == "trace") {
				var at = m.params.position;
				Term.out(at == null ? m.params.message : Style.dim('${at.file}:${at.line}:') + ' ${m.params.message}');
			}
			broadcast("Log", notification("Log.entry", m.params));
			return;
		}
		if (method == "Runtime.ready") DevCommand.measured();
		broadcast(method.substr(0, method.indexOf(".")), line);
	}

	// the program's connection closed
	@:coroutine public static function programGone() {
		if (!connected) return;
		connected = false;
		for (id => p in pending) if (p.tool != null) toTool(p.tool, Json.stringify({jsonrpc: "2.0", id: p.id, error: {code: -32002, message: "the program's connection closed (a reload, or it ended)"}}));
		pending.clear();
	}

	// a request of ours (done: its response, or nothing)
	@:coroutine public static function request(method:String, params:Dynamic, ?done:Dynamic->Void):Bool {
		if (!connected) return false;
		var id = nextId++;
		pending.set(id, {done: done ?? (_ -> {})});
		DevCommand.sendLine(Json.stringify({jsonrpc: "2.0", id: id, method: method, params: params ?? {}}));
		return true;
	}

	// a line of the program's output
	@:coroutine public static function output(line:String, err:Bool) {
		var e = {level: err ? "error" : "info", source: err ? "stderr" : "stdout", message: line, time: Sys.time()};
		entry(e);
		if (tools.length > 0) broadcast("Log", notification("Log.entry", e));
	}

	// the CLI's notifications: a build, its errors, a reload, the program's end
	@:coroutine public static function built(ms:Int, size:String) {
		build = {ok: true, ms: ms, size: size};
		broadcast("Runtime", notification("Runtime.built", build));
	}

	@:coroutine public static function buildError(ms:Int, message:String) {
		build = {ok: false, ms: ms, message: message};
		var e = {level: "error", source: "build", message: message, time: Sys.time()};
		entry(e);
		broadcast("Log", notification("Log.entry", e));
		broadcast("Runtime", notification("Runtime.buildError", {ms: ms, message: message}));
	}

	@:coroutine public static function reloaded(ms:Int, build:Int)
		broadcast("Runtime", notification("Runtime.reloaded", {ms: ms, build: build}));

	@:coroutine public static function exited(code:Int) {
		var e = {level: "error", source: "helder", message: 'the program ended ($code)', time: Sys.time()};
		entry(e);
		broadcast("Log", notification("Log.entry", e));
		broadcast("Runtime", notification("Runtime.exited", {code: code}));
	}

	// (time: when it came, wall clock seconds)
	static function entry(e:Dynamic) {
		if (e.time == null) Reflect.setField(e, "time", Sys.time());
		log.push(e);
		if (log.length > LOG) log.splice(0, log.length - LOG);
	}

	static function notification(method:String, params:Dynamic):String
		return Json.stringify({jsonrpc: "2.0", method: method, params: params});

	// --- the tools' side (a WebSocket at /__helder/devtools)

	@:coroutine public static function serve(ws:WebSocket) {
		var t = new Tool(ws);
		tools.push(t);
		var text;
		while ((text = try ws.receive() catch (_:haxe.Exception) null) != null) {
			var m:Dynamic = try Json.parse(text) catch (_:Dynamic) null;
			if (m == null || m.method == null) continue;
			fromTool(t, m);
		}
		tools.remove(t);
		for (d in t.domains.keys()) if (drop(d)) request(d + ".disable", {});
	}

	@:coroutine static function fromTool(t:Tool, m:Dynamic) {
		var method:String = m.method, id:Dynamic = m.id;
		var dot = method.indexOf("."), domain = method.substr(0, dot), verb = method.substr(dot + 1);
		switch [domain, verb] {
			case ["Runtime", "hello"]:
				if (m.params?.protocol != null && m.params.protocol != PROTOCOL) {
					fail(t, id, -32010, 'protocol ${m.params.protocol} is not this one (${PROTOCOL})');
					return;
				}
				answer(t, id, {protocol: PROTOCOL, server: "helder dev", program: connected ? program : null, entry: main, target: target, build: build});
			case ["Runtime", "reload"]:
				fail(t, id, -32601, "Runtime.reload is helder dev's (a change to a source reloads)");
			case ["Log", "enable"]:
				t.domains.set("Log", true);
				answer(t, id, {entries: log});
			case ["Log", "disable"]:
				t.domains.remove("Log");
				answer(t, id, {});
			case [_, "enable"] if (!t.domains.exists(domain)):
				t.domains.set(domain, true);
				var n = (counts.get(domain) ?? 0) + 1;
				counts.set(domain, n);
				if (n == 1) params.set(domain, m.params);
				if (n == 1 && connected) forward(t, m) else answer(t, id, {});
			case [_, "disable"] if (t.domains.exists(domain)):
				t.domains.remove(domain);
				if (drop(domain) && connected) forward(t, m) else answer(t, id, {});
			case [_, "enable" | "disable"]:
				answer(t, id, {});
			case _:
				if (!connected) fail(t, id, -32001, "no program connected" + (target == "web" ? " (the page's agent is to come)" : ""));
				else forward(t, m);
		}
	}

	@:coroutine static function answer(t:Tool, id:Dynamic, result:Dynamic)
		if (id != null) toTool(t, Json.stringify({jsonrpc: "2.0", id: id, result: result}));

	@:coroutine static function fail(t:Tool, id:Dynamic, code:Int, message:String)
		if (id != null) toTool(t, Json.stringify({jsonrpc: "2.0", id: id, error: {code: code, message: message}}));

	// a tool's request to the program, its response routed back by id
	@:coroutine static function forward(t:Tool, m:Dynamic) {
		var id = nextId++;
		if (m.id != null) pending.set(id, {tool: t, id: m.id});
		DevCommand.sendLine(Json.stringify({jsonrpc: "2.0", id: id, method: m.method, params: m.params ?? {}}));
	}

	// a domain one tool fewer has: disabled in the program when none has it
	static function drop(domain:String):Bool {
		if (domain == "Log" || !counts.exists(domain)) return false;
		var n = counts.get(domain) - 1;
		counts.set(domain, n);
		if (n > 0) return false;
		counts.remove(domain);
		params.remove(domain);
		return true;
	}

	@:coroutine static function toTool(t:Tool, text:String)
		try t.ws.send(text) catch (_:haxe.Exception) tools.remove(t);

	@:coroutine static function broadcast(domain:String, text:String)
		for (t in tools.copy())
			if (domain == "Runtime" || t.domains.exists(domain)) toTool(t, text);
}

private class Tool {
	public final ws:WebSocket;
	public final domains = new Map<String, Bool>();

	public function new(ws)
		this.ws = ws;
}
