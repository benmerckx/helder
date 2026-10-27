package helder.devtools;

#if (hxmc.dev && !macro)
import haxe.Json;

// The program's side of the devtools protocol (README.md here): JSON-RPC
// 2.0 on helder.dev.Hot's connection to `helder dev`, in dev builds only.
// Hot connects, reads the lines and hands the protocol's messages here
// (Runtime.reload stays Hot's); the agent speaks only when the dev server
// says it does (HXMC_DEV_PROTOCOL, set by helder dev), else Hot speaks
// @hxmc/cli's {"type"} lines alone. A domain costs nothing until enabled:
// Log hooks haxe.Log.trace on Log.enable, Frame records each frame on
// Frame.enable. Libraries add methods (Agent.method: helder.ui's
// Ui.getTree) without this package depending on them.
class Agent {
	public static inline var PROTOCOL = 1;

	// speaking the protocol (the dev server asked for it, the hello sent)
	public static var on(default, null) = false;
	// Frame enabled: Hot.framed calls frame
	public static var framing(default, null) = false;
	// the GC bytes the agent allocated itself (taken out of the frames' counts)
	public static var own = 0.0;

	static final methods = new Map<String, Dynamic->Dynamic>();
	static var nextId = 1;
	static var trace0:Null<Dynamic->?haxe.PosInfos->Void> = null;

	// a method a library adds (params to result; throw an RpcError, or anything, for an error)
	public static function method(name:String, f:Dynamic->Dynamic)
		methods.set(name, f);

	// Hot.init, connected: the hello, when the dev server speaks the protocol
	@:allow(helder.dev.Hot) static function start() {
		if (Sys.getEnv("HXMC_DEV_PROTOCOL") != Std.string(PROTOCOL)) return;
		on = true;
		methods.set("Runtime.state", _ -> helder.dev.Hot.state());
		methods.set("Log.enable", _ -> {
			if (trace0 == null) {
				trace0 = haxe.Log.trace;
				haxe.Log.trace = logTrace;
			}
			return ok();
		});
		methods.set("Log.disable", _ -> {
			if (trace0 != null) haxe.Log.trace = trace0;
			trace0 = null;
			return ok();
		});
		methods.set("Frame.enable", p -> Frames.enable(p == null || p.interval == null ? 100 : p.interval));
		methods.set("Frame.disable", _ -> Frames.disable());
		var target = haxe.macro.Compiler.getDefine("hxmc.target");
		request("Runtime.hello", {
			protocol: PROTOCOL,
			program: {
				name: haxe.macro.Compiler.getDefine("helder.name"),
				target: target,
				#if hxmc.dev_host
				hosted: helder.dev.Hosted.hosted(),
				#else
				hosted: false,
				#end
				reloaded: helder.dev.Hot.reloading,
			},
			domains: domains(),
		});
	}

	static function ok():Dynamic
		return {};

	static function domains():Array<String> {
		var a = ["Runtime"];
		for (k in methods.keys()) {
			var d = k.substr(0, k.indexOf("."));
			if (!a.contains(d)) a.push(d);
		}
		a.sort((x, y) -> x < y ? -1 : x > y ? 1 : 0);
		return a;
	}

	// a message of the protocol from the dev server (Hot.poll)
	@:allow(helder.dev.Hot) static function receive(m:Dynamic) {
		if (m.method == null) return; // (a response: the hello's)
		var name:String = m.method;
		var f = methods.get(name);
		if (m.id == null) {
			if (f != null) try f(m.params) catch (_:Dynamic) {};
			return;
		}
		if (f == null) {
			reply(m.id, null, {code: -32601, message: 'no method $name' + (name == "Ui.getTree" ? " (helder.ui is not in this program)" : "")});
			return;
		}
		var result:Dynamic = null;
		var error:Dynamic = null;
		try result = f(m.params) catch (e:RpcError) error = {code: e.code, message: e.message} catch (e:Dynamic) error = {code: -32603, message: Std.string(e)};
		reply(m.id, result, error);
	}

	static function reply(id:Dynamic, result:Dynamic, error:Dynamic)
		helder.dev.Hot.sendLine(error != null ? Json.stringify({jsonrpc: "2.0", id: id, error: error}) : Json.stringify({jsonrpc: "2.0", id: id, result: result ?? ok()}));

	public static function notify(method:String, params:Dynamic)
		if (on) helder.dev.Hot.sendLine(Json.stringify({jsonrpc: "2.0", method: method, params: params}));

	static function request(method:String, params:Dynamic)
		helder.dev.Hot.sendLine(Json.stringify({jsonrpc: "2.0", id: nextId++, method: method, params: params}));

	// (Log enabled) a trace as an entry, not printed: helder dev prints it
	static function logTrace(v:Dynamic, ?pos:haxe.PosInfos) {
		var b = begin();
		var s = Std.string(v);
		if (pos != null && pos.customParams != null) for (p in pos.customParams) s += ", " + Std.string(p);
		notify("Log.entry", {
			level: "info",
			source: "trace",
			message: s,
			position: pos == null ? null : {file: pos.fileName, line: pos.lineNumber, className: pos.className, method: pos.methodName}
		});
		end(b);
	}

	// Hot.dispose: the domains off (the GC's stats too: no report at exit)
	@:allow(helder.dev.Hot) static function dispose() {
		if (framing) Frames.disable();
		if (trace0 != null) haxe.Log.trace = trace0;
		trace0 = null;
	}

	// seconds on the monotonic clock (not haxe.Timer.stamp: haxe.Timer costs a
	// dev build 118 KB, its EventLoop's, without -dce full)
	public static inline function now():Float {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		return hxmc.rt.Os.now();
		#else
		return Sys.time();
		#end
	}

	// around the agent's own work while Frame is on: its garbage counted apart
	public static inline function begin():Float
		return framing ? GcCounters.bytes() : 0;

	public static inline function end(b:Float)
		if (framing) own += GcCounters.bytes() - b;

	// Hot.poll, at the start of a turn (a frame's work from here to framed)
	public static inline function turn()
		if (framing) Frames.turn();

	// Hot.framed, after each frame
	public static inline function frame()
		if (framing) Frames.frame();

	@:allow(helder.devtools.Frames) static function setFraming(v:Bool)
		framing = v;
}

class RpcError {
	public final code:Int;
	public final message:String;

	public function new(code:Int, message:String) {
		this.code = code;
		this.message = message;
	}
}
#end
