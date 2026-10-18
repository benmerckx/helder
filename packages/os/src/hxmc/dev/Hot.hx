package hxmc.dev;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

// Fast refresh's primitives (docs/dev.md; docs/plans/dev-loop.md): what a
// state library calls so that its state survives a reload under `hxmc dev`.
// A reload is a fresh start: the new build runs its own main, and what it
// gets from the old one is data, by key. hxmc's signals (hxmc.view) and any
// other library use the same calls:
//
//   Hot.reloading            true while this build starts from a snapshot
//                            (until its first frame); false on a cold start
//   Hot.onSnapshot(f)        f runs before the swap, to save values; returns
//                            a function that removes f (when what it saves
//                            is gone)
//   Hot.onDispose(f)         f runs after the snapshot, before the new build
//                            starts: release what this build owns (effects,
//                            timers, sockets, GPU buffers); returns a remover
//   Hot.save(key, v, type)   v kept for the next build (haxe.Serializer, or
//                            encode: T->String)
//   Hot.load(key, type)      the value the last build saved under key (once;
//                            Unserializer, or decode: String->T), null when
//                            there is none or its type changed (logged)
//   Hot.typeOf((_ : T))      T's shape hashed when compiling (its fields and
//                            their types, recursively: HotMacro.hash); "" for
//                            a type that is not data, which is never kept.
//                            Haxe has no explicit type arguments: `(_ : T)`
//                            names T, any other expression gives its type
//   Hot.here()               the static identity of the place it is written:
//                            Type.method.variable (the variable the
//                            expression is assigned to, else #n, its order)
//   Hot.scope(name, f)       runs f with name nested in the keys made in it
//                            (a component instance, a list item); a name
//                            given twice in one scope becomes name#1, ...
//   Hot.keep(key, init)      a value kept as it is: load, else init(); saved
//                            on each snapshot
//   Hot.path(), Hot.at(p, f) the current scope, and f run in a scope taken
//                            earlier (code that runs later: an effect again)
//
// Keys are relative to the scope: save and load resolve them against it
// (load also numbers a key loaded twice in one scope: key#1). Functions given
// to onSnapshot and onDispose run in the scope, and with the keys, of where
// they were given, so that save(key) there reaches what load(key) read.
//
// Without -D hxmc.dev every call compiles to nothing (macros: no argument is
// evaluated; load is null, reloading false, here and typeOf ""; scope, at and
// keep call their function), so a library can call them unconditionally.
class Hot {
	#if (!hxmc.dev || macro)
	// (without -D hxmc.dev; and in the macro context, where a library's macro class is compiled too)
	public static var reloading(get, never):Bool;

	static inline function get_reloading():Bool
		return false;

	public static macro function onSnapshot(f:Expr):Expr
		return macro(hxmc.dev.Hot.none : Void->Void);

	public static macro function onDispose(f:Expr):Expr
		return macro(hxmc.dev.Hot.none : Void->Void);

	public static macro function save(key:Expr, value:Expr, type:Expr, rest:Array<Expr>):Expr
		return macro {};

	public static macro function load(key:Expr, type:Expr, rest:Array<Expr>):Expr
		return macro null;

	#if !hxmc.dev
	public static macro function typeOf(e:Expr):Expr
		return macro "";

	public static macro function here():Expr
		return macro "";

	public static macro function keep(key:Expr, init:Expr):Expr
		return body(init);
	#end

	public static macro function path():Expr
		return macro "";

	public static macro function scope(name:Expr, f:Expr):Expr
		return body(f);

	public static macro function at(path:Expr, f:Expr):Expr
		return body(f);

	@:noCompletion public static function none() {}

	#if macro
	// f's body when f is a function literal without arguments, else f()
	static function body(f:Expr):Expr {
		return switch f.expr {
			case EFunction(_, {args: [], expr: e}) if (e != null):
				switch e.expr {
					case EMeta({name: ":implicitReturn"}, {expr: EReturn(r)}) | EReturn(r) if (r != null): r;
					case _: macro $f();
				}
			case _: macro $f();
		}
	}
	#end
	#end
	#if hxmc.dev
	public static macro function typeOf(e:Expr):Expr
		return macro $v{HotMacro.hash(HotMacro.typeOfExpr(e))};

	public static macro function here():Expr
		return macro $v{HotMacro.here(Context.currentPos())};

	public static macro function keep(key:Expr, init:Expr):Expr {
		var t = switch Context.follow(Context.typeof(init)) {
			case TFun(_, ret): ret;
			case t: Context.error("hxmc.dev: Hot.keep's init is a function () -> value, not " + haxe.macro.TypeTools.toString(t), init.pos);
		}
		return macro hxmc.dev.Hot.keepValue($key, $v{HotMacro.hash(t)}, $init);
	}

	#if !macro
	public static var reloading(get, never):Bool;

	static function get_reloading():Bool {
		init();
		return restored != null && !settled;
	}

	public static function onSnapshot(f:Void->Void):Void->Void {
		var id = nextId++;
		snapshots.set(id, {f: f, frame: frame.capture()});
		return () -> snapshots.remove(id);
	}

