package helder.os.wayland;

import hxmc.unsafe.*;

typedef MessageDef = {name:String, signature:String, types:Array<Null<String>>};
typedef InterfaceDef = {name:String, version:Int, requests:Array<MessageDef>, events:Array<MessageDef>};

// libwayland's wl_interface and wl_message structs, made at run time from
// the generated modules' tables (helder.os.wayland.protocol), once each,
// kept for the process: wl_interface { name, version, method_count,
// methods, event_count, events } (40 bytes), wl_message { name, signature,
// types } (24); an argument's interface not among them is null (any).
class Interfaces {
	static final defs:Map<String, InterfaceDef> = [];
	static final made:Map<String, Ptr> = [];
	static var arena:Null<Arena> = null;

	public static function register(list:Array<InterfaceDef>)
		for (d in list)
			defs.set(d.name, d);

	static function ensure() {
		if (arena != null) return;
		arena = Arena.create();
		register(helder.os.wayland.protocol.WaylandProtocol.interfaces);
		register(helder.os.wayland.protocol.XdgShellProtocol.interfaces);
		register(helder.os.wayland.protocol.XdgDecorationUnstableV1Protocol.interfaces);
		register(helder.os.wayland.protocol.ViewporterProtocol.interfaces);
		register(helder.os.wayland.protocol.FractionalScaleV1Protocol.interfaces);
		register(helder.os.wayland.protocol.CursorShapeV1Protocol.interfaces);
		register(helder.os.wayland.protocol.TextInputUnstableV3Protocol.interfaces);
	}

	// the wl_interface of that name (nil: none known)
	public static function get(name:String):Ptr {
		ensure();
		var p = made.get(name);
		if (p != null) return p;
		var d = defs.get(name);
		if (d == null) return Ptr.nil();
		var a = arena;
		var i = a.alloc(40);
		made.set(name, i);
		(cast i : Ptr<Ptr>).value = cast a.cstring(name);
		(cast i.add(8) : Ptr<Int32>).value = d.version;
		(cast i.add(12) : Ptr<Int32>).value = d.requests.length;
		(cast i.add(16) : Ptr<Ptr>).value = messages(d.requests);
		(cast i.add(24) : Ptr<Int32>).value = d.events.length;
		(cast i.add(32) : Ptr<Ptr>).value = messages(d.events);
		return i;
	}

	static function messages(ms:Array<MessageDef>):Ptr {
		if (ms.length == 0) return Ptr.nil();
		var a = arena, p = a.alloc(24 * ms.length);
		for (k in 0...ms.length) {
			var m = ms[k], at = p.add(24 * k);
			(cast at : Ptr<Ptr>).value = cast a.cstring(m.name);
			(cast at.add(8) : Ptr<Ptr>).value = cast a.cstring(m.signature);
			var types = a.alloc(8 * Std.int(Math.max(1, m.types.length)));
			for (t in 0...m.types.length)
				(cast types.add(8 * t) : Ptr<Ptr>).value = m.types[t] == null ? Ptr.nil() : get(m.types[t]);
			(cast at.add(16) : Ptr<Ptr>).value = types;
		}
		return p;
	}

	// (a wl_interface's fields read back: tests, wl_registry.bind's name)
	public static function name(i:Ptr):String {
		var p:Ptr<Ptr> = cast i;
		return str(p.value);
	}

	// (a C string's text)
	public static function str(p:Ptr):Null<String> {
		if (p.isNull()) return null;
		var c:Ptr<UInt8> = cast p;
		return (c : CString).toString();
	}

	public static function version(i:Ptr):Int
		return (cast i.add(8) : Ptr<Int32>).value;

	public static function count(i:Ptr, events:Bool):Int
		return (cast i.add(events ? 24 : 12) : Ptr<Int32>).value;

	// a message's name, signature and its arguments' interfaces' names
	public static function message(i:Ptr, events:Bool, k:Int):{name:String, signature:String, types:Array<Null<String>>} {
		var m = (cast i.add(events ? 32 : 16) : Ptr<Ptr>).value.add(24 * k);
		var sp:Ptr<Ptr> = cast m.add(8), np:Ptr<Ptr> = cast m;
		var sig = str(sp.value);
		var n = 0;
		for (c in 0...sig.length)
			if (sig.charAt(c) != "?" && !(sig.charCodeAt(c) >= "0".code && sig.charCodeAt(c) <= "9".code)) n++;
		var types = (cast m.add(16) : Ptr<Ptr>).value;
		return {
			name: str(np.value),
			signature: sig,
			types: [for (t in 0...n) {
				var p = (cast types.add(8 * t) : Ptr<Ptr>).value;
				p.isNull() ? null : name(p);
			}]
		};
	}
}
