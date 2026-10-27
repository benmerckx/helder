package helder.async.http;

import haxe.Exception;
import haxe.coro.Coroutine;
import haxe.io.Bytes;
import helder.async.*;

// A minimal HTTP/1.1 server on helder.async's TCP: enough for a dev server.
// Each connection is a child task of the caller's; its requests (kept alive)
// go to the handler in turn, whose Response is written back; a null one
// means the handler took the connection over (WebSocket.upgrade). Bodies
// by Content-Length (no chunked requests); an error in the handler is a 500
// and the connection closed, the server going on.
//
//   var server = Server.listen("127.0.0.1", 8080);
//   Http.serve(server, req -> Http.file("public", req.path) ?? Response.text("not found", 404));
class Http {
	@:coroutine public static function serve(server:Server, handler:Coroutine<Request->Null<Response>>):Void {
		var node = Async.context().get(Node.key);
		while (true) {
			var s = server.accept();
			node.async(_ -> connection(s, handler));
		}
	}

	@:coroutine static function connection(s:Socket, handler:Coroutine<Request->Null<Response>>):Void {
		var r = new Reader(s);
		var open = true;
		while (open) {
			var req = try Request.read(s, r) catch (e:Exception) null;
			if (req == null) break;
			var res = try handler(req) catch (e:Exception) {
				if (e is haxe.exceptions.CancellationException) {
					s.close();
					throw e;
				}
				Response.text("error: " + e.message, 500);
			}
			if (res == null) return;
			open = req.keepAlive();
			try res.write(s, req.method == "HEAD", open) catch (e:Exception) open = false;
		}
		s.close();
	}

	// the file at root + path (its index.html for a directory), as a response
	// with its type; null when there is none (or the path leaves root)
	public static function file(root:String, path:String):Null<Response> {
		if (path.indexOf("..") >= 0 || path.indexOf("\\") >= 0) return null;
		var p = root + (StringTools.startsWith(path, "/") ? path : "/" + path);
		if (sys.FileSystem.exists(p) && sys.FileSystem.isDirectory(p)) p += (StringTools.endsWith(p, "/") ? "" : "/") + "index.html";
		if (!sys.FileSystem.exists(p) || sys.FileSystem.isDirectory(p)) return null;
		var res = new Response(200, sys.io.File.getBytes(p));
		res.headers.set("content-type", mime(p));
		return res;
	}

	public static function mime(path:String):String {
		var ext = path.substr(path.lastIndexOf(".") + 1).toLowerCase();
		return switch ext {
			case "html", "htm": "text/html; charset=utf-8";
			case "js", "mjs": "text/javascript; charset=utf-8";
			case "css": "text/css; charset=utf-8";
			case "json", "map": "application/json";
			case "wasm": "application/wasm";
			case "png": "image/png";
			case "jpg", "jpeg": "image/jpeg";
			case "gif": "image/gif";
			case "webp": "image/webp";
			case "svg": "image/svg+xml";
			case "txt": "text/plain; charset=utf-8";
			case "glb": "model/gltf-binary";
			case "wav": "audio/wav";
			case "ttf", "otf": "font/" + ext;
			case _: "application/octet-stream";
		}
	}
}

class Request {
	public final method:String;
	// decoded, without the query
	public final path:String;
	public final query:String;
	public final version:String;
	// names in lower case
	public final headers:Map<String, String>;
	public var body(default, null):Bytes;
	public final socket:Socket;
	public final reader:Reader;

	function new(method, path, query, version, headers, socket, reader) {
		this.method = method;
		this.path = path;
		this.query = query;
		this.version = version;
		this.headers = headers;
		this.socket = socket;
		this.reader = reader;
	}

	public inline function header(name:String):Null<String>
		return headers.get(name.toLowerCase());

	public function keepAlive():Bool {
		var c = (header("connection") ?? "").toLowerCase();
		return version == "HTTP/1.1" ? c.indexOf("close") < 0 : c.indexOf("keep-alive") >= 0;
	}

	// the next request on the connection; null at its end
	@:coroutine public static function read(s:Socket, r:Reader):Null<Request> {
		var line = r.readLine();
		if (line == null) return null;
		if (line == "") line = r.readLine();
		if (line == null) return null;
		var parts = line.split(" ");
		if (parts.length != 3) throw new Exception("bad request line");
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
		var target = parts[1], q = target.indexOf("?");
		var path = StringTools.urlDecode(q < 0 ? target : target.substr(0, q));
		var req = new Request(parts[0], path, q < 0 ? "" : target.substr(q + 1), parts[2], headers, s, r);
		var n = Std.parseInt(headers.get("content-length") ?? "0") ?? 0;
		req.body = n > 0 ? r.readBytes(n) : Bytes.alloc(0);
		return req;
	}
}

class Response {
	public var status:Int;
	// names in lower case
	public final headers = new Map<String, String>();
	public var body:Bytes;

	public function new(status = 200, ?body:Bytes) {
		this.status = status;
		this.body = body ?? Bytes.alloc(0);
	}

	public static function text(s:String, status = 200, type = "text/plain; charset=utf-8"):Response {
		var r = new Response(status, Bytes.ofString(s));
		r.headers.set("content-type", type);
		return r;
	}

	@:coroutine public function write(s:Socket, head:Bool, keepAlive:Bool):Void {
		var b = new StringBuf();
		b.add('HTTP/1.1 $status ${reason(status)}\r\n');
		for (k => v in headers)
			b.add('$k: $v\r\n');
		if (!headers.exists("content-length")) b.add('content-length: ${body.length}\r\n');
		if (!headers.exists("connection")) b.add(keepAlive ? "connection: keep-alive\r\n" : "connection: close\r\n");
		b.add("\r\n");
		var h = Bytes.ofString(b.toString());
		if (head || body.length == 0) s.write(h, 0, h.length) else {
			var all = Bytes.alloc(h.length + body.length);
			all.blit(0, h, 0, h.length);
			all.blit(h.length, body, 0, body.length);
			s.write(all, 0, all.length);
		}
	}

	static function reason(status:Int):String
		return switch status {
			case 101: "Switching Protocols";
			case 200: "OK";
			case 204: "No Content";
			case 304: "Not Modified";
			case 400: "Bad Request";
			case 404: "Not Found";
			case 405: "Method Not Allowed";
			case 500: "Internal Server Error";
			case _: "Status";
		}
}
