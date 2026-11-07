package helder.ui.platform;

import haxe.io.Bytes;
import sys.net.Host;
import sys.net.Socket;

// A WebContent served over HTTP on 127.0.0.1 (WebContent.local: its
// origin http://127.0.0.1:<port>, a potentially trustworthy one), for
// what a custom scheme does not get: WebKit's cross-origin isolation is
// an HTTP origin's. A thread accepts, a thread per connection reads one
// request, answers it from the content (its status, headers, bytes) and
// closes; a POST to <secret>/__helder/post is a bridge's message
// (WebContent.onPost: macOS's, whose script messages WebKit cannot take on
// helder's main stack).
//
// Any process of the device can connect to a loopback port, so the server
// answers only its own web view (the README's "The web view", its threat
// model):
// - bound to 127.0.0.1 alone, never every address;
// - every request's path starts with /<secret>/, a random 256-bit secret
//   of the session's (helder.pack.Entropy: the system's CSPRNG) that only
//   the web view is given (its URLs: WebContent.url). The origin is the same
//   with or without it (http://127.0.0.1:<port>), so cross-origin isolation
//   and the page's own relative URLs are as they were. The request line is
//   read alone and its path compared in constant time first: without the
//   secret a 403, its headers never read;
// - the Host header is the server's own (127.0.0.1:<port>: no other name
//   resolving here, DNS rebinding);
// - the bridge takes a POST only, whose Origin is the page's own origin;
// - bounded: the request line within LINE_TIMEOUT, the whole request within
//   TIMEOUT, its line and headers within MAX_HEAD bytes, a body within
//   MAX_BODY (Content-Length, no chunks), at most MAX_CONNECTIONS
//   connections at once (the next ones wait in the listen queue).
class WebServer {
	// the request line and the headers, together
	public static var MAX_HEAD = 16 * 1024;
	// a bridge message's body (bytes go as base64 in it)
	public static var MAX_BODY = 64 * 1024 * 1024;
	public static var MAX_CONNECTIONS = 32;
	// seconds for the request line (before the secret is known: a connection that says nothing goes)
	public static var LINE_TIMEOUT = 5.0;
	// seconds for the whole request, its body too, and each write of the response
	public static var TIMEOUT = 30.0;

	public final port:Int;
	// the path's first segment, 64 hex digits
	public final secret:String;

	final content:WebContent;
	final socket:Socket;
	final slots:sys.thread.Semaphore;
	final prefix:Bytes;

	public function new(content:WebContent) {
		this.content = content;
		secret = helder.pack.Entropy.bytes(32).toHex();
		prefix = Bytes.ofString("/" + secret + "/");
		slots = new sys.thread.Semaphore(MAX_CONNECTIONS);
		socket = new Socket();
		socket.bind(new Host("127.0.0.1"), 0);
		socket.listen(64);
		port = socket.host().port;
		sys.thread.Thread.create(accept);
	}

	// the origin, the page's (no secret in it)
	public function origin():String
		return "http://127.0.0.1:" + port;

	function accept() {
		while (true) {
			// (a slot first: at most MAX_CONNECTIONS served at once, the others queued by the system)
			slots.acquire();
			var c = try socket.accept() catch (e:Dynamic) {
				slots.release();
				Sys.println("helder.ui: a web view's server: " + Std.string(e));
				return;
			}
			sys.thread.Thread.create(() -> {
				try serve(c) catch (_:Dynamic) {}
				linger(c);
				try c.close() catch (_:Dynamic) {}
				slots.release();
			});
		}
	}

	function serve(c:Socket) {
		var start = Sys.time();
		var r = new Reader(c, MAX_HEAD, start + LINE_TIMEOUT);
		var line = r.line();
		if (line == null) return; // (closed, too long or too slow: nothing said back)
		// (the secret first, nothing else read: METHOD SP /<secret>/... SP HTTP/1.x)
		var sp = line.indexOf(" ");
		var target = sp < 0 ? "" : line.substring(sp + 1, line.lastIndexOf(" ") > sp ? line.lastIndexOf(" ") : line.length);
		if (!authorized(target)) {
			reply(c, WebResponse.error(403, "text/plain", "forbidden"), false);
			return;
		}
		var method = line.substr(0, sp);
		r.deadline = start + TIMEOUT;
		var headers = new Map<String, String>();
		var count = 0;
		while (true) {
			var h = r.line();
			if (h == null) {
				if (r.tooLong) reply(c, WebResponse.error(431, "text/plain", "headers too large"), false);
				return;
			}
			if (h == "") break;
			if (++count > 100) {
				reply(c, WebResponse.error(431, "text/plain", "too many headers"), false);
				return;
			}
			var colon = h.indexOf(":");
			if (colon <= 0) {
				reply(c, WebResponse.error(400, "text/plain", "bad header"), false);
				return;
			}
			var k = h.substr(0, colon).toLowerCase(), v = StringTools.trim(h.substr(colon + 1));
			// (two of one: a request smuggled; Host, Origin and Content-Length once each)
			if (headers.exists(k) && (k == "host" || k == "origin" || k == "content-length")) {
				reply(c, WebResponse.error(400, "text/plain", "repeated " + k), false);
				return;
			}
			headers.set(k, v);
		}
		if (headers.get("host") != "127.0.0.1:" + port) {
			reply(c, WebResponse.error(403, "text/plain", "forbidden host"), false);
			return;
		}
		var path = target.substr(prefix.length - 1);
		var bridge = path == "/__helder/post" || StringTools.startsWith(path, "/__helder/post?");
		var res = if (bridge) {
			if (method != "POST") WebResponse.error(405, "text/plain", "POST only") else if (headers.get("origin") != origin())
				WebResponse.error(403, "text/plain", "forbidden origin") else if (content.onPost == null)
				WebResponse.error(404, "text/plain", "no bridge") else if (headers.exists("transfer-encoding"))
				WebResponse.error(411, "text/plain", "a length, no chunks") else {
				var n = length(headers.get("content-length"));
				if (n < 0) WebResponse.error(411, "text/plain", "a length") else if (n > MAX_BODY) WebResponse.error(413, "text/plain", "too large") else {
					var body = r.body(n);
					if (body == null) return;
					content.onPost(body.toString());
					WebResponse.error(204, "text/plain", "");
				}
			}
		} else if (method == "GET" || method == "HEAD") {
			content.respond(content.origin() + path);
		} else WebResponse.error(405, "text/plain", "GET only");
		reply(c, res, method == "HEAD");
	}

