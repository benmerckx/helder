package helder.ui.platform;

import haxe.io.Bytes;
import helder.test.Test;

// The web view's loopback server (WebServer: Apple's WebContent.local, here
// on the host natively, the same code) as another process of the device
// sees it, through raw sockets: without its secret every request a 403
// (a wrong one of the same length too, and before its headers are read);
// with it the content and its cross-origin isolation's headers; the bridge
// a POST from the page's own origin alone; a foreign Host refused; the
// head's and the body's limits, the request line's timeout and the
// connections' cap.
function tests() {
	describe("WebServer", () -> {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		var posted:Array<String> = [];
		function content():WebContent {
			var c = WebContent.handler(path -> path == "index.html" ? WebResponse.text("<p>hello</p>", "text/html") : null);
			c.local = true;
			@:privateAccess c.onPost = s -> posted.push(s);
			return c;
		}
		var c = content();
		var server:WebServer = @:privateAccess c.started();
		var host = '127.0.0.1:${server.port}';

		test("its origin has no secret, its URLs have it, unguessable", () -> {
			equals(c.origin(), 'http://$host');
			assert(StringTools.startsWith(c.url("index.html"), 'http://$host/${server.secret}/'));
			assert(~/^[0-9a-f]{64}$/.match(server.secret), server.secret);
			// (each server its own)
			notEquals(@:privateAccess content().started().secret, server.secret);
		});
		test("without the secret: 403", () -> {
			var r = request(server.port, 'GET /index.html HTTP/1.1\r\nHost: $host\r\n\r\n');
			equals(r.status, 403);
			assert(r.text.indexOf("hello") < 0);
			equals(request(server.port, 'GET / HTTP/1.1\r\nHost: $host\r\n\r\n').status, 403);
			equals(request(server.port, 'GET /${server.secret} HTTP/1.1\r\nHost: $host\r\n\r\n').status, 403);
			equals(request(server.port, 'GET /x/${server.secret}/index.html HTTP/1.1\r\nHost: $host\r\n\r\n').status, 403);
			equals(request(server.port, 'POST /__helder/post HTTP/1.1\r\nHost: $host\r\nOrigin: http://$host\r\nContent-Length: 2\r\n\r\nsx').status, 403);
			equals(posted, []);
		});
		test("a wrong secret of the same length: 403", () -> {
			var last = server.secret.charAt(63) == "0" ? "1" : "0";
			var wrong = server.secret.substr(0, 63) + last;
			equals(request(server.port, 'GET /$wrong/index.html HTTP/1.1\r\nHost: $host\r\n\r\n').status, 403);
			var first = (server.secret.charAt(0) == "0" ? "1" : "0") + server.secret.substr(1);
			equals(request(server.port, 'GET /$first/index.html HTTP/1.1\r\nHost: $host\r\n\r\n').status, 403);
		});
		test("refused on the request line alone, its headers never awaited", () -> {
			// (no blank line, the connection kept open: the 403 comes all the same)
			var t = Sys.time();
			var r = request(server.port, 'GET /index.html HTTP/1.1\r\nHost: $host\r\nX-Never: ', false);
			equals(r.status, 403);
			assert(Sys.time() - t < 2, "answered at once");
		});
		test("with the secret: the content, cross-origin isolated", () -> {
			var r = request(server.port, 'GET /${server.secret}/index.html HTTP/1.1\r\nHost: $host\r\n\r\n');
			equals(r.status, 200);
			assert(r.text.indexOf("<p>hello</p>") > 0, r.text);
			assert(r.text.indexOf("Cross-Origin-Opener-Policy: same-origin") > 0);
			assert(r.text.indexOf("Cross-Origin-Embedder-Policy: require-corp") > 0);
			equals(request(server.port, 'GET /${server.secret}/ HTTP/1.1\r\nHost: $host\r\n\r\n').status, 200);
			equals(request(server.port, 'GET /${server.secret}/missing.js HTTP/1.1\r\nHost: $host\r\n\r\n').status, 404);
			equals(request(server.port, 'DELETE /${server.secret}/index.html HTTP/1.1\r\nHost: $host\r\n\r\n').status, 405);
		});
		test("another Host (a name rebound to 127.0.0.1): 403", () -> {
			equals(request(server.port, 'GET /${server.secret}/index.html HTTP/1.1\r\nHost: evil.example:${server.port}\r\n\r\n').status, 403);
			equals(request(server.port, 'GET /${server.secret}/index.html HTTP/1.1\r\n\r\n').status, 403);
		});
		test("the bridge: a POST from the page's origin alone", () -> {
			posted.resize(0);
			var at = '/${server.secret}/__helder/post';
			equals(request(server.port, 'POST $at HTTP/1.1\r\nHost: $host\r\nOrigin: http://evil.example\r\nContent-Length: 3\r\n\r\nsno').status, 403);
			equals(request(server.port, 'POST $at HTTP/1.1\r\nHost: $host\r\nOrigin: http://127.0.0.1:1\r\nContent-Length: 3\r\n\r\nsno').status, 403);
			equals(request(server.port, 'POST $at HTTP/1.1\r\nHost: $host\r\nOrigin: null\r\nContent-Length: 3\r\n\r\nsno').status, 403);
			equals(request(server.port, 'POST $at HTTP/1.1\r\nHost: $host\r\nContent-Length: 3\r\n\r\nsno').status, 403);
			equals(request(server.port, 'GET $at HTTP/1.1\r\nHost: $host\r\nOrigin: http://$host\r\n\r\n').status, 405);
			equals(request(server.port, 'POST $at HTTP/1.1\r\nHost: $host\r\nOrigin: http://$host\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nsno\r\n0\r\n\r\n').status, 411);
			equals(posted, []);
			equals(request(server.port, 'POST $at HTTP/1.1\r\nHost: $host\r\nOrigin: http://$host\r\nContent-Length: 4\r\n\r\nsyes').status, 204);
			equals(posted, ["syes"]);
		});
		test("limits: the head, the body", () -> {
			var big = StringTools.lpad("", "a", WebServer.MAX_HEAD);
			equals(request(server.port, 'GET /${server.secret}/index.html HTTP/1.1\r\nHost: $host\r\nX-Big: $big\r\n\r\n').status, 431);
			// (a request line past the limit, with or without the secret: nothing said, closed)
			equals(request(server.port, 'GET /$big HTTP/1.1\r\n\r\n').status, -1);
			var was = WebServer.MAX_BODY;
			WebServer.MAX_BODY = 1024;
			var at = '/${server.secret}/__helder/post';
			equals(request(server.port, 'POST $at HTTP/1.1\r\nHost: $host\r\nOrigin: http://$host\r\nContent-Length: 1025\r\n\r\n').status, 413);
			equals(request(server.port, 'POST $at HTTP/1.1\r\nHost: $host\r\nOrigin: http://$host\r\nContent-Length: 99999999999\r\n\r\n').status, 411);
			WebServer.MAX_BODY = was;
		});
		test("a connection that says nothing is closed; at most MAX_CONNECTIONS at once", () -> {
			var line = WebServer.LINE_TIMEOUT, max = WebServer.MAX_CONNECTIONS;
			WebServer.LINE_TIMEOUT = 0.5;
			WebServer.MAX_CONNECTIONS = 2;
			var c2 = content(), s2:WebServer = @:privateAccess c2.started();
			WebServer.MAX_CONNECTIONS = max;
			var idle = [for (_ in 0...2) connect(s2.port)];
			var t = Sys.time();
			// (the third waits for a slot: one of the idle ones timed out)
			var r = request(s2.port, 'GET /${s2.secret}/index.html HTTP/1.1\r\nHost: 127.0.0.1:${s2.port}\r\n\r\n');
			var waited = Sys.time() - t;
			equals(r.status, 200);
			assert(waited >= 0.3 && waited < 5, 'waited $waited s');
			// (the idle ones closed by the server, nothing said)
			for (s in idle) {
				equals(readAll(s), "");
				s.close();
			}
			WebServer.LINE_TIMEOUT = line;
		});
		#end
	});
}

#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
private function connect(port:Int):sys.net.Socket {
	var s = new sys.net.Socket();
	s.connect(new sys.net.Host("127.0.0.1"), port);
	s.setTimeout(10);
	return s;
}

private function readAll(s:sys.net.Socket):String {
	var out = new haxe.io.BytesBuffer(), buf = Bytes.alloc(4096);
	while (true) {
		var n = try s.input.readBytes(buf, 0, buf.length) catch (_:Dynamic) 0;
		if (n <= 0) break;
		out.addBytes(buf, 0, n);
	}
	return out.getBytes().toString();
}

// a raw request; its status (-1: closed without a word) and what came back
private function request(port:Int, raw:String, close = true):{status:Int, text:String} {
	var s = connect(port);
	try s.output.writeString(raw) catch (_:Dynamic) {}
	if (close) try s.shutdown(false, true) catch (_:Dynamic) {}
	var text = readAll(s);
	s.close();
	var m = ~/^HTTP\/1\.1 ([0-9]{3}) /;
	return {status: m.match(text) ? Std.parseInt(m.matched(1)) : -1, text: text};
}
#end
