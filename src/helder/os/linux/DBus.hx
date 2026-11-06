package helder.os.linux;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import hxmc.unsafe.*;

// A small D-Bus client (Linux): the session bus over its Unix socket
// (DBUS_SESSION_BUS_ADDRESS's unix:path= or abstract=), SASL's EXTERNAL
// authentication, Hello; method calls and their replies, signals (with a
// match rule), replies and signals sent (a service's half: what tests stand
// in with). Little-endian messages, the types the desktop's portals use:
// y b n q i u x t d s o g, arrays, structs, dict entries, variants. Values:
// Int (64-bit ones as Float), Bool, String, Array (an array, a struct, a
// dict entry: [key, value]), Variant. Blocking, with a timeout: what
// helder.os's dialogs (FileDialog, xdg-desktop-portal's FileChooser) need;
// or not (poll: what came, without waiting; callLater: a call whose reply is
// not waited for), as a service answering in a program's loop does
// (helder.ui's AT-SPI adapter, LinuxAccess).
class DBus {
	public static inline var METHOD_CALL = 1;
	public static inline var METHOD_RETURN = 2;
	public static inline var ERROR = 3;
	public static inline var SIGNAL = 4;

	final fd:Int;
	var serial = 0;
	var inbox = new BytesBuffer();
	var pending = Bytes.alloc(0);
	final queued:Array<DBusMessage> = [];
	// its unique name on the bus (Hello's)
	public var name(default, null) = "";

	function new(fd:Int)
		this.fd = fd;

	// the session bus, or null when there is none to reach
	public static function session():Null<DBus> {
		var address = Sys.getEnv("DBUS_SESSION_BUS_ADDRESS");
		if (address == null) {
			var runtime = Sys.getEnv("XDG_RUNTIME_DIR");
			if (runtime == null) return null;
			address = "unix:path=" + runtime + "/bus";
		}
		for (a in address.split(";")) {
			var b = connect(a);
			if (b != null) return b;
		}
		return null;
	}

