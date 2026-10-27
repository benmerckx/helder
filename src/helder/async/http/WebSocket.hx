package helder.async.http;

import haxe.Exception;
import haxe.io.Bytes;
import helder.async.*;
import helder.async.http.Http;

// A WebSocket (RFC 6455) on a connection: a server's, from an HTTP request
// (upgrade), or a client's (connect). Messages are text (binary ones come
// as their bytes' string); pings are answered, fragments joined, a close
// answered. Sends are whole messages, one at a time (a Lock), so several
// tasks may send while one receives.
//
//   Http.serve(server, req -> {
//     if (req.path != "/ws") return Http.file("public", req.path);
//     var ws = WebSocket.upgrade(req);
//     var m; while ((m = ws.receive()) != null) ws.send("echo " + m);
//     null;
//   });
class WebSocket {
	public var closed(default, null) = false;

	final socket:Socket;
	final reader:Reader;
	// a client masks what it sends
	final client:Bool;
	final lock = new Lock();

	function new(socket, reader, client) {
		this.socket = socket;
		this.reader = reader;
		this.client = client;
	}

	// whether the request asks for a WebSocket
	public static function wants(req:Request):Bool
		return (req.header("upgrade") ?? "").toLowerCase() == "websocket" && req.header("sec-websocket-key") != null;

	// the request's connection taken over (Http.serve's handler returns null after)
	@:coroutine public static function upgrade(req:Request):WebSocket {
		if (!wants(req)) throw new Exception("not a WebSocket request");
		var accept = haxe.crypto.Base64.encode(haxe.crypto.Sha1.make(Bytes.ofString(req.header("sec-websocket-key") + GUID)));
		req.socket.writeString('HTTP/1.1 101 Switching Protocols\r\nupgrade: websocket\r\nconnection: Upgrade\r\nsec-websocket-accept: $accept\r\n\r\n');
		return new WebSocket(req.socket, req.reader, false);
	}

	@:coroutine public static function connect(host:String, port:Int, path = "/"):WebSocket {
		var s = Socket.connect(host, port);
		var key = haxe.crypto.Base64.encode(Bytes.ofString(Std.string(Math.random()).substr(0, 16)));
		s.writeString('GET $path HTTP/1.1\r\nhost: $host:$port\r\nupgrade: websocket\r\nconnection: Upgrade\r\nsec-websocket-key: $key\r\nsec-websocket-version: 13\r\n\r\n');
		var r = new Reader(s);
		var status = r.readLine();
		if (status == null || status.indexOf(" 101 ") < 0) {
			s.close();
			throw new Exception('WebSocket to $host:$port$path: $status');
		}
		while (true) {
			var h = r.readLine();
			if (h == null || h == "") break;
		}
		return new WebSocket(s, r, true);
	}

	// the next message; null once closed
	@:coroutine public function receive():Null<String> {
		var parts:Null<haxe.io.BytesBuffer> = null;
		while (!closed) {
			var head = try reader.readBytes(2) catch (e:haxe.io.Eof) null;
			if (head == null) {
				end();
				return null;
			}
			var fin = head.get(0) & 0x80 != 0, op = head.get(0) & 0x0F;
			var masked = head.get(1) & 0x80 != 0;
			var n = head.get(1) & 0x7F;
			if (n == 126) {
				var e = reader.readBytes(2);
				n = (e.get(0) << 8) | e.get(1);
			} else if (n == 127) {
				var e = reader.readBytes(8);
				n = (e.get(4) << 24) | (e.get(5) << 16) | (e.get(6) << 8) | e.get(7);
			}
			var mask = masked ? reader.readBytes(4) : null;
			var data = n > 0 ? reader.readBytes(n) : Bytes.alloc(0);
			if (mask != null) for (i in 0...n)
				data.set(i, data.get(i) ^ mask.get(i & 3));
			switch op {
				case 0x8:
					if (!closed) frame(0x8, data);
					end();
					return null;
				case 0x9:
					frame(0xA, data);
				case 0xA:
				case _:
					if (fin && parts == null) return data.toString();
					parts ??= new haxe.io.BytesBuffer();
					parts.add(data);
					if (fin) return parts.getBytes().toString();
			}
		}
		return null;
	}

	@:coroutine public function send(text:String):Void
		frame(0x1, Bytes.ofString(text));

	@:coroutine public function ping():Void
		frame(0x9, Bytes.alloc(0));

	// a close sent (the other side's answer ends receive), the connection closed
	@:coroutine public function close(code = 1000):Void {
		if (closed) return;
		var b = Bytes.alloc(2);
		b.set(0, code >> 8);
		b.set(1, code & 0xFF);
		try frame(0x8, b) catch (_:Exception) {}
		end();
	}

	function end() {
		closed = true;
		socket.close();
	}

	@:coroutine function frame(op:Int, data:Bytes):Void {
		if (closed) throw new Exception("WebSocket closed");
		var n = data.length;
		var ext = n < 126 ? 0 : n < 65536 ? 2 : 8;
		var b = Bytes.alloc(2 + ext + (client ? 4 : 0) + n);
		b.set(0, 0x80 | op);
		b.set(1, (client ? 0x80 : 0) | (ext == 0 ? n : ext == 2 ? 126 : 127));
		if (ext == 2) {
			b.set(2, n >> 8);
			b.set(3, n & 0xFF);
		} else if (ext == 8) for (i in 0...4)
			b.set(6 + i, (n >> (24 - 8 * i)) & 0xFF);
		var at = 2 + ext;
		if (client) {
			for (i in 0...4)
				b.set(at + i, Std.random(256));
			for (i in 0...n)
				b.set(at + 4 + i, data.get(i) ^ b.get(at + (i & 3)));
		} else b.blit(at, data, 0, n);
		lock.acquire();
		try socket.write(b, 0, b.length) catch (e:Exception) {
			lock.release();
			throw e;
		}
		lock.release();
	}

	static inline var GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
}
