package helder.ui.platform;

import haxe.io.Bytes;
import helder.ui.platform.PlatformWebView;

// An app that is a web view on the whole screen, a thin native shell
// around a page (helder studio's on phones: the web studio inside the
// system's web view, the only place a phone runs wasm compiled at run
// time): iOS's WKWebView as its window's root view (no drawn surface),
// Android's WebView as the activity's content (org.hxmc.Activity); on the
// desktop a window whose drawn tree is a WebView alone. run never returns:
// it is the app's loop, handing the page's events to onEvent.
//
//   WebShell.run({content: WebContent.bundle("web/"), src: "index.html"}, (shell, e) -> switch e.kind {
//     case Message: shell.post("pong " + e.text);
//     case _:
//   });
class WebShell implements WebViewListener {
	public final options:WebShellOptions;
	// the web view (null on the desktop until its window drew)
	public var view(default, null):Null<PlatformWebView> = null;
	final onEvent:(WebShell, WebViewEvent) -> Void;
	var node:Null<WebView> = null;

	function new(options:WebShellOptions, onEvent:(WebShell, WebViewEvent) -> Void) {
		this.options = options;
		this.onEvent = onEvent;
	}

	public static function run(options:WebShellOptions, ?onEvent:(WebShell, WebViewEvent) -> Void) {
		var s = new WebShell(options, onEvent ?? (_, _) -> {});
		s.start();
	}

	// a src's URL (a path: its content's)
	public function resolve(src:String):String
		return src.indexOf(":") > 0 || options.content == null ? src : options.content.url(src);

	public function load(src:String)
		if (node != null) node.src = src else if (view != null) view.load(resolve(src));

	public function post(text:String)
		eval(WebBridge.receive("s", text));

	public function postJson(value:Dynamic)
		eval(WebBridge.receive("j", haxe.Json.stringify(value)));

	public function postBytes(b:Bytes)
		eval(options.content != null ? WebBridge.fetch(options.content.keep(b)) : WebBridge.receive("b", haxe.crypto.Base64.encode(b)));

	public function eval(js:String)
		if (node != null) node.eval(js) else if (view != null) view.eval(js);

	public function snapshot(done:Null<WebSnapshot>->Void)
		if (node != null) node.snapshot(done) else if (view != null) view.snapshot(done) else done(null);

	public function webViewEvent(e:WebViewEvent)
		onEvent(this, e);

	function first() {
		var v = view;
		if (v == null) return;
		if (options.html != null) v.loadHtml(options.html) else if (options.src != null) v.load(resolve(options.src));
	}

	function start() {
		var o:WebViewOptions = {
			content: options.content,
			inspectable: options.inspectable,
			zoom: options.zoom,
			transparent: options.transparent,
			backGesture: options.backGesture
		};
		#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		var v = AppleWebView.fullScreen(o, () -> {});
		view = v;
		v.listen(this);
		first();
		var mode = helder.os.objc.ObjC.str("kCFRunLoopDefaultMode");
		while (true) {
			v.poll();
			helder.os.uikit.UIKitApp.CF.CFRunLoopRunInMode(mode, 1, true);
		}
		#elseif (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		// (the APK's activity draws views: org.hxmc.Activity)
		new AndroidWebView.AndroidContent();
		var v = new AndroidWebView(o, () -> 1.0, () -> {}, true);
		view = v;
		v.listen(this);
		first();
		while (true) {
			helder.os.android.MainThread.wait(-1);
			v.poll();
		}
		#else
		var w = new helder.ui.draw.UiWindow(options.title ?? "", options.width ?? 1024, options.height ?? 768);
		var n = new WebView();
		n.content = options.content;
		n.inspectable = options.inspectable;
		n.zoom = options.zoom == true;
		n.transparent = options.transparent == true;
		n.style.width = helder.ui.Dim.parse("100%");
		n.style.height = helder.ui.Dim.parse("100%");
		n.onMessage = n.onNavigate = n.onUrlChange = n.onLoad = n.onTitle = n.onProgress = n.onLoadError = n.onConsole = n.onCrash = e -> onEvent(this, e);
		if (options.html != null) n.html = options.html else if (options.src != null) n.src = options.src;
		node = n;
		w.root.insert(n, w.root.children.length);
		helder.ui.draw.UiWindow.run();
		#end
	}
}

typedef WebShellOptions = WebViewOptions & {
	// the first page: a URL or a path of the content's origin, or HTML
	?src:String,
	?html:String,
	// the desktop's window
	?title:String,
	?width:Int,
	?height:Int
}
