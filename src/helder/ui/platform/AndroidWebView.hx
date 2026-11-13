package helder.ui.platform;

import helder.os.android.*;
import helder.os.android.Jni.JniEnv;
import helder.os.android.Native;
import helder.ui.platform.PlatformWebView;
import hxmc.NativeThread;
import hxmc.unsafe.*;

// An android.webkit.WebView, made and driven on the main thread
// (MainThread: the program's thread posts to it). Over a drawn window it
// is a panel window of the activity's (WindowManager.addView, type
// TYPE_APPLICATION_PANEL: NativeActivity's own window draws no views, its
// surface the program's), placed in pixels (the layout's times the
// window's scale) where its node is laid out, not touch-modal (touches
// outside it go to the window below), focusable (the input method for the
// page's fields); for WebShell it is the activity's content (org.hxmc.Activity).
// classes.dex's WebClient, WebChrome and WebBridge (helder.pack.android.Glue)
// call back:
// - shouldInterceptRequest, on the web view's own thread: a request of its
//   WebContent's origin (https://appassets.androidplatform.net/, as
//   WebViewAssetLoader's) answered with a WebResourceResponse of the
//   content's status, headers (COOP and COEP) and bytes, an HTML page with
//   the bridge's script put first in its head; others go to the network;
// - the bridge's post(String) (@JavascriptInterface, on its JavaBridge
//   thread): a message (WebBridge's script, also evaluated at each page's
//   start for pages from elsewhere);
// - the client's and chrome client's callbacks, on the main thread: a
//   page started, finished, its history updated, failed, its progress,
//   title, console lines; the renderer gone (handled: the view stays).
// Those foreign threads become Haxe threads (NativeThread.attach) and use
// the JNIEnv they were given. The events wait, under a lock, for the
// program's thread: its pump (AndroidWindow.pumped) asks for a frame, and
// poll hands them on. The Back key goes back in the page's history while
// it can (the panel has the focus). The inspector:
// WebView.setWebContentsDebuggingEnabled where asked.
@:hxmc.android
@:hxmc.unsafe(gc)
class AndroidWebView implements PlatformWebView {
	static final lock = new sys.thread.Mutex();
	static final byId = new Map<Int, AndroidWebView>();
	static var started = false;
	static var m:Map<String, Ptr>;
	static var cls:Map<String, Ptr>;

	final options:WebViewOptions;
	final content:Null<WebContent>;
	final scale:Void->Float;
	final queued:Void->Void;
	final full:Bool;
	final bridgeJs:String;
	var id = 0;
	var listener:Null<WebViewListener> = null;
	final events:Array<WebViewEvent> = [];
	final done:Array<Void->Void> = [];
	var disposed = false;
	// (the main thread's: the view, the panel's layout params, global references)
	var web = Ptr.nil();
	var params = Ptr.nil();
	var added = false;
	var lastX = -1;
	var lastY = -1;
	var lastW = -1;
	var lastH = -1;
	var lastShown = false;
	var pumped:Null<Void->Void> = null;

	// a web view (over the window, or the activity's content when full);
	// scale: the window's pixels per layout pixel; queued: an event waits for poll
	public function new(options:WebViewOptions, scale:Void->Float, queued:Void->Void, full = false) {
		this.options = options;
		this.content = options.content;
		this.scale = scale;
		this.queued = queued;
		this.full = full;
		bridgeJs = WebBridge.script("android", "function(s){__helderBridge.post(s);}", false);
		MainThread.run(make);
		// (the program's thread, at each pump: events waiting, a frame asked for)
		pumped = () -> {
			lock.acquire();
			var any = events.length > 0 || done.length > 0;
			lock.release();
			if (any) this.queued();
		};
		AndroidWindow.pumped.push(pumped);
	}