	// a bus at an address (unix:path=... or unix:abstract=...)
	public static function connect(address:String):Null<DBus> {
		if (!StringTools.startsWith(address, "unix:")) return null;
		var path:Null<String> = null, isAbstract = false;
		for (kv in address.substr(5).split(",")) {
			var i = kv.indexOf("=");
			if (i < 0) continue;
			var k = kv.substr(0, i), v = unescape(kv.substr(i + 1));
			if (k == "path") path = v else if (k == "abstract") {
				path = v;
				isAbstract = true;
			}
		}
		if (path == null) return null;
		var fd = open(path, isAbstract);
		if (fd < 0) return null;
		var bus = new DBus(fd);
		if (!bus.authenticate()) {
			bus.close();
			return null;
		}
		var hello = bus.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "Hello", "", [], 5);
		if (hello == null || hello.type != METHOD_RETURN) {
			bus.close();
			return null;
		}
		bus.name = hello.body[0];
		return bus;
	}

	// (AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC; sockaddr_un: the family, then the path, a NUL first when isAbstract)
	static function open(path:String, isAbstract:Bool):Int {
		var fd = Posix.socket(1, 1 | 0x80000, 0);
		if (fd < 0) return -1;
		var p = Bytes.ofString(path);
		var addr:Ptr<UInt8> = LibC.malloc(110);
		for (i in 0...110)
			addr[i] = 0;
		(cast addr : Ptr<UInt16>).value = 1;
		var o = isAbstract ? 3 : 2;
		for (i in 0...Std.int(Math.min(p.length, 106)))
			addr[o + i] = p.get(i);
		var r = Posix.connect(fd, cast addr, o + p.length + (isAbstract ? 0 : 1));
		LibC.free(cast addr);
		if (r != 0) {
			Posix.close(fd);
			return -1;
		}
		return fd;
	}

	public function close()
		Posix.close(fd);

	// --- the wire

	function send(b:Bytes) {
		var p = LibC.malloc((b.length : hxmc.I64)), q:Ptr<UInt8> = cast p;
		for (i in 0...b.length)
			q[i] = b.get(i);
		var off = 0;
		while (off < b.length) {
			var n = Posix.write(fd, p.add(off), (b.length - off : hxmc.I64)).toInt();
			if (n <= 0) break;
			off += n;
		}
		LibC.free(p);
	}

	// up to 4096 bytes, waiting at most `seconds` (null: the time ran out or the bus closed)
	function receive(seconds:Float):Null<Bytes> {
		var tv:Ptr<Int64> = LibC.malloc(16);
		tv[0] = Std.int(seconds);
		tv[1] = Std.int((seconds - Std.int(seconds)) * 1e6);
		Posix.setsockopt(fd, 1, 20, cast tv, 16); // (SOL_SOCKET, SO_RCVTIMEO)
		LibC.free(cast tv);
		var buf = LibC.malloc(4096), q:Ptr<UInt8> = cast buf;
		var n = Posix.read(fd, buf, 4096).toInt();
		var out:Null<Bytes> = null;
		if (n > 0) {
			out = Bytes.alloc(n);
			for (i in 0...n)
				out.set(i, q[i]);
		}
		LibC.free(buf);
		return out;
	}

	// (SASL: a NUL, then AUTH EXTERNAL with the uid in hex; OK; BEGIN)
	function authenticate():Bool {
		var uid = Std.string(uidOf());
		var hex = [for (i in 0...uid.length) StringTools.hex(uid.charCodeAt(i), 2)].join("");
		send(Bytes.ofString("\x00AUTH EXTERNAL " + hex + "\r\n"));
		var line = "";
		while (line.indexOf("\r\n") < 0) {
			var b = receive(5);
			if (b == null) return false;
			line += b.toString();
		}
		if (!StringTools.startsWith(line, "OK")) return false;
		send(Bytes.ofString("BEGIN\r\n"));
		return true;
	}

	static function uidOf():Int {
		var status = try sys.io.File.getContent("/proc/self/status") catch (e:Dynamic) "";
		for (l in status.split("\n"))
			if (StringTools.startsWith(l, "Uid:")) return Std.parseInt(StringTools.trim(l.substr(4)).split("\t")[0]);
		return 0;
	}

	static function unescape(v:String):String {
		var out = new StringBuf(), i = 0;
		while (i < v.length) {
			if (v.charAt(i) == "%" && i + 2 < v.length) {
				out.addChar(Std.parseInt("0x" + v.substr(i + 1, 2)));
				i += 3;
			} else {
				out.add(v.charAt(i));
				i++;
			}
		}
		return out.toString();
	}

	// --- messages

	// a method call, its reply waited for (other messages kept for next); null: none in time
	public function call(destination:String, path:String, iface:String, member:String, signature:String, args:Array<Dynamic>, seconds:Float):Null<DBusMessage> {
		var s = write(METHOD_CALL, 0, destination, path, iface, member, signature, args, null);
		var until = Sys.time() + seconds;
		while (Sys.time() < until) {
			var m = read(until - Sys.time());
			if (m == null) return null;
			if ((m.type == METHOD_RETURN || m.type == ERROR) && m.replySerial == s) return m;
			queued.push(m);
		}
		return null;
	}

	// what comes next (a signal, a call to this connection), waiting at most seconds
	public function next(seconds:Float):Null<DBusMessage> {
		if (queued.length > 0) return queued.shift();
		return read(seconds);
	}

	// what has come (null: nothing yet), without waiting: the socket read
	// while it has bytes (O_NONBLOCK for the read)
	public function poll():Null<DBusMessage> {
		if (queued.length > 0) return queued.shift();
		var m = parse();
		if (m != null) return m;
		var flags = Posix.fcntl(fd, 3, 0); // F_GETFL
		Posix.fcntl(fd, 4, flags | 0x800); // F_SETFL, O_NONBLOCK
		var buf = LibC.malloc(65536), q:Ptr<UInt8> = cast buf;
		while (true) {
			var n = Posix.read(fd, buf, 65536).toInt();
			if (n <= 0) break;
			var all = new BytesBuffer();
			all.add(pending);
			for (i in 0...n)
				all.addByte(q[i]);
			pending = all.getBytes();
			if (n < 65536) break;
		}
		LibC.free(buf);
		Posix.fcntl(fd, 4, flags);
		return parse();
	}

	// a method call whose reply is not waited for (its serial: the reply's, when one comes)
	public function callLater(destination:String, path:String, iface:String, member:String, signature:String, args:Array<Dynamic>):Int
		return write(METHOD_CALL, 0, destination, path, iface, member, signature, args, null);

	// an error for a call (its name, a message)
	public function error(to:DBusMessage, name:String, text:String)
		write(ERROR, to.serial, to.sender, null, null, null, "s", [text], name);

	public function addMatch(rule:String)
		call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "AddMatch", "s", [rule], 5);

	// a well-known name for this connection (a service's)
	public function requestName(n:String):Bool {
		var r = call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", "su", [n, 4], 5);
		return r != null && r.type == METHOD_RETURN && r.body[0] == 1;
	}

	public function reply(to:DBusMessage, signature:String, args:Array<Dynamic>)
		write(METHOD_RETURN, to.serial, to.sender, null, null, null, signature, args, null);

	public function signal(path:String, iface:String, member:String, signature:String, args:Array<Dynamic>, ?destination:String)
		write(SIGNAL, 0, destination, path, iface, member, signature, args, null);

	function write(type:Int, replyTo:Int, destination:Null<String>, path:Null<String>, iface:Null<String>, member:Null<String>, signature:String, args:Array<Dynamic>, error:Null<String>):Int {
		var body = new Writer();
		var sig = new SigReader(signature);
		var i = 0;
		while (!sig.done()) body.value(sig.next(), args[i++]);
		var fields:Array<Dynamic> = [];
		if (path != null) fields.push([1, new Variant("o", path)]);
		if (iface != null) fields.push([2, new Variant("s", iface)]);
		if (member != null) fields.push([3, new Variant("s", member)]);
		if (error != null) fields.push([4, new Variant("s", error)]);
		if (replyTo != 0) fields.push([5, new Variant("u", replyTo)]);
		if (destination != null) fields.push([6, new Variant("s", destination)]);
		if (signature != "") fields.push([8, new Variant("g", signature)]);
		var s = ++serial;
		var h = new Writer();
		h.value("y", "l".code);
		h.value("y", type);
		h.value("y", replyTo == 0 && type == METHOD_CALL ? 0 : 1); // (NO_REPLY_EXPECTED on replies and signals)
		h.value("y", 1);
		h.value("u", body.length);
		h.value("u", s);
		h.value("a(yv)", fields);
		h.pad(8);
		var b = new BytesBuffer();
		b.add(h.bytes());
		b.add(body.bytes());
		send(b.getBytes());
		return s;
	}

	// (the next whole message from the socket)
	function read(seconds:Float):Null<DBusMessage> {
		var until = Sys.time() + seconds;
		while (true) {
			var m = parse();
			if (m != null) return m;
			var left = until - Sys.time();
			if (left <= 0) return null;
			var b = receive(Math.max(0.01, left));
			if (b == null) {
				if (Sys.time() >= until) return null;
				continue;
			}
			var all = new BytesBuffer();
			all.add(pending);
			all.add(b);
			pending = all.getBytes();
		}
	}

	function parse():Null<DBusMessage> {
		if (pending.length < 16) return null;
		var bodyLen = pending.getInt32(4), fieldsLen = pending.getInt32(12);
		var headerEnd = 16 + fieldsLen;
		headerEnd = (headerEnd + 7) & ~7;
		var total = headerEnd + bodyLen;
		if (pending.length < total) return null;
		var msg = pending.sub(0, total);
		pending = pending.sub(total, pending.length - total);
		var m = new DBusMessage();
		m.type = msg.get(1);
		m.serial = msg.getInt32(8);
		var r = new Reader(msg, 12);
		var fields:Array<Dynamic> = r.value("a(yv)");
		for (f in fields) {
			var code:Int = f[0], v:Variant = f[1];
			switch code {
				case 1: m.path = v.value;
				case 2: m.iface = v.value;
				case 3: m.member = v.value;
				case 4: m.errorName = v.value;
				case 5: m.replySerial = v.value;
				case 6: m.destination = v.value;
				case 7: m.sender = v.value;
				case 8: m.signature = v.value;
				case _:
			}
		}
		var br = new Reader(msg, headerEnd);
		var sig = new SigReader(m.signature);
		while (!sig.done()) m.body.push(br.value(sig.next()));
		return m;
	}
}

