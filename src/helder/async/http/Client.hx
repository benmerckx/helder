package helder.async.http;

import haxe.Exception;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.async.*;

// An HTTP/1.1 client on helder.async's TCP, for talking to a local server
// (plain http, one connection a request): the body read by Content-Length,
// chunked or until the server closes. No TLS, no redirects, no
// compression asked for.
//
//   var res = Client.request("http://127.0.0.1:4983/", {method: "POST", body: '{"type":"init"}',
//     headers: ["content-type" => "application/json"]});
//   trace(res.status, res.text());
class Client {
	@:coroutine public static function request(url:String, ?options:RequestOptions):Reply {
		var u = Url.parse(url);
		var method = options?.method ?? "GET";
		var body = options?.body ?? (options?.text != null ? Bytes.ofString(options.text) : Bytes.alloc(0));
		var head = new StringBuf();
		head.add('$method ${u.path} HTTP/1.1\r\nhost: ${u.host}:${u.port}\r\nconnection: close\r\n');
		final given = options?.headers ?? new Map();
		for (k => v in given)
			head.add('$k: $v\r\n');
		if (options?.contentType != null && !given.exists("content-type")) head.add('content-type: ${options.contentType}\r\n');
		if (body.length > 0 || method != "GET") head.add('content-length: ${body.length}\r\n');
		head.add("\r\n");
		var s = Socket.connect(u.host, u.port);
		try {
			var h = Bytes.ofString(head.toString());
			var out = Bytes.alloc(h.length + body.length);
			out.blit(0, h, 0, h.length);
			out.blit(h.length, body, 0, body.length);
			s.write(out, 0, out.length);
			var reply = read(new Reader(s), method == "HEAD");
			s.close();
			return reply;
		} catch (e:Exception) {
			s.close();
			throw e;
		}
	}

	@:coroutine static function read(r:Reader, head:Bool):Reply {
		var line = r.readLine();
		if (line == null) throw new Exception("no response");
		var parts = line.split(" ");
		var status = Std.parseInt(parts[1] ?? "");
		if (status == null) throw new Exception("bad status line");
		var headers = new Map<String, String>();
		while (true) {
			var h = r.readLine();
			if (h == null) throw new Exception("end of headers missing");
			if (h == "") break;
			var i = h.indexOf(":");
			if (i <= 0) continue;
			var k = h.substr(0, i).toLowerCase(), v = StringTools.trim(h.substr(i + 1));
			headers.set(k, headers.exists(k) ? headers.get(k) + ", " + v : v);
		}
		if (head || status == 204 || status == 304) return new Reply(status, headers, Bytes.alloc(0));
		var length = headers.get("content-length");
		if (length != null) return new Reply(status, headers, r.readBytes(Std.parseInt(length) ?? 0));
		if ((headers.get("transfer-encoding") ?? "").toLowerCase().indexOf("chunked") >= 0) return new Reply(status, headers, chunked(r));
		return new Reply(status, headers, r.readAll());
	}

	@:coroutine static function chunked(r:Reader):Bytes {
		var out = new BytesBuffer();
		while (true) {
			var size = r.readLine();
			if (size == null) throw new Exception("chunk missing");
			var semi = size.indexOf(";");
			var n = Std.parseInt("0x" + StringTools.trim(semi < 0 ? size : size.substr(0, semi)));
			if (n == null) throw new Exception("bad chunk size");
			if (n == 0) {
				// (trailers until the blank line)
				while (true) {
					var t = r.readLine();
					if (t == null || t == "") break;
				}
				return out.getBytes();
			}
			out.add(r.readBytes(n));
			r.readLine();
		}
	}
}

typedef RequestOptions = {
	?method:String,
	// names as given, sent as they are
	?headers:Map<String, String>,
	?body:Bytes,
	// the body as text (UTF-8), when body is not given
	?text:String,
	// its content-type header ("application/json")
	?contentType:String
}

class Reply {
	public final status:Int;
	// names in lower case
	public final headers:Map<String, String>;
	public final body:Bytes;

	public function new(status, headers, body) {
		this.status = status;
		this.headers = headers;
		this.body = body;
	}

	public inline function header(name:String):Null<String>
		return headers.get(name.toLowerCase());

	public function text():String
		return body.toString();
}

private class Url {
	public final host:String;
	public final port:Int;
	public final path:String;

	function new(host, port, path) {
		this.host = host;
		this.port = port;
		this.path = path;
	}

	public static function parse(url:String):Url {
		if (!StringTools.startsWith(url, "http://")) throw new Exception('only http urls: $url');
		var rest = url.substr(7);
		var slash = rest.indexOf("/");
		var authority = slash < 0 ? rest : rest.substr(0, slash);
		var path = slash < 0 ? "/" : rest.substr(slash);
		var colon = authority.lastIndexOf(":");
		if (colon < 0) return new Url(authority, 80, path);
		var port = Std.parseInt(authority.substr(colon + 1));
		if (port == null) throw new Exception('bad port: $url');
		return new Url(authority.substr(0, colon), port, path);
	}
}
