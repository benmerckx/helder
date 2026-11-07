package helder.ui.platform;

import haxe.io.Bytes;

// What a web view's own origin serves (WebView.content): the files of the
// app's bundle (assets the program names, helder.asset's keys under a
// prefix) or of a directory, or a function's responses, each with headers
// of its own beside the MIME type its extension gives. By default every
// response is cross-origin isolated (COOP same-origin, COEP require-corp,
// CORP same-origin: the page's crossOriginIsolated, SharedArrayBuffer and
// wasm threads), never cached, and a .wasm is application/wasm (what
// WebAssembly.instantiateStreaming asks for).
//
// The origin is the platform's: on iOS and macOS http://127.0.0.1:<port>,
// a loopback server of the app's own (WebServer: WebKit isolates HTTP
// origins only), or, with local false, a custom scheme (WKURLSchemeHandler:
// `app://localhost/`, the scheme WebContent.scheme); on Android https on a host of its own (shouldInterceptRequest, as
// WebViewAssetLoader does: `https://appassets.androidplatform.net/`), so
// the page is a secure context everywhere. `url(path)` is a path's URL
// there (on the loopback under the server's secret, base(): WebServer
// answers nothing else, its origin the same); a web view's src may be a
// path, resolved against it.
//
//   var content = WebContent.bundle("web/");                  // Asset.bytes("web/index.html") etc. in the bundle
//   var content = WebContent.directory(dir);                  // a folder on disk
//   var content = WebContent.handler(path -> WebResponse.text("hi"));
class WebContent {
	// the custom scheme on Apple's systems
	public var scheme = "app";
	// the host (Apple: app://<host>/; Android: https://<host>/)
	public var host = "localhost";
	// the headers every response gets (cross-origin isolation, no cache)
	public final headers:Map<String, String> = [
		"Cross-Origin-Opener-Policy" => "same-origin",
		"Cross-Origin-Embedder-Policy" => "require-corp",
		"Cross-Origin-Resource-Policy" => "same-origin",
		"Cache-Control" => "no-cache"
	];
	// the path a directory's request gets (a path ending in /)
	public var index = "index.html";
	// served over HTTP on the loopback address instead of a scheme
	// (WebServer: http://127.0.0.1:<port>), set before its first use: by
	// default on Apple's systems, whose WebKit isolates (crossOriginIsolated,
	// SharedArrayBuffer) an HTTP origin, never a custom scheme's; Android's
	// scheme (https, intercepted) puts the bridge in its pages first
	public var local = #if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64" || hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64") true #else false #end;
	var server:Null<WebServer> = null;
	// (WebServer's POSTs to /__helder/post: a bridge's messages, on its threads)
	@:allow(helder.ui.platform) var onPost:Null<String->Void> = null;

	final serve:String->Null<WebResponse>;
	// bytes posted to the page (WebView.postBytes): fetched once from /__helder/bytes/<id>
	final posted = new Map<Int, Bytes>();
	var nextPosted = 1;
	final lock = new sys.thread.Mutex();

	public function new(serve:String->Null<WebResponse>) {
		this.serve = serve;
		#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		host = "appassets.androidplatform.net";
		#end
	}

	// the bundle's files under prefix (helder.asset's keys: each must be
	// named by the program, Asset.bytes(prefix + path), to be bundled)
	// (none in a browser: a page has no web view of its own here, and its
	// program does not take helder.asset's fetches for it)
	public static function bundle(prefix = ""):WebContent
		return new WebContent(path -> {
			#if (hxmc.target == "wasm32-wasi")
			return null;
			#else
			var b = try helder.asset.Files.readNow(prefix + path) catch (_:Dynamic) null;
			return b == null ? null : WebResponse.bytes(b, WebResponse.mimeOf(path));
			#end
		});

	// the files of a directory on disk
	public static function directory(dir:String):WebContent
		return new WebContent(path -> {
			var f = haxe.io.Path.join([dir, path]);
			if (!sys.FileSystem.exists(f) || sys.FileSystem.isDirectory(f)) return null;
			var b = try sys.io.File.getBytes(f) catch (_:Dynamic) null;
			b == null ? null : WebResponse.bytes(b, WebResponse.mimeOf(path));
		});

	// a function's responses, by path (null: 404)
	public static function handler(f:String->Null<WebResponse>):WebContent
		return new WebContent(f);

	// the origin, without a slash at the end (the loopback's: no secret in it)
	public function origin():String {
		#if (hxmc.target != "wasm32-wasi")
		if (local) return started().origin();
		#end
		#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		return "https://" + host;
		#else
		return scheme + "://" + host;
		#end
	}

	#if (hxmc.target != "wasm32-wasi")
	function started():WebServer {
		lock.acquire();
		if (server == null) server = try new WebServer(this) catch (e:Dynamic) {
			lock.release();
			throw e;
		}
		lock.release();
		return server;
	}
	#end

	// what every URL of the content starts with, without a slash at the end:
	// the origin, and on the loopback the server's secret after it
	// (http://127.0.0.1:<port>/<secret>: WebServer answers nothing else)
	public function base():String {
		#if (hxmc.target != "wasm32-wasi")
		if (local) return origin() + "/" + started().secret;
		#end
		return origin();
	}

	// a path's URL at the origin (on the loopback under its secret: the
	// page's relative URLs are too, never a path from the root)
	public function url(path:String):String
		return base() + "/" + (StringTools.startsWith(path, "/") ? path.substr(1) : path);

	// whether a URL is the content's (the request this handles)
	public function owns(url:String):Bool
		return StringTools.startsWith(url, base() + "/") || url == base();

	// the response to a URL of the content's (any thread: Android's requests
	// come on the web view's own); 404 when nothing serves it
	public function respond(url:String):WebResponse {
		var b = base();
		var path = StringTools.startsWith(url, b + "/") ? url.substr(b.length) : StringTools.startsWith(url, origin()) ? url.substr(origin().length) : url;
		var q = path.indexOf("?"), h = path.indexOf("#");
		if (h >= 0 && (q < 0 || h < q)) q = h;
		if (q >= 0) path = path.substr(0, q);
		path = StringTools.urlDecode(path);
		while (StringTools.startsWith(path, "/"))
			path = path.substr(1);
		if (path == "" || StringTools.endsWith(path, "/")) path += index;
		var r:Null<WebResponse> = null;
		if (StringTools.startsWith(path, "__helder/bytes/")) {
			var id = Std.parseInt(path.substr(15));
			lock.acquire();
			var b = id == null ? null : posted.get(id);
			if (id != null) posted.remove(id);
			lock.release();
			if (b != null) r = WebResponse.bytes(b, "application/octet-stream");
		} else if (path.indexOf("..") < 0) r = try serve(path) catch (e:Dynamic) {
			Sys.println("helder.ui: a web view's request " + path + ": " + Std.string(e));
			WebResponse.error(500, "text/plain", Std.string(e));
		}
		if (r == null) r = WebResponse.error(404, "text/plain", "not found: " + path);
		for (k => v in headers)
			if (!r.headers.exists(k)) r.headers.set(k, v);
		return r;
	}

	// (WebView.postBytes) bytes kept for the page to fetch once: their path
	@:allow(helder.ui.platform) function keep(b:Bytes):String {
		lock.acquire();
		var id = nextPosted++;
		posted.set(id, b);
		lock.release();
		return url("__helder/bytes/" + id);
	}
}