	// (the main thread)
	function make() {
		if (!started) init();
		var act = Jni.activity;
		var v = Jni.newObject(cls["WebView"], m["WebView.<init>"], act.toI64());
		web = Jni.global(v);
		Jni.deleteLocal(v);
		id = Glue.handle(event);
		lock.acquire();
		byId.set(id, this);
		lock.release();
		var s = Jni.obj(web, m["getSettings"]);
		Jni.call(s, m["setJavaScriptEnabled"], 1);
		Jni.call(s, m["setDomStorageEnabled"], 1);
		Jni.call(s, m["setMediaPlaybackRequiresUserGesture"], 0);
		Jni.call(s, m["setAllowFileAccess"], 0);
		var zoom = options.zoom == true;
		Jni.call(s, m["setSupportZoom"], Jni.z(zoom));
		Jni.call(s, m["setBuiltInZoomControls"], Jni.z(zoom));
		Jni.call(s, m["setDisplayZoomControls"], 0);
		Jni.deleteLocal(s);
		var inspect = options.inspectable ?? #if (hxmc.dev || helder.inspectable) true #else false #end;
		if (inspect) JniEnv.CallStaticVoidMethodA(Jni.env, cls["WebView"], m["setWebContentsDebuggingEnabled"], args1(1));
		for (k in ["WebClient", "WebChrome", "WebBridge"]) {
			var o = Jni.newObject(cls[k], m[k + ".<init>"], id);
			Jni.call(web, m[k == "WebClient" ? "setWebViewClient" : k == "WebChrome" ? "setWebChromeClient" : "addJavascriptInterface"], o.toI64(),
				k == "WebBridge" ? Jni.string("__helderBridge").toI64() : 0);
			Jni.deleteLocal(o);
		}
		if (options.transparent == true) Jni.call(web, m["setBackgroundColor"], 0);
		// (the Back key: back in its history while it can)
		var keys = Glue.listener((kind, o, a, b) -> {
			if (kind != Glue.KEY || a != 4 || options.backGesture == false) return 0; // KEYCODE_BACK
			if (b == 0) {
				if (!Jni.bool(web, m["canGoBack"])) return 0;
				Jni.call(web, m["goBack"]);
			}
			return 1;
		});
		Jni.call(web, m["setOnKeyListener"], keys.obj.toI64());
		Jni.call(web, m["setFocusable"], 1);
		Jni.call(web, m["setFocusableInTouchMode"], 1);
		// (WebShell's: it makes an AndroidContent, so the APK's activity draws views)
		if (full) {
			Glue.setContentView(web);
			// (the theme's action bar gone: the page is the app)
			var bar = Jni.obj(Jni.activity, Jni.method(Jni.cls("android.app.Activity"), "getActionBar", "()Landroid/app/ActionBar;"));
			if (!bar.isNull()) Jni.call(bar, Jni.method(Jni.cls("android.app.ActionBar"), "hide", "()V"));
		}
	}