	public static function onDispose(f:Void->Void):Void->Void {
		var id = nextId++;
		disposals.set(id, {f: f, frame: frame.capture()});
		return () -> disposals.remove(id);
	}

	public static function save<T>(key:String, value:T, type:String, ?encode:T->String) {
		var k = frame.saveKey(key);
		if (type == "") {
			notKept.push(k);
			return;
		}
		var data = try encode != null ? encode(value) : haxe.Serializer.run(value) catch (e:Dynamic) {
			log('$k not kept: ' + Std.string(e));
			return;
		}
		saved.set(k, {type: type, data: data});
	}

	public static function load<T>(key:String, type:String, ?decode:String->T):Null<T> {
		init();
		var k = frame.loadKey(key);
		if (restored == null) return null;
		var e = restored.get(k);
		if (e == null) return null;
		restored.remove(k);
		if (e.type != type) {
			log('$k reset: its type changed');
			return null;
		}
		return try decode != null ? decode(e.data) : haxe.Unserializer.run(e.data) catch (x:Dynamic) {
			log('$k reset: its value could not be read back (' + Std.string(x) + ')');
			null;
		}
	}

	public static function scope<R>(name:String, f:Void->R):R {
		var saved = frame;
		frame = new Frame(saved.child(name));
		try {
			var r = f();
			frame = saved;
			return r;
		} catch (e:Dynamic) {
			frame = saved;
			throw e;
		}
	}

	public static function path():String
		return frame.path;

	public static function at<R>(path:String, f:Void->R):R {
		var saved = frame;
		frame = new Frame(path);
		try {
			var r = f();
			frame = saved;
			return r;
		} catch (e:Dynamic) {
			frame = saved;
			throw e;
		}
	}

	@:noCompletion public static function keepValue<T>(key:String, type:String, init:Void->T):T {
		var v:Null<T> = load(key, type);
		var value:T = v != null ? v : init();
		onSnapshot(() -> save(key, value, type));
		return value;
	}

	// --- the dev loop's side (the dev server, packages/cli/hxmc/bootstrap/dev.mjs) ---

	// the values the last build saved, by key, until asked for (null: a cold start)
	static var restored:Null<Map<String, {type:String, data:String}>> = null;
	static final saved = new Map<String, {type:String, data:String}>();
	static final notKept:Array<String> = [];
	static final snapshots = new haxe.ds.IntMap<{f:Void->Void, frame:Frame}>();
	static final disposals = new haxe.ds.IntMap<{f:Void->Void, frame:Frame}>();
	static var nextId = 0;
	static var frame = new Frame("");
	static var started = false;
	static var settled = false;
	// (this build has handed over: its loop ends)
	static var done = false;
	// natively, the dev server's connection
	static var socket:Null<sys.net.Socket> = null;
	static var input = "";

	static function log(s:String)
		Sys.stderr().writeString("hxmc.dev: " + s + "\n");

	static function init() {
		if (started) return;
		started = true;
		var data:Null<String> = null;
		if (hxmc.unsafe.Mem.os() == 3) {
			var n = DevWeb.restore_length();
			if (n >= 0) {
				var b = haxe.io.Bytes.alloc(n);
				hxmc.unsafe.Arena.scoped(a -> {
					var p = a.alloc(n + 1, 1);
					DevWeb.restore_take(p);
					hxmc.unsafe.BytesPtr.copyIn(b, 0, p, n);
				});
				data = b.toString();
			}
			DevWeb.register(hxmc.unsafe.Callback.addr(webReload));
		} else {
			var file = Sys.getEnv("HXMC_DEV_SNAPSHOT");
			if (file != null && file != "" && sys.FileSystem.exists(file)) data = sys.io.File.getContent(file);
			var at = Sys.getEnv("HXMC_DEV");
			if (at != null && at.indexOf(":") > 0) {
				try {
					var s = new sys.net.Socket();
					s.connect(new sys.net.Host(at.substr(0, at.lastIndexOf(":"))), Std.parseInt(at.substr(at.lastIndexOf(":") + 1)));
					s.setBlocking(false);
					socket = s;
				} catch (e:Dynamic) {
					log("no dev server at " + at + " (" + Std.string(e) + ")");
				}
			}
		}
		if (data != null) restored = parse(data);
	}

	// the snapshot's format: haxe.Serializer's of an array of strings: key, type, data, key, ...
	static function parse(data:String):Map<String, {type:String, data:String}> {
		var m = new Map<String, {type:String, data:String}>();
		var a:Array<String> = try haxe.Unserializer.run(data) catch (e:Dynamic) {
			log("the snapshot could not be read (" + Std.string(e) + "): a cold start");
			return null;
		}
		var i = 0;
		while (i + 2 < a.length) {
			m.set(a[i], {type: a[i + 1], data: a[i + 2]});
			i += 3;
		}
		return m;
	}