	// (the response sent, what the peer still sends read and dropped for a
	// moment, at most 64 KB: closed with unread bytes, the system would reset
	// the connection, the response perhaps lost on the way)
	static function linger(c:Socket) {
		try {
			c.shutdown(false, true);
			var end = Sys.time() + 0.5, buf = Bytes.alloc(4096), left = 64 * 1024;
			while (left > 0) {
				var t = end - Sys.time();
				if (t <= 0) break;
				c.setTimeout(Math.max(0.05, t));
				left -= c.input.readBytes(buf, 0, buf.length);
			}
		} catch (_:Dynamic) {}
	}

	// whether a target starts with /<secret>/: every byte compared, whatever differs
	public function authorized(target:String):Bool {
		var t = Bytes.ofString(target), n = prefix.length;
		var d = t.length < n ? 1 : 0;
		for (i in 0...n)
			d |= (i < t.length ? t.get(i) : 0) ^ prefix.get(i);
		return d == 0;
	}

	// a Content-Length: its digits alone, else -1
	static function length(v:Null<String>):Int {
		if (v == null || v.length == 0 || v.length > 10) return -1;
		var n = 0.0;
		for (i in 0...v.length) {
			var d = StringTools.fastCodeAt(v, i) - "0".code;
			if (d < 0 || d > 9) return -1;
			n = n * 10 + d;
		}
		return n > 0x7FFFFFFF ? 0x7FFFFFFF : Std.int(n);
	}

	function reply(c:Socket, r:WebResponse, head:Bool) {
		c.setTimeout(TIMEOUT);
		var b = new StringBuf();
		b.add('HTTP/1.1 ${r.status} ${WebResponse.reason(r.status)}\r\n');
		b.add('Content-Type: ${r.mime}\r\n');
		b.add('Content-Length: ${r.body.length}\r\n');
		b.add("Connection: close\r\n");
		for (k => v in r.headers)
			b.add('$k: $v\r\n');
		b.add("\r\n");
		c.output.writeString(b.toString());
		if (!head) c.output.writeFullBytes(r.body, 0, r.body.length);
		c.output.flush();
	}
}

// a connection's bytes in, buffered: lines within a budget of bytes, a body,
// each read before a deadline
private class Reader {
	public var deadline:Float;
	public var tooLong = false;

	final c:Socket;
	final buf:Bytes;
	var budget:Int;
	var pos = 0;
	var len = 0;

	public function new(c:Socket, budget:Int, deadline:Float) {
		this.c = c;
		this.budget = budget;
		this.deadline = deadline;
		buf = Bytes.alloc(4096);
	}

	// more bytes in the buffer, false when the peer is gone or the time up
	function fill():Bool {
		var left = deadline - Sys.time();
		if (left <= 0) return false;
		try {
			c.setTimeout(Math.max(0.05, left));
			pos = 0;
			len = c.input.readBytes(buf, 0, buf.length);
			return len > 0;
		} catch (_:Dynamic) {
			return false;
		}
	}

	// the next line without its CRLF (or LF); null once the budget, the time or the peer is gone
	public function line():Null<String> {
		var out = new haxe.io.BytesBuffer();
		while (true) {
			if (pos >= len && !fill()) return null;
			var b = buf.get(pos++);
			if (b == "\n".code) {
				var s = out.getBytes();
				var n = s.length > 0 && s.get(s.length - 1) == "\r".code ? s.length - 1 : s.length;
				return s.getString(0, n);
			}
			if (--budget < 0) {
				tooLong = true;
				return null;
			}
			out.addByte(b);
		}
	}

	// n bytes (what is left of the buffer first); null once the time or the peer is gone
	public function body(n:Int):Null<Bytes> {
		var out = Bytes.alloc(n), at = 0;
		while (at < n) {
			if (pos >= len && !fill()) return null;
			var k = Std.int(Math.min(len - pos, n - at));
			out.blit(at, buf, pos, k);
			pos += k;
			at += k;
		}
		return out;
	}
}
