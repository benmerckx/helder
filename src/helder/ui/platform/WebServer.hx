package helder.ui.platform;

import haxe.io.Bytes;
import sys.net.Host;
import sys.net.Socket;

// A WebContent served over HTTP on 127.0.0.1 (WebContent.local: its
// origin http://127.0.0.1:<port>, a potentially trustworthy one), for
// what a custom scheme does not get: WebKit's cross-origin isolation is
// an HTTP origin's. A thread accepts, a thread per connection reads a
// request (GET or HEAD; its headers to the blank line), answers it from
// the content (its status, headers, bytes) and closes. Nothing but the
// machine itself reaches it (the loopback address).
class WebServer {
	public final port:Int;
	final content:WebContent;
	final socket:Socket;

	public function new(content:WebContent) {
		this.content = content;
		socket = new Socket();
		socket.bind(new Host("127.0.0.1"), 0);
		socket.listen(64);
		port = socket.host().port;
		sys.thread.Thread.create(accept);
	}

	function accept() {
		while (true) {
			var c = try socket.accept() catch (e:Dynamic) {
				Sys.println("helder.ui: a web view's server: " + Std.string(e));
				return;
			}
			sys.thread.Thread.create(() -> try serve(c) catch (e:Dynamic) try c.close() catch (_:Dynamic) {});
		}
	}

	function serve(c:Socket) {
		var head = new StringBuf(), line = "", first = "";
		// (the request line, then its headers up to the blank line)
		while (true) {
			line = c.input.readLine();
			if (first == "") first = line;
			if (StringTools.trim(line) == "") break;
			head.add(line);
		}
		var parts = first.split(" ");
		var method = parts[0], target = parts.length > 1 ? parts[1] : "/";
		var r = method == "GET" || method == "HEAD" ? content.respond(content.origin() + target) : WebResponse.error(405, "text/plain", "GET only");
		var b = new StringBuf();
		b.add('HTTP/1.1 ${r.status} ${WebResponse.reason(r.status)}\r\n');
		b.add('Content-Type: ${r.mime}\r\n');
		b.add('Content-Length: ${r.body.length}\r\n');
		b.add("Connection: close\r\n");
		for (k => v in r.headers)
			b.add('$k: $v\r\n');
		b.add("\r\n");
		c.output.writeString(b.toString());
		if (method != "HEAD") c.output.writeFullBytes(r.body, 0, r.body.length);
		c.output.flush();
		c.close();
	}
}