	// the values to hand to the next build: what each onSnapshot function saves
	@:noCompletion public static function snapshot():String {
		init();
		notKept.resize(0);
		for (s in snapshots) {
			var savedFrame = frame;
			frame = s.frame;
			try s.f() catch (e:Dynamic) log("a snapshot function failed: " + Std.string(e));
			frame = savedFrame;
		}
		var a:Array<String> = [];
		var n = 0;
		for (k => e in saved) {
			a.push(k);
			a.push(e.type);
			a.push(e.data);
			n++;
		}
		if (notKept.length > 0) log('$n values kept, ${notKept.length} not (not data): ' + notKept.join(", "));
		return haxe.Serializer.run(a);
	}

	// releases what this build owns (the onDispose functions, last given first)
	@:noCompletion public static function dispose() {
		var fs = [for (d in disposals) d];
		fs.reverse();
		for (d in fs) {
			var savedFrame = frame;
			frame = d.frame;
			try d.f() catch (e:Dynamic) log("a dispose function failed: " + Std.string(e));
			frame = savedFrame;
		}
		done = true;
	}

	// hxmc.os.App, at each turn of its loop: the dev server's messages (natively)
	@:noCompletion public static function poll():Bool {
		init();
		if (socket == null) return !done;
		var buf = haxe.io.Bytes.alloc(4096);
		while (true) {
			var n = try socket.input.readBytes(buf, 0, buf.length) catch (e:haxe.io.Eof) {
				socket.close();
				socket = null;
				return !done;
			} catch (e:Dynamic) 0;
			if (n <= 0) break;
			input += buf.getString(0, n);
		}
		var nl;
		while ((nl = input.indexOf("\n")) >= 0) {
			var line = input.substr(0, nl);
			input = input.substr(nl + 1);
			var m:Dynamic = try haxe.Json.parse(line) catch (_:Dynamic) null;
			if (m != null && m.type == "reload") {
				var data = snapshot();
				sys.io.File.saveContent(m.snapshot, data);
				dispose();
				send('{"type":"saved"}');
				Sys.exit(0);
			}
		}
		return !done;
	}

	// hxmc.os.App, after each frame: the first one tells the dev server
	// (the reload's time, save to pixels) and ends the start: a value the
	// last build saved and nothing asked for is dropped (logged)
	@:noCompletion public static function framed() {
		if (settled) return;
		init();
		settled = true;
		if (restored != null) {
			var left = [for (k in restored.keys()) k];
			if (left.length > 0) {
				left.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
				log("not restored (nothing asked for it): " + left.join(", "));
			}
			restored = new Map();
		}
		if (hxmc.unsafe.Mem.os() == 3) DevWeb.frame() else send('{"type":"frame"}');
	}

	static function send(line:String) {
		if (socket == null) return;
		try {
			socket.setBlocking(true);
			socket.output.writeString(line + "\n");
			socket.output.flush();
			socket.setBlocking(false);
		} catch (e:Dynamic) {}
	}

	// the page asks for the snapshot (it then loads the new build)
	@:hxmc.callback static function webReload():Int {
		sendWeb(haxe.io.Bytes.ofString(snapshot()));
		dispose();
		return 0;
	}

	@:hxmc.noGc static function sendWeb(b:haxe.io.Bytes)
		DevWeb.send(hxmc.unsafe.BytesPtr.of(b, 0, b.length), b.length);
	#end
	#end
}

#if (hxmc.dev && !macro)
// a scope: its path, the names claimed in it (a name given again is name#n),
// and the keys load resolved there (for save)
private class Frame {
	public final path:String;

	var counts:Null<Map<String, Int>> = null;
	var names:Null<Map<String, String>> = null;

	public function new(path:String)
		this.path = path;

	function under(name:String):String
		return path == "" ? name : path + "/" + name;

	function claim(name:String):String {
		if (counts == null) counts = new Map();
		var c = counts.exists(name) ? counts.get(name) : 0;
		counts.set(name, c + 1);
		return c == 0 ? name : name + "#" + c;
	}

	// a nested scope's path
	public function child(name:String):String
		return under(claim(name));

	public function loadKey(key:String):String {
		var k = under(claim(key));
		if (names == null) names = new Map();
		names.set(key, k);
		return k;
	}

	public function saveKey(key:String):String {
		var k = names == null ? null : names.get(key);
		return k != null ? k : under(key);
	}

	// for a function run later in this scope (its own claims, the keys as they are now)
	public function capture():Frame {
		var f = new Frame(path);
		if (names != null) f.names = names.copy();
		return f;
	}
}

// the page's side in the browser (the dev server's page gives these imports)
@:hxmc.c @:hxmc.fast @:hxmc.lib("hxmc_dev") extern class DevWeb {
	// the snapshot the page was given: its UTF-8 length (-1: none), its bytes into p
	static function restore_length():Int;
	static function restore_take(p:hxmc.unsafe.Ptr):Void;
	// the function the page calls before it loads the new build (a @:hxmc.callback ():Int)
	static function register(f:hxmc.unsafe.Ptr):Void;
	// the snapshot (UTF-8), for the next build
	static function send(p:hxmc.unsafe.Ptr, n:Int):Void;
	// the first frame is drawn
	static function frame():Void;
}
#end