class DBusMessage {
	public var type = 0;
	public var serial = 0;
	public var replySerial = 0;
	public var path:Null<String>;
	public var iface:Null<String>;
	public var member:Null<String>;
	public var errorName:Null<String>;
	public var destination:Null<String>;
	public var sender:Null<String>;
	public var signature = "";
	public final body:Array<Dynamic> = [];

	public function new() {}
}

// a variant: its signature and value
class Variant {
	public final sig:String;
	public final value:Dynamic;

	public function new(sig:String, value:Dynamic) {
		this.sig = sig;
		this.value = value;
	}
}

// (complete types one by one out of a signature)
private class SigReader {
	final s:String;
	var i = 0;

	public function new(s:String)
		this.s = s;

	public function done():Bool
		return i >= s.length;

	public function next():String {
		var start = i;
		skip();
		return s.substring(start, i);
	}

	function skip() {
		var c = s.charAt(i++);
		if (c == "a") skip() else if (c == "(" || c == "{") {
			var close = c == "(" ? ")" : "}";
			while (s.charAt(i) != close)
				skip();
			i++;
		}
	}
}

// (the marshalling: little-endian, each value at its alignment)
private class Writer {
	var buf = Bytes.alloc(256);

	public var length(default, null) = 0;

	public function new() {}

