import haxe.io.Bytes;
import helder.asset.Asset;
import helder.ui.draw.UiWindow;
import helder.ui.platform.*;
import helder.ui.platform.PlatformWebView;
import helder.ui.platform.WebContent;
import helder.view.*;

// helder.ui.platform's web view on a phone (CI's simulator and emulator
// jobs: tests/platform/webview.sh reads its lines, simctl's and logcat's):
// a drawn window with a header and a <webview> below it (WebView: a
// WKWebView over the HxmcView, Android's WebView in a panel window), or,
// from WebShellCheck, the whole screen (WebShell). Its page
// (webview/index.html, bundled: WebContent.bundle) comes from the web
// view's own origin with COOP and COEP: it reports crossOriginIsolated,
// instantiates webview/add.wasm (application/wasm) and posts the result;
// native replies with a string and with bytes, the page answers both, and
// the round trip is checked. Then a still of the page (snapshot), and, when
// a helder web build is there (HELDER_WEB_DIR, else the app's files/todo:
// examples/todo for the web), that build loaded in the same web view, its
// canvas and its module running reported. Ends with "webview: N checks, ok"
// (or FAILED) and exits.
//   helder build tests/platform/WebViewCheck.hx --target ios-sim | android-x86_64
class WebViewCheck implements Markup {
	static var failed = 0;
	static var checks = 0;
	static var step = 0;
	static var webDir:Null<String> = null;
	public static var post:String->Void;
	public static var postBytes:Bytes->Void;
	public static var load:String->Void;
	public static var snapshot:(Null<WebSnapshot>->Void)->Void;
	public static var content:WebContent;
	public static var evalJs:String->Void = _ -> {};
	static var mode = "embedded";

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) failed++;
		Sys.println('webview: ${ok ? "ok" : "FAIL"}: $what' + (detail == null ? "" : " (" + detail + ")"));
	}

	static function end() {
		Sys.println('webview: $mode: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function main() {
		start("embedded");
		var w = new UiWindow("WebView", 400, 700);
		var me = new WebViewCheck();
		Render.render(me.view(), w.root);
		UiWindow.run();
	}

	// the page's content and the web build's directory
	public static function start(m:String) {
		mode = m;
		Sys.println('webview: started ($mode)');
		// (bundled: the keys named)
		Asset.bytes("webview/index.html");
		Asset.bytes("webview/add.wasm");
		webDir = Sys.getEnv("HELDER_WEB_DIR");
		#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		if (webDir == null || webDir == "") {
			var a = helder.os.android.Activity.activity;
			var p:hxmc.unsafe.Ptr<hxmc.unsafe.UInt8> = hxmc.unsafe.Mem.getPtr(a, 32); // ANativeActivity.internalDataPath
			if (!p.isNull()) webDir = (p : hxmc.unsafe.CString).toString() + "/todo";
		}
		#end
		if (webDir != null && !sys.FileSystem.exists(webDir + "/Todo.html")) {
			Sys.println('webview: no web build at $webDir');
			webDir = null;
		}
		var bundled = WebContent.bundle("");
		content = WebContent.handler(path -> {
			if (StringTools.startsWith(path, "todo/") && webDir != null) {
				var f = webDir + "/" + path.substr(5);
				return sys.FileSystem.exists(f) ? WebResponse.bytes(sys.io.File.getBytes(f), WebResponse.mimeOf(f)) : null;
			}
			return @:privateAccess bundled.serve("webview/" + path);
		});
		// (HELDER_WEBVIEW_LOCAL: 1 over HTTP on the loopback address, WebServer; 0 the scheme; else the platform's default)
		var local = Sys.getEnv("HELDER_WEBVIEW_LOCAL");
		if (local == "1" || local == "0") content.local = local == "1";
		Sys.println("webview: content at " + content.origin());
		#if !(hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		if (content.local) outsider();
		#end
	}

	// (the loopback server as another process sees it, a raw socket of the
	// app's own: no secret, a wrong one, the bridge from another origin, all
	// refused; webview-ios.sh and webview-macos.sh try the same with curl)
	static function outsider() {
		var port = Std.parseInt(content.origin().substr(content.origin().lastIndexOf(":") + 1));
		var host = '127.0.0.1:$port';
		var secret = content.base().substr(content.origin().length + 1);
		function status(raw:String):Int {
			var s = new sys.net.Socket();
			try {
				s.connect(new sys.net.Host("127.0.0.1"), port);
				s.setTimeout(10);
				s.output.writeString(raw);
				var b = new haxe.io.BytesBuffer(), buf = Bytes.alloc(4096);
				while (true) {
					var n = try s.input.readBytes(buf, 0, buf.length) catch (_:Dynamic) 0;
					if (n <= 0) break;
					b.addBytes(buf, 0, n);
				}
				s.close();
				var m = ~/^HTTP\/1\.1 ([0-9]{3}) /;
				var t = b.getBytes().toString();
				return m.match(t) ? Std.parseInt(m.matched(1)) : -1;
			} catch (e:Dynamic) {
				s.close();
				return -2;
			}
		}
		var wrong = (secret.charAt(0) == "0" ? "1" : "0") + secret.substr(1);
		var s = status('GET /index.html HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n');
		check("the loopback without the secret: 403", s == 403, '$s');
		s = status('GET /$wrong/index.html HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n');
		check("the loopback with a wrong secret: 403", s == 403, '$s');
		s = status('POST /$secret/__helder/post HTTP/1.1\r\nHost: $host\r\nOrigin: http://evil.example\r\nContent-Length: 4\r\nConnection: close\r\n\r\nsbad');
		check("the bridge from another origin: 403", s == 403, '$s');
		s = status('GET /$secret/index.html HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n');
		check("the loopback with the secret: 200", s == 200, '$s');
	}

	var node:Null<WebView> = null;

	public function new() {}

	public function view():View
		return <view tag="app" width="100%" height="100%" background="#fef3c7">
			<view tag="header" padding={16} padding-top="env(safe-area-inset-top)" background="#f59e0b">
				<text font-size={20}>helder: a web view below</text>
			</view>
			<webview tag="web" ref={n -> attached(cast n)} content={content} src="index.html" inspectable grow={1} margin={12}
				onMessage={e -> event(e)} onLoad={e -> event(e)} onLoadError={e -> event(e)} onConsole={e -> event(e)} onTitle={e -> event(e)}/>
		</view>;

	function attached(n:WebView) {
		node = n;
		post = n.post;
		postBytes = n.postBytes;
		load = s -> n.src = s;
		evalJs = n.eval;
		snapshot = n.snapshot;
	}

	// (the shell's too: WebShellCheck)
	public static function event(e:WebViewEvent) {
		switch e.kind {
			case Console: Sys.println("webview: console: " + e.text);
			case Title: Sys.println("webview: title: " + e.text);
			case Load: Sys.println("webview: loaded " + e.url);
			case LoadError: Sys.println('webview: load error ${e.code}: ${e.text} (${e.url})');
			case Message: message(e);
			case _:
		}
		// (the web build's page: polled for its canvas and its module)
		if (step == 5 && e.kind == Load && StringTools.endsWith(e.url, "Todo.html")) probeWeb();
	}

	static function message(e:WebViewEvent) {
		Sys.println('webview: message: ' + (e.bytes != null ? 'bytes ${e.bytes.length}' : e.text));
		switch step {
			case 0:
				var r:Dynamic = e.json();
				check("the page's result came through the bridge (JSON)", e.isJson && r.kind == "result", e.text);
				check("a secure context (" + r.origin + ")", r.secure == true);
				check("the scheme handler's headers: COOP, COEP, application/wasm", r.coop == "same-origin" && r.coep == "require-corp" && r.mime == "application/wasm",
					'${r.coop} ${r.coep} ${r.mime}');
				check("wasm instantiated (instantiateStreaming: application/wasm): add(2, 3) = 5", r.wasm == 5, Std.string(r.wasmError ?? r.wasm));
				#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
				// (Android's WebView gives no cross-origin isolation: no site isolation in it, the
				// headers it is sent notwithstanding; reported, not checked)
				Sys.println('webview: android: crossOriginIsolated ${r.isolated}, SharedArrayBuffer ${r.sab}, a shared memory ${r.shared} (not cross-origin isolated in Android\'s WebView)');
				#else
				// (WebKit isolates an HTTP origin only: a custom scheme's page is not, its headers notwithstanding)
				if (!content.local) Sys.println('webview: the scheme: crossOriginIsolated ${r.isolated}, SharedArrayBuffer ${r.sab} (WebKit isolates HTTP origins only)') else {
				check("crossOriginIsolated === true (COOP, COEP from its WebContent)", r.isolated == true);
				check("SharedArrayBuffer there", r.sab == true);
				check("a shared wasm memory", r.shared == true);
				}
				#end
				Sys.println("webview: user agent: " + r.ua);
				step = 1;
				post("pong " + r.wasm);
			case 1:
				check("the reply's round trip", e.text == "round trip: pong 5", e.text);
				step = 2;
				var b = Bytes.alloc(256 * 1024);
				for (i in 0...b.length)
					b.set(i, i * 7 & 255);
				postBytes(b);
			case 2:
				var ok = e.bytes != null && e.bytes.length == 256 * 1024;
				if (ok)
					for (i in 0...e.bytes.length)
						if (e.bytes.get(i) != ((e.bytes.length - 1 - i) * 7 & 255)) {
							ok = false;
							break;
						}
				check("bytes there and back (an ArrayBuffer to the page, base64 from it)", ok, e.bytes == null ? "none" : '${e.bytes.length}');
				step = 3;
				shoot(0);
			case 3:
				if (e.text == "again") shoot(shots);
			case 4:
				// (a pause for the screenshot, then the web build)
				if (e.text != "continue") return;
				if (webDir == null) {
					Sys.println("webview: no helder web build to load: skipped");
					end();
				} else {
					step = 5;
					load(content.url("todo/Todo.html"));
				}
			case 5:
				var r:Dynamic = e.json();
				if (r.kind != "web") return;
				check("the helder web build ran in the web view (its canvas " + r.canvas + ", its module's host)", r.running == true, haxe.Json.stringify(r.log));
				step = 6;
				later("end", 3000);
			case 6:
				if (e.text == "end") end();
			case _:
		}
	}

	static var shots = 0;

	// a still of the page: distinct colours in it (tried again a second later, three times at most)
	static function shoot(n:Int) {
		shots = n + 1;
		snapshot(shot -> {
			var distinct = [];
			if (shot != null) {
				var i = 0;
				while (i < shot.pixels.length && distinct.length < 8) {
					var c = shot.pixels.getInt32(i);
					if (distinct.indexOf(c) < 0) distinct.push(c);
					i += 4 * 97;
				}
			}
			if (distinct.length < 2 && shots < 3) {
				later("again", 1000);
				return;
			}
			check("a snapshot of the page", shot != null && shot.width > 0 && distinct.length >= 2,
				shot == null ? "none" : '${shot.width}x${shot.height}, ${distinct.length} colours: ' + [for (c in distinct) StringTools.hex(c, 8)].join(" "));
			step = 4;
			later("continue", 3000);
		});
	}

	// the page posts text after ms (the shell's loop has no timers of its own)
	static function later(text:String, ms:Int)
		evalJs('setTimeout(function(){helder.post("' + text + '");},' + ms + ');');

	// (the web build: its canvas laid out, its module's host made and nothing uncaught,
	// page.html's window.hxmcDev; polled in the page, for 60 s at most)
	static function probeWeb()
		evalJs('(function(){var t=Date.now(),f=function(){var c=document.querySelector("canvas"),d=window.hxmcDev;'
			+ 'var ok=!!(c&&c.width>0&&d&&d.instance&&d.instance.host)&&!d.log.some(function(l){return l.indexOf("Uncaught")>=0;});'
			+ 'if(ok||Date.now()-t>60000)helder.post({kind:"web",canvas:c?c.width+"x"+c.height:"none",running:ok,log:d?d.log.slice(-3):[]});'
			+ 'else setTimeout(f,500);};f();})();');

}
