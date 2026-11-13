package helder.os.wayland;

import hxmc.unsafe.*;

// What the generated bindings call: a request marshalled (libwayland's
// wl_proxy_marshal_array_flags: the arguments as wl_argument slots of 8
// bytes; a new_id's proxy returned, a destructor's destroyed), a proxy's
// events to its Dispatcher (one C dispatcher for all: wl_proxy_add_dispatcher,
// its data the dispatcher's index here), the slots of an event read back.
// recorder, when set, takes the requests instead of libwayland (the
// bindings' unit test: Wayland.test.hx).
@:hxmc.unsafe(gc)
class Proxy {
	public static var recorder:Null<(proxy:Ptr, opcode:Int, iface:Ptr, version:Int, flags:Int, args:Ptr<Int64>, count:Int) -> Ptr> = null;
	static final dispatchers:Array<Null<Dispatcher>> = [null];
	static final free:Array<Int> = [];

	public static function marshal(proxy:Ptr, opcode:Int, iface:Ptr, version:Int, flags:Int, args:Ptr<Int64>, count:Int):Ptr {
		if (recorder != null) return recorder(proxy, opcode, iface, version, flags, args, count);
		if (proxy.isNull()) throw "helder.os: a Wayland request on a null proxy";
		var v = version >= 0 ? version : WaylandClient.wl_proxy_get_version(proxy);
		return WaylandClient.wl_proxy_marshal_array_flags(proxy, opcode, iface, v, flags, args);
	}

	// a proxy's events to d (its slot freed when the proxy is destroyed: forget)
	public static function listen(proxy:Ptr, d:Dispatcher):Int {
		var i = free.length > 0 ? free.pop() : dispatchers.length;
		if (i == dispatchers.length) dispatchers.push(d) else dispatchers[i] = d;
		if (recorder == null) WaylandClient.wl_proxy_add_dispatcher(proxy, Callback.addr(dispatch), Ptr.ofI64(i), Ptr.nil());
		return i;
	}

	public static function forget(i:Int) {
		if (i <= 0 || i >= dispatchers.length || dispatchers[i] == null) return;
		dispatchers[i] = null;
		free.push(i);
	}

	// (tests: the dispatcher at i given an event as libwayland would)
	public static function deliver(i:Int, opcode:Int, args:Ptr<Int64>) {
		var d = dispatchers[i];
		if (d != null) d.dispatch(opcode, args);
	}

	@:hxmc.callback static function dispatch(data:Ptr, target:Ptr, opcode:Int, message:Ptr, args:Ptr<Int64>):Int {
		var i = data.toI64().toInt();
		var d = i > 0 && i < dispatchers.length ? dispatchers[i] : null;
		if (d != null) d.dispatch(opcode, args);
		return 0;
	}

	// a slot as an int (int, uint, fd: their low 32 bits), a fixed, a string, a pointer
	public static inline function int(args:Ptr<Int64>, i:Int):Int
		return (cast args.add(8 * i) : Ptr<Int32>).value;

	public static inline function uint(args:Ptr<Int64>, i:Int):Int
		return (cast args.add(8 * i) : Ptr<Int32>).value;

	public static inline function fixed(args:Ptr<Int64>, i:Int):Float
		return (cast args.add(8 * i) : Ptr<Int32>).value / 256;

	public static function string(args:Ptr<Int64>, i:Int):Null<String> {
		var p:Ptr<Ptr> = cast args.add(8 * i);
		return Interfaces.str(p.value);
	}

	public static inline function ptr(args:Ptr<Int64>, i:Int):Ptr
		return (cast args.add(8 * i) : Ptr<Ptr>).value;

	public static inline function setString(a:Arena, args:Ptr<Int64>, i:Int, s:Null<String>)
		(cast args.add(8 * i) : Ptr<Ptr>).value = s == null ? Ptr.nil() : cast a.cstring(s);

	public static inline function interfaceName(iface:Ptr):String
		return Interfaces.name(iface);
}

// a proxy's events, decoded (the generated *Events classes)
interface Dispatcher {
	function dispatch(opcode:Int, args:Ptr<Int64>):Void;
}