	public function bytes():Bytes
		return buf.sub(0, length);

	function room(n:Int) {
		if (length + n <= buf.length) return;
		var nb = Bytes.alloc(Std.int(Math.max(buf.length * 2, length + n)));
		nb.blit(0, buf, 0, length);
		buf = nb;
	}

	function byte(v:Int) {
		room(1);
		buf.set(length++, v);
	}

	function int32(v:Int) {
		room(4);
		buf.setInt32(length, v);
		length += 4;
	}

	public function pad(n:Int)
		while (length % n != 0)
			byte(0);

	public static function align(t:String):Int
		return switch t.charAt(0) {
			case "y" | "g" | "v": 1;
			case "n" | "q": 2;
			case "b" | "i" | "u" | "s" | "o" | "a": 4;
			case _: 8; // x t d ( {
		}

	public function value(t:String, v:Dynamic) {
		pad(align(t));
		switch t.charAt(0) {
			case "y": byte(v);
			case "b": int32(v ? 1 : 0);
			case "n" | "q":
				byte(v & 255);
				byte((v >> 8) & 255);
			case "i" | "u": int32(v);
			case "x" | "t":
				var x = haxe.Int64.fromFloat(v);
				int32(x.low);
				int32(x.high);
			case "d":
				room(8);
				buf.setDouble(length, v);
				length += 8;
			case "s" | "o":
				var s = Bytes.ofString(v);
				int32(s.length);
				for (i in 0...s.length)
					byte(s.get(i));
				byte(0);
			case "g":
				var s = Bytes.ofString(v);
				byte(s.length);
				for (i in 0...s.length)
					byte(s.get(i));
				byte(0);
			case "v":
				var x:Variant = v;
				value("g", x.sig);
				value(x.sig, x.value);
			case "a":
				var elem = t.substr(1);
				var at = length;
				int32(0);
				pad(align(elem));
				var start = length;
				for (e in (v : Array<Dynamic>))
					value(elem, e);
				// (the array's length in bytes, from its first element)
				buf.setInt32(at, length - start);
			case "(" | "{":
				var inner = new SigReader(t.substr(1, t.length - 2));
				var k = 0;
				while (!inner.done()) value(inner.next(), (v : Array<Dynamic>)[k++]);
			case _: throw "DBus: the type " + t;
		}
	}
}

private class Reader {
	final b:Bytes;
	var p:Int;

	public function new(b:Bytes, p:Int) {
		this.b = b;
		this.p = p;
	}

	function align(n:Int)
		p = (p + n - 1) & ~(n - 1);

	public function value(t:String):Dynamic {
		switch t.charAt(0) {
			case "y": return b.get(p++);
			case "b":
				align(4);
				p += 4;
				return b.getInt32(p - 4) != 0;
			case "n" | "q":
				align(2);
				p += 2;
				var v = b.getUInt16(p - 2);
				return t == "n" && v >= 0x8000 ? v - 0x10000 : v;
			case "i" | "u":
				align(4);
				p += 4;
				return b.getInt32(p - 4);
			case "x" | "t":
				align(8);
				p += 8;
				var v = b.getInt64(p - 8);
				return haxe.Int64.toInt(v);
			case "d":
				align(8);
				p += 8;
				return b.getDouble(p - 8);
			case "s" | "o":
				align(4);
				var n = b.getInt32(p);
				p += 4;
				var s = b.getString(p, n);
				p += n + 1;
				return s;
			case "g":
				var n = b.get(p++);
				var s = b.getString(p, n);
				p += n + 1;
				return s;
			case "v":
				var sig:String = value("g");
				return new Variant(sig, value(sig));
			case "a":
				align(4);
				var n = b.getInt32(p);
				p += 4;
				var elem = t.substr(1);
				align(Writer.align(elem));
				var end = p + n, out:Array<Dynamic> = [];
				while (p < end) out.push(value(elem));
				return out;
			case "(" | "{":
				align(8);
				var inner = new SigReader(t.substr(1, t.length - 2)), out:Array<Dynamic> = [];
				while (!inner.done()) out.push(value(inner.next()));
				return out;
			case _: throw "DBus: the type " + t;
		}
	}
}