	// the classes and methods, once (the main thread)
	static function init() {
		started = true;
		var view = Jni.cls("android.view.View"), wv = Jni.cls("android.webkit.WebView"), ws = Jni.cls("android.webkit.WebSettings");
		var lp = Jni.cls("android.view.WindowManager$LayoutParams"), wm = Jni.cls("android.view.WindowManager"), vm = Jni.cls("android.view.ViewManager");
		cls = [
			"WebView" => wv,
			"LayoutParams" => lp,
			"Bitmap" => Jni.cls("android.graphics.Bitmap"),
			"Canvas" => Jni.cls("android.graphics.Canvas"),
			"WebResourceResponse" => Jni.cls("android.webkit.WebResourceResponse"),
			"ByteArrayInputStream" => Jni.cls("java.io.ByteArrayInputStream"),
			"HashMap" => Jni.cls("java.util.HashMap"),
		];
		var natives = [{name: "intercept", sig: "(ILandroid/webkit/WebResourceRequest;)Landroid/webkit/WebResourceResponse;", fn: Callback.addr(interceptEntry)}];
		cls["WebClient"] = Glue.adopt("org.hxmc.WebClient", natives);
		cls["WebChrome"] = Glue.adopt("org.hxmc.WebChrome");
		cls["WebBridge"] = Jni.cls("org.hxmc.WebBridge");
		Jni.registerNatives(cls["WebBridge"], [{name: "message", sig: "(ILjava/lang/String;)V", fn: Callback.addr(messageEntry)}]);
		var req = Jni.cls("android.webkit.WebResourceRequest"), uri = Jni.cls("android.net.Uri");
		var bitmap = cls["Bitmap"];
		m = [
			"WebView.<init>" => Jni.method(wv, "<init>", "(Landroid/content/Context;)V"),
			"WebClient.<init>" => Jni.method(cls["WebClient"], "<init>", "(I)V"),
			"WebChrome.<init>" => Jni.method(cls["WebChrome"], "<init>", "(I)V"),
			"WebBridge.<init>" => Jni.method(cls["WebBridge"], "<init>", "(I)V"),
			"getSettings" => Jni.method(wv, "getSettings", "()Landroid/webkit/WebSettings;"),
			"setJavaScriptEnabled" => Jni.method(ws, "setJavaScriptEnabled", "(Z)V"),
			"setDomStorageEnabled" => Jni.method(ws, "setDomStorageEnabled", "(Z)V"),
			"setMediaPlaybackRequiresUserGesture" => Jni.method(ws, "setMediaPlaybackRequiresUserGesture", "(Z)V"),
			"setAllowFileAccess" => Jni.method(ws, "setAllowFileAccess", "(Z)V"),
			"setSupportZoom" => Jni.method(ws, "setSupportZoom", "(Z)V"),
			"setBuiltInZoomControls" => Jni.method(ws, "setBuiltInZoomControls", "(Z)V"),
			"setDisplayZoomControls" => Jni.method(ws, "setDisplayZoomControls", "(Z)V"),
			"setWebContentsDebuggingEnabled" => Jni.staticMethod(wv, "setWebContentsDebuggingEnabled", "(Z)V"),
			"setWebViewClient" => Jni.method(wv, "setWebViewClient", "(Landroid/webkit/WebViewClient;)V"),
			"setWebChromeClient" => Jni.method(wv, "setWebChromeClient", "(Landroid/webkit/WebChromeClient;)V"),
			"addJavascriptInterface" => Jni.method(wv, "addJavascriptInterface", "(Ljava/lang/Object;Ljava/lang/String;)V"),
			"loadUrl" => Jni.method(wv, "loadUrl", "(Ljava/lang/String;)V"),
			"loadDataWithBaseURL" => Jni.method(wv, "loadDataWithBaseURL", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V"),
			"evaluateJavascript" => Jni.method(wv, "evaluateJavascript", "(Ljava/lang/String;Landroid/webkit/ValueCallback;)V"),
			"goBack" => Jni.method(wv, "goBack", "()V"),
			"goForward" => Jni.method(wv, "goForward", "()V"),
			"canGoBack" => Jni.method(wv, "canGoBack", "()Z"),
			"reload" => Jni.method(wv, "reload", "()V"),
			"stopLoading" => Jni.method(wv, "stopLoading", "()V"),
			"destroy" => Jni.method(wv, "destroy", "()V"),
			"getUrl" => Jni.method(wv, "getUrl", "()Ljava/lang/String;"),
			"setBackgroundColor" => Jni.method(view, "setBackgroundColor", "(I)V"),
			"setOnKeyListener" => Jni.method(view, "setOnKeyListener", "(Landroid/view/View$OnKeyListener;)V"),
			"setFocusable" => Jni.method(view, "setFocusable", "(Z)V"),
			"setFocusableInTouchMode" => Jni.method(view, "setFocusableInTouchMode", "(Z)V"),
			"setVisibility" => Jni.method(view, "setVisibility", "(I)V"),
			"getWidth" => Jni.method(view, "getWidth", "()I"),
			"getHeight" => Jni.method(view, "getHeight", "()I"),
			"draw" => Jni.method(view, "draw", "(Landroid/graphics/Canvas;)V"),
"getWindow" => Jni.method(Jni.cls("android.app.Activity"), "getWindow", "()Landroid/view/Window;"),
			"getDecorView" => Jni.method(Jni.cls("android.view.Window"), "getDecorView", "()Landroid/view/View;"),
			"getLocationOnScreen" => Jni.method(view, "getLocationOnScreen", "([I)V"),
			"getWindowManager" => Jni.method(Jni.cls("android.app.Activity"), "getWindowManager", "()Landroid/view/WindowManager;"),
			"addView" => Jni.method(vm, "addView", "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V"),
			"updateViewLayout" => Jni.method(vm, "updateViewLayout", "(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V"),
			"removeView" => Jni.method(vm, "removeView", "(Landroid/view/View;)V"),
			"LayoutParams.<init>" => Jni.method(lp, "<init>", "(IIIII)V"),
			"lp.x" => Jni.field(lp, "x", "I"),
			"lp.y" => Jni.field(lp, "y", "I"),
			"lp.width" => Jni.field(lp, "width", "I"),
			"lp.height" => Jni.field(lp, "height", "I"),
			"lp.gravity" => Jni.field(lp, "gravity", "I"),
			"lp.flags" => Jni.field(lp, "flags", "I"),
			"lp.softInputMode" => Jni.field(lp, "softInputMode", "I"),
			"lp.layoutInDisplayCutoutMode" => Jni.field(lp, "layoutInDisplayCutoutMode", "I"),
			"getUrlOf" => Jni.method(req, "getUrl", "()Landroid/net/Uri;"),
			"isForMainFrame" => Jni.method(req, "isForMainFrame", "()Z"),
			"Uri.toString" => Jni.method(uri, "toString", "()Ljava/lang/String;"),
			"getDescription" => Jni.method(Jni.cls("android.webkit.WebResourceError"), "getDescription", "()Ljava/lang/CharSequence;"),
			"console.message" => Jni.method(Jni.cls("android.webkit.ConsoleMessage"), "message", "()Ljava/lang/String;"),
			"console.lineNumber" => Jni.method(Jni.cls("android.webkit.ConsoleMessage"), "lineNumber", "()I"),
			"console.sourceId" => Jni.method(Jni.cls("android.webkit.ConsoleMessage"), "sourceId", "()Ljava/lang/String;"),
			"Response.<init>" => Jni.method(cls["WebResourceResponse"], "<init>",
				"(Ljava/lang/String;Ljava/lang/String;ILjava/lang/String;Ljava/util/Map;Ljava/io/InputStream;)V"),
			"Stream.<init>" => Jni.method(cls["ByteArrayInputStream"], "<init>", "([B)V"),
			"HashMap.<init>" => Jni.method(cls["HashMap"], "<init>", "()V"),
			"HashMap.put" => Jni.method(cls["HashMap"], "put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"),
			"createBitmap" => Jni.staticMethod(bitmap, "createBitmap", "(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;"),
			"copyPixelsToBuffer" => Jni.method(bitmap, "copyPixelsToBuffer", "(Ljava/nio/Buffer;)V"),
			"recycle" => Jni.method(bitmap, "recycle", "()V"),
			"Canvas.<init>" => Jni.method(cls["Canvas"], "<init>", "(Landroid/graphics/Bitmap;)V"),
		];
	}

	static var argsBuf = Ptr.nil();

	// (the main thread's) one argument of a static call
	static function args1(a:Int64):Ptr {
		if (argsBuf.isNull()) argsBuf = LibC.malloc(64);
		Mem.setI64(argsBuf, 0, a);
		return argsBuf;
	}

	// ---- the main thread's callbacks (Glue's, org.hxmc.WebClient's and WebChrome's)

	function event(kind:Int, o:Ptr, a:Int, b:Int):Int {
		if (disposed) return 0;
		switch kind {
			case Glue.WEB_STARTED:
				var e = new WebViewEvent(Navigate);
				e.url = Jni.fromString(o);
				push(e);
				// (pages from elsewhere: the bridge as soon as it can be; its own pages have it first)
				if (content == null || !content.owns(e.url)) evaluate(bridgeJs);
			case Glue.WEB_FINISHED:
				var e = new WebViewEvent(Load);
				e.url = Jni.fromString(o);
				if (content == null || !content.owns(e.url)) evaluate(bridgeJs);
				push(e);
			case Glue.WEB_NAVIGATED:
				var e = new WebViewEvent(UrlChange);
				e.url = Jni.fromString(o);
				push(e);
			case Glue.WEB_PROGRESS:
				var e = new WebViewEvent(Progress);
				e.progress = a / 100;
				push(e);
			case Glue.WEB_TITLE:
				var e = new WebViewEvent(Title);
				e.text = Jni.fromString(o);
				push(e);
			case Glue.WEB_ERROR:
				var e = new WebViewEvent(LoadError);
				var d = Jni.obj(o, m["getDescription"]);
				e.text = Jni.text(d);
				Jni.deleteLocal(d);
				e.code = a;
				var u = Jni.obj(web, m["getUrl"]);
				e.url = Jni.fromString(u);
				Jni.deleteLocal(u);
				// (a subresource's failure: a console line, not the page's error)
				if (b == 0) {
					var c = new WebViewEvent(Console);
					c.text = "error: a request failed: " + e.text;
					push(c);
				} else push(e);
			case Glue.WEB_CONSOLE:
				var e = new WebViewEvent(Console);
				var msg = Jni.obj(o, m["console.message"]), src = Jni.obj(o, m["console.sourceId"]);
				e.text = Jni.fromString(msg) + " (" + Jni.fromString(src) + ":" + Jni.int(o, m["console.lineNumber"]) + ")";
				Jni.deleteLocal(msg);
				Jni.deleteLocal(src);
				push(e);
				return 1;
			case Glue.WEB_GONE: // (the renderer went; kept, a Crash)
				push(new WebViewEvent(Crash));
				return 1;
			case _:
		}
		return 0;
	}

	function push(e:WebViewEvent) {
		lock.acquire();
		events.push(e);
		lock.release();
		MainThread.wake();
	}

	// (the main thread) JavaScript into the page
	function evaluate(js:String) {
		if (web.isNull()) return;
		var s = Jni.string(js);
		Jni.call(web, m["evaluateJavascript"], s.toI64(), 0);
		Jni.deleteLocal(s);
	}

	// ---- foreign threads: the web view's requests, the bridge's messages
	// (their JNIEnv, Haxe threads once attached)

	@:hxmc.callback @:hxmc.noGc static function interceptEntry(env:Ptr, c:Ptr, id:Int, request:Ptr):Ptr {
		NativeThread.attach();
		return JniFast.call3(Callback.addr(intercept), env, Ptr.ofI64(id), request, Ptr.nil());
	}

	@:hxmc.callback @:hxmc.noGc static function messageEntry(env:Ptr, c:Ptr, id:Int, text:Ptr):Void {
		NativeThread.attach();
		JniFast.call3(Callback.addr(bridgeMessage), env, Ptr.ofI64(id), text, Ptr.nil());
	}

	@:hxmc.callback static function bridgeMessage(env:Ptr, idp:Ptr, s:Ptr, unused:Ptr):Ptr {
		var v = find(idp.toI64().toInt());
		if (v != null) v.push(WebViewEvent.message(string(env, s)));
		return Ptr.nil();
	}

	static function find(id:Int):Null<AndroidWebView> {
		lock.acquire();
		var v = byId.get(id);
		lock.release();
		return v == null || v.disposed ? null : v;
	}

	@:hxmc.callback static function intercept(env:Ptr, idp:Ptr, request:Ptr, unused:Ptr):Ptr {
		var v = find(idp.toI64().toInt());
		if (v == null || v.content == null) return Ptr.nil();
		var a = LibC.malloc(64);
		var uri = JniEnv.CallObjectMethodA(env, request, m["getUrlOf"], a);
		var us = JniEnv.CallObjectMethodA(env, uri, m["Uri.toString"], a);
		var url = string(env, us);
		JniEnv.DeleteLocalRef(env, us);
		JniEnv.DeleteLocalRef(env, uri);
		if (!v.content.owns(url)) {
			LibC.free(a);
			return Ptr.nil();
		}
		var r = try v.content.respond(url) catch (e:Dynamic) WebResponse.error(500, "text/plain", Std.string(e));
		var mime = r.mime, semi = mime.indexOf(";");
		var encoding:Null<String> = null;
		if (semi >= 0) {
			var p = mime.substr(semi + 1), at = p.indexOf("charset=");
			if (at >= 0) encoding = StringTools.trim(p.substr(at + 8));
			mime = StringTools.trim(mime.substr(0, semi));
		}
		var body = r.body;
		if (mime == "text/html") body = haxe.io.Bytes.ofString(WebBridge.inject(body.toString(), v.bridgeJs));
		var headers = JniEnv.NewObjectA(env, cls["HashMap"], m["HashMap.<init>"], a);
		for (k => val in r.headers) {
			var jk = newString(env, k), jv = newString(env, val);
			Mem.setI64(a, 0, jk.toI64());
			Mem.setI64(a, 8, jv.toI64());
			var old = JniEnv.CallObjectMethodA(env, headers, m["HashMap.put"], a);
			if (!old.isNull()) JniEnv.DeleteLocalRef(env, old);
			JniEnv.DeleteLocalRef(env, jk);
			JniEnv.DeleteLocalRef(env, jv);
		}
		var n = body.length, bytes = JniEnv.NewByteArray(env, n);
		if (n > 0) {
			var copy = LibC.malloc((n : Int64));
			LibC.memcpy(copy, BytesPtr.of(body, 0, n), (n : Int64));
			JniEnv.SetByteArrayRegion(env, bytes, 0, n, copy);
			LibC.free(copy);
		}
		Mem.setI64(a, 0, bytes.toI64());
		var stream = JniEnv.NewObjectA(env, cls["ByteArrayInputStream"], m["Stream.<init>"], a);
		var jm = newString(env, mime), je = encoding == null ? Ptr.nil() : newString(env, encoding), jr = newString(env, WebResponse.reason(r.status));
		Mem.setI64(a, 0, jm.toI64());
		Mem.setI64(a, 8, je.toI64());
		Mem.setI64(a, 16, r.status);
		Mem.setI64(a, 24, jr.toI64());
		Mem.setI64(a, 32, headers.toI64());
		Mem.setI64(a, 40, stream.toI64());
		var response = JniEnv.NewObjectA(env, cls["WebResourceResponse"], m["Response.<init>"], a);
		LibC.free(a);
		if (JniEnv.ExceptionCheck(env) & 0xff != 0) {
			JniEnv.ExceptionDescribe(env);
			JniEnv.ExceptionClear(env);
			return Ptr.nil();
		}
		return response;
	}

	// a java.lang.String's text, through env
	static function string(env:Ptr, js:Ptr):String {
		if (js.isNull()) return "";
		var n = JniEnv.GetStringLength(env, js);
		var buf = LibC.malloc((2 * n + 2 : Int64));
		JniEnv.GetStringRegion(env, js, 0, n, buf);
		var s = hxmc.rt.Str.make2(n);
		LibC.memcpy(hxmc.rt.Str.unitsAddr(s), buf, (2 * n : Int64));
		LibC.free(buf);
		return s;
	}

	static function newString(env:Ptr, s:String):Ptr
		return Arena.scopedValue(a -> JniEnv.NewString(env, a.wstring(s), s.length));

	// ---- PlatformWebView (the program's thread)

	public function listen(l:WebViewListener)
		listener = l;

	public function place(x:Float, y:Float, width:Float, height:Float, shown:Bool) {
		if (disposed || full) return;
		var s = scale();
		var px = Math.round(x * s), py = Math.round(y * s), pw = Std.int(Math.max(1, Math.round(width * s))), ph = Std.int(Math.max(1, Math.round(height * s)));
		if (px == lastX && py == lastY && pw == lastW && ph == lastH && shown == lastShown) return;
		lastX = px;
		lastY = py;
		lastW = pw;
		lastH = ph;
		lastShown = shown;
		MainThread.post(() -> {
			if (disposed) return;
			if (params.isNull()) {
				// (TYPE_APPLICATION_PANEL; FLAG_NOT_TOUCH_MODAL | FLAG_LAYOUT_NO_LIMITS |
				// FLAG_LAYOUT_IN_SCREEN | FLAG_HARDWARE_ACCELERATED; PixelFormat.TRANSLUCENT)
				var a = args5(Ptr.ofI64(pw), Ptr.ofI64(ph), Ptr.ofI64(1000), Ptr.ofI64(0x20 | 0x200 | 0x100 | 0x01000000), Ptr.ofI64(-3));
				var p = JniEnv.NewObjectA(Jni.env, cls["LayoutParams"], m["LayoutParams.<init>"], a);
				Jni.check();
				params = Jni.global(p);
				Jni.deleteLocal(p);
				JniEnv.SetIntField(Jni.env, params, m["lp.gravity"], 0x33); // TOP | LEFT
				JniEnv.SetIntField(Jni.env, params, m["lp.softInputMode"], 0x10); // SOFT_INPUT_ADJUST_RESIZE
				JniEnv.SetIntField(Jni.env, params, m["lp.layoutInDisplayCutoutMode"], 3); // ALWAYS
			}
			// (the window's own place on the screen: the panel's is the screen's, FLAG_LAYOUT_IN_SCREEN)
			var o = origin();
			JniEnv.SetIntField(Jni.env, params, m["lp.x"], px + o.x);
			JniEnv.SetIntField(Jni.env, params, m["lp.y"], py + o.y);
			JniEnv.SetIntField(Jni.env, params, m["lp.width"], pw);
			JniEnv.SetIntField(Jni.env, params, m["lp.height"], ph);
			// (hidden: FLAG_NOT_TOUCHABLE too, the touches the window's below)
			JniEnv.SetIntField(Jni.env, params, m["lp.flags"], 0x20 | 0x200 | 0x100 | 0x01000000 | (shown ? 0 : 0x10));
			var wm = Jni.obj(Jni.activity, m["getWindowManager"]);
			if (!added) {
				Jni.call(wm, m["addView"], web.toI64(), params.toI64());
				added = true;
			} else Jni.call(wm, m["updateViewLayout"], web.toI64(), params.toI64());
			Jni.deleteLocal(wm);
			Jni.call(web, m["setVisibility"], shown ? 0 : 4); // VISIBLE, INVISIBLE
		});
	}

	// (the main thread) the activity's window's top left on the screen (its decor view's)
	function origin():{x:Int, y:Int} {
		var w = Jni.obj(Jni.activity, m["getWindow"]);
		var d = Jni.obj(w, m["getDecorView"]);
		var a = JniEnv.NewIntArray(Jni.env, 2);
		Jni.call(d, m["getLocationOnScreen"], a.toI64());
		var buf = LibC.malloc(8);
		JniEnv.GetIntArrayRegion(Jni.env, a, 0, 2, buf);
		var r = {x: Mem.getI32(buf, 0), y: Mem.getI32(buf, 4)};
		LibC.free(buf);
		for (o in [a, d, w])
			Jni.deleteLocal(o);
		return r;
	}

	public function load(url:String)
		MainThread.post(() -> {
			if (disposed) return;
			var s = Jni.string(url);
			Jni.call(web, m["loadUrl"], s.toI64());
			Jni.deleteLocal(s);
		});

	public function loadHtml(html:String, ?baseUrl:String) {
		var base = baseUrl ?? (content != null ? content.url("") : null);
		// (the page has the bridge first, as the content's pages)
		var page = WebBridge.inject(html, bridgeJs);
		MainThread.post(() -> {
			if (disposed) return;
			var b = base == null ? Ptr.nil() : Jni.string(base), d = Jni.string(page), t = Jni.string("text/html"), e = Jni.string("utf-8");
			JniEnv.CallVoidMethodA(Jni.env, web, m["loadDataWithBaseURL"], args5(b, d, t, e, Ptr.nil()));
			Jni.check();
			for (o in [b, d, t, e])
				if (!o.isNull()) Jni.deleteLocal(o);
		});
	}

	static function args5(a:Ptr, b:Ptr, c:Ptr, d:Ptr, e:Ptr):Ptr {
		if (argsBuf.isNull()) argsBuf = LibC.malloc(64);
		Mem.setI64(argsBuf, 0, a.toI64());
		Mem.setI64(argsBuf, 8, b.toI64());
		Mem.setI64(argsBuf, 16, c.toI64());
		Mem.setI64(argsBuf, 24, d.toI64());
		Mem.setI64(argsBuf, 32, e.toI64());
		return argsBuf;
	}

	public function eval(js:String)
		MainThread.post(() -> if (!disposed) evaluate(js));

	public function goBack()
		MainThread.post(() -> if (!disposed) Jni.call(web, m["goBack"]));

	public function goForward()
		MainThread.post(() -> if (!disposed) Jni.call(web, m["goForward"]));

	public function reload()
		MainThread.post(() -> if (!disposed) Jni.call(web, m["reload"]));

	public function stop()
		MainThread.post(() -> if (!disposed) Jni.call(web, m["stopLoading"]));

	public function canGoBack():Bool {
		var r = false;
		MainThread.run(() -> r = !disposed && Jni.bool(web, m["canGoBack"]));
		return r;
	}

	// the view drawn into a bitmap (ARGB_8888: R G B A in memory, premultiplied)
	public function snapshot(f:Null<WebSnapshot>->Void)
		MainThread.post(() -> {
			var shot:Null<WebSnapshot> = null;
			if (!disposed) try {
				var w = Jni.int(web, m["getWidth"]), h = Jni.int(web, m["getHeight"]);
				if (w > 0 && h > 0) {
					var config = Arena.scopedValue(a -> {
						var c = Jni.cls("android.graphics.Bitmap$Config");
						JniEnv.GetStaticObjectField(Jni.env, c, JniEnv.GetStaticFieldID(Jni.env, c, a.cstring("ARGB_8888"), a.cstring("Landroid/graphics/Bitmap$Config;")));
					});
					var bmp = Jni.staticObj(cls["Bitmap"], m["createBitmap"], w, h, config.toI64());
					var canvas = Jni.newObject(cls["Canvas"], m["Canvas.<init>"], bmp.toI64());
					Jni.call(web, m["draw"], canvas.toI64());
					var n = w * h * 4, mem = LibC.malloc((n : Int64));
					var buf = JniEnv.NewDirectByteBuffer(Jni.env, mem, n);
					Jni.call(bmp, m["copyPixelsToBuffer"], buf.toI64());
					var px = haxe.io.Bytes.alloc(n);
					BytesPtr.copyIn(px, 0, mem, n);
					LibC.free(mem);
					Jni.call(bmp, m["recycle"]);
					for (o in [buf, canvas, bmp, config])
						Jni.deleteLocal(o);
					AppleWebView.unpremultiply(px);
					shot = {width: w, height: h, pixels: px};
				}
			} catch (e:Dynamic) Sys.println("helder.ui: a web view's snapshot: " + Std.string(e));
			lock.acquire();
			done.push(() -> f(shot));
			lock.release();
			MainThread.wake();
		});

	public function poll() {
		lock.acquire();
		var es = events.splice(0, events.length), ds = done.splice(0, done.length);
		lock.release();
		for (e in es)
			if (listener != null) listener.webViewEvent(e);
		for (d in ds)
			d();
	}

	public function dispose() {
		if (disposed) return;
		AndroidWindow.pumped.remove(pumped);
		MainThread.run(() -> {
			disposed = true;
			lock.acquire();
			byId.remove(id);
			lock.release();
			Glue.release(id);
			if (added) {
				var wm = Jni.obj(Jni.activity, m["getWindowManager"]);
				Jni.call(wm, m["removeView"], web.toI64());
				Jni.deleteLocal(wm);
			}
			Jni.call(web, m["destroy"]);
			Jni.deleteGlobal(web);
			if (!params.isNull()) Jni.deleteGlobal(params);
			web = params = Ptr.nil();
		});
		listener = null;
	}
}

// (made by WebShell alone, for a full-screen web view: the APK's activity
// org.hxmc.Activity, whose window draws views, its content the web view;
// helder.pack.android.Classes looks for an instance)
@:hxmc.android @:helder.android.views
class AndroidContent {
	public function new() {}
}
