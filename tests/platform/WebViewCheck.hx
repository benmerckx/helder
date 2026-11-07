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
	}

	var node:Null<WebView> = null;

	public function new() {}

	public function view():View
		return <view tag="app" width="100%" height="100%" background="#fef3c7">
			<view tag="header" padding={16} padding-top="env(safe-area-inset-top)" background="#f59e0b">
				<text font-size={20}>helder: a web view below</text>
			</view>
			<webview tag="web" ref={n -> attached(cast n)} content={content} src="index.html" inspectable flex-grow={1} margin={12}
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
				check("crossOriginIsolated === true (COOP, COEP from the scheme handler)", r.isolated == true);
				check("SharedArrayBuffer there", r.sab == true);
				check("wasm instantiated (instantiateStreaming: application/wasm): add(2, 3) = 5", r.wasm == 5, Std.string(r.wasmError ?? r.wasm));
				check("a shared wasm memory", r.shared == true);
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
				snapshot(shot -> {
					var distinct = new Map<Int, Bool>(), n = 0;
					if (shot != null) {
						var i = 0;
						while (i < shot.pixels.length && n < 8) {
							var c = shot.pixels.getInt32(i);
							if (!distinct.exists(c)) {
								distinct.set(c, true);
								n++;
							}
							i += 4 * 97;
						}
					}
					check("a snapshot of the page", shot != null && shot.width > 0 && n >= 2, shot == null ? "none" : '${shot.width}x${shot.height}, $n colours');
					step = 4;
					if (webDir == null) {
						Sys.println("webview: no helder web build to load: skipped");
						end();
					} else {
						step = 5;
						load(content.url("todo/Todo.html"));
					}
				});
			case 5:
				var r:Dynamic = e.json();
				if (r.kind != "web") return;
				check("the helder web build ran in the web view (its canvas " + r.canvas + ", its module's host)", r.running == true, haxe.Json.stringify(r.log));
				end();
			case _:
		}
	}

	// (the web build: its canvas laid out and its module's host made,
	// page.html's window.hxmcDev; polled in the page, for 60 s at most)
	static function probeWeb()
		evalJs('(function(){var t=Date.now(),f=function(){var c=document.querySelector("canvas"),d=window.hxmcDev;'
			+ 'var ok=!!(c&&c.width>0&&d&&d.instance&&d.instance.host);'
			+ 'if(ok||Date.now()-t>60000)helder.post({kind:"web",canvas:c?c.width+"x"+c.height:"none",running:ok,log:d?d.log.slice(-3):[]});'
			+ 'else setTimeout(f,500);};f();})();');

}
