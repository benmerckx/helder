package helder.ui.platform;

import haxe.io.Bytes;
import helder.ui.platform.PlatformWebView;

// A system web view in a drawn tree, `<webview>` in markup: placed where
// it is laid out, over the window's drawn surface (iOS and macOS: a
// WKWebView, AppleWebView; Android: android.webkit.WebView, AndroidWebView;
// elsewhere, for now, nothing: its box alone is drawn). Made once it is in
// a window that has one, let go when it leaves it.
//
//   <webview src="index.html" content={WebContent.bundle("web/")} width="100%" flex-grow={1}
//     onMessage={e -> reply(e.text)} onTitle={e -> title(e.text)}/>
//
// src: a URL, or a path of its content's origin (WebContent.url); html: a
// page as a string (at the content's origin). content, inspectable, zoom,
// transparent and backGesture are read when the native view is made.
// Messages: post(text), postJson(value), postBytes(bytes) to the page's
// helder.onmessage; the page's helder.post(...) to onMessage (WebBridge).
// Its handlers run on the program's thread before the next layout.
class WebView extends Node implements WebViewListener {
	public var src(default, set):Null<String> = null;
	public var html(default, set):Null<String> = null;
	// its own origin's files (a scheme handler: WebContent)
	public var content:Null<WebContent> = null;
	// the web inspector (null: in debug builds)
	public var inspectable:Null<Bool> = null;
	public var zoom = false;
	public var transparent = false;
	public var backGesture = true;

	// what it shows: its URL, title, the load's progress (0 to 1), whether it is loading
	public var url(default, null) = "";
	public var title(default, null) = "";
	public var progress(default, null) = 0.0;
	public var loading(default, null) = false;

	public var onMessage:Null<WebViewEvent->Void> = null;
	public var onNavigate:Null<WebViewEvent->Void> = null;
	public var onUrlChange:Null<WebViewEvent->Void> = null;
	public var onLoad:Null<WebViewEvent->Void> = null;
	public var onTitle:Null<WebViewEvent->Void> = null;
	public var onProgress:Null<WebViewEvent->Void> = null;
	public var onLoadError:Null<WebViewEvent->Void> = null;
	public var onConsole:Null<WebViewEvent->Void> = null;
	public var onCrash:Null<WebViewEvent->Void> = null;

	// the native view, once made
	public var native(default, null):Null<PlatformWebView> = null;

	// (what waits for it: a load, calls)
	var pending:Array<PlatformWebView->Void> = [];
	var loaded = false;
	var shown = false;

	public function new()
		super("webview");

	function set_src(v:Null<String>):Null<String> {
		src = v;
		@:bypassAccessor html = null;
		loaded = false;
		if (native != null) loadNow();
		return v;
	}

	function set_html(v:Null<String>):Null<String> {
		html = v;
		loaded = false;
		if (native != null) loadNow();
		return v;
	}

	// a src's URL: as it is when it has a scheme, else its content's
	public function resolve(s:String):String
		return s.indexOf(":") > 0 || content == null ? s : content.url(s);

	function loadNow() {
		if (loaded || native == null) return;
		if (html != null) native.loadHtml(html);
		else if (src != null) native.load(resolve(src));
		else return;
		loaded = true;
		loading = true;
	}

	function call(f:PlatformWebView->Void)
		if (native != null) f(native) else pending.push(f);

	// a message to the page (its helder.onmessage: e.data the string)
	public function post(text:String)
		call(n -> n.eval(WebBridge.receive("s", text)));

	// a value as JSON (e.data the value)
	public function postJson(value:Dynamic)
		call(n -> n.eval(WebBridge.receive("j", haxe.Json.stringify(value))));

	// bytes (e.data an ArrayBuffer): fetched by the page from its content's
	// origin where it has one, else as base64
	public function postBytes(b:Bytes)
		call(n -> n.eval(content != null ? WebBridge.fetch(content.keep(b)) : WebBridge.receive("b", haxe.crypto.Base64.encode(b))));

	// JavaScript run in the page
	public function eval(js:String)
		call(n -> n.eval(js));

	public function goBack()
		call(n -> n.goBack());

	public function goForward()
		call(n -> n.goForward());

	public function reload()
		call(n -> n.reload());

	public function stop()
		call(n -> n.stop());

	// a still of what it shows (done(null): none, or no native view)
	public function snapshot(done:Null<WebSnapshot>->Void)
		if (native != null) native.snapshot(done) else done(null);

	override function attach(u:Null<Ui>) {
		if (ui != null && ui != u) {
			@:privateAccess ui.natives.remove(this);
			drop();
		}
		super.attach(u);
		if (u != null && @:privateAccess u.natives.indexOf(this) < 0) @:privateAccess u.natives.push(this);
	}

	function drop() {
		if (native == null) return;
		native.dispose();
		native = null;
		loaded = false;
	}

	// (after each layout: made, placed, its events handed to the handlers)
	override function syncNative() {
		if (ui == null) return;
		if (native == null) {
			native = make(ui, {
				content: content,
				inspectable: inspectable,
				zoom: zoom,
				transparent: transparent,
				backGesture: backGesture
			}, ui.requestFrame);
			if (native == null) return;
			native.listen(this);
			shown = false;
			loadNow();
			var calls = pending;
			pending = [];
			for (f in calls)
				f(native);
		}
		var be = style.borderEdges;
		var w = width - be.left - be.right, h = height - be.top - be.bottom;
		var b = windowBounds();
		var on = visible() && w > 0 && h > 0;
		native.place(b.x + be.left, b.y + be.top, w, h, on);
		native.poll();
	}

	public function webViewEvent(e:WebViewEvent) {
		var h:Null<WebViewEvent->Void> = switch e.kind {
			case Message: onMessage;
			case Navigate:
				loading = true;
				url = e.url;
				onNavigate;
			case UrlChange:
				url = e.url;
				onUrlChange;
			case Load:
				loading = false;
				progress = 1;
				url = e.url;
				onLoad;
			case Title:
				title = e.text;
				onTitle;
			case Progress:
				progress = e.progress;
				onProgress;
			case LoadError:
				loading = false;
				onLoadError;
			case Console: onConsole;
			case Crash: onCrash;
		}
		if (h != null) h(e);
		if (ui != null) ui.requestFrame();
	}

	// the platform's web view for a window's ui (null: none here)
	public static function make(ui:Ui, o:WebViewOptions, queued:Void->Void):Null<PlatformWebView> {
		#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		return new AndroidWebView(o, () -> ui.scale, queued);
		#elseif (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64" || hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64")
		// (the window's view: its surface's)
		for (w in @:privateAccess helder.ui.draw.UiWindow.open)
			if (w.ui == ui) return new AppleWebView(w.window.surface.handle, o, queued);
		return null;
		#else
		return null;
		#end
	}
}
