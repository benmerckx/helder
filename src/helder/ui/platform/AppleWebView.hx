package helder.ui.platform;

import helder.os.objc.*;
import helder.ui.platform.PlatformWebView;
import helder.ui.platform.WkMsg;
import hxmc.unsafe.*;

// A WKWebView (WebKit), the same on iOS and macOS: a subview of the
// window's view (iOS: the HxmcView whose layer the GPU draws, the web view
// over it; macOS: the window's content view, y up), placed in points
// where its node is laid out; or the whole screen (iOS: fullScreen, a
// window of its own, WebShell's). One delegate (HxmcWebDelegate, made at
// first use) hears every web view:
// - WKURLSchemeHandler: its WebContent's custom scheme (app://localhost/),
//   each request answered at once (webView:startURLSchemeTask:) with an
//   NSHTTPURLResponse of the content's status and headers (COOP and COEP:
//   cross-origin isolation) and its bytes;
// - WKScriptMessageHandler: the bridge's messages (WebBridge's script, a
//   WKUserScript at each document's start, posts through
//   webkit.messageHandlers.helder; console.* lines too);
// - WKNavigationDelegate: a navigation started, committed (its URL),
//   finished, failed (provisionally or not), the content process gone;
// - key-value observing of title, estimatedProgress and URL.
// Native to the page: evaluateJavaScript:completionHandler: (no handler).
// A snapshot: takeSnapshotWithConfiguration:completionHandler: (a global
// block whose invoke is a callback), the UIImage's or NSImage's CGImage
// drawn into an RGBA bitmap, unpremultiplied. The web inspector:
// setInspectable: (iOS 16.4, macOS 13.3) where asked. Zoom off: the
// viewport's user-scalable=no and the scroll view's zoom scales at 1. The
// events wait for poll (the main thread is the program's here).
class AppleWebView implements PlatformWebView {
	static var delegateClass = Ptr.nil();
	static var delegate = Ptr.nil();
	static final views:Array<AppleWebView> = [];
	// (snapshots asked for, by the id in their block)
	static final snapshots = new Map<Int, Null<WebSnapshot>->Void>();
	static var nextSnapshot = 1;
	static var blockDescriptor = Ptr.nil();

	public final web:Ptr; // WKWebView*
	final parent:Ptr;
	final ios:Bool;
	final options:WebViewOptions;
	final content:Null<WebContent>;
	final queue:Array<WebViewEvent> = [];
	// (macOS: the server's messages, from its threads, until the main thread takes them)
	final posted:Array<String> = [];
	final lock = new sys.thread.Mutex();
	final queued:Void->Void;
	var listener:Null<WebViewListener> = null;
	var disposed = false;
	var lastX = -1.0;
	var lastY = -1.0;
	var lastW = -1.0;
	var lastH = -1.0;
	var lastShown = false;

	// a web view in parent (iOS: the window's UIView; macOS: its NSView,
	// whose window's content view takes it); queued: an event waits for poll
	public function new(parent:Ptr, options:WebViewOptions, queued:Void->Void, fullScreen = false) {
		this.ios = Mem.platform() >= 1;
		this.options = options;
		this.content = options.content;
		this.queued = queued;
		start();
		var pool = Runtime.objc_autoreleasePoolPush();
		var config = Msg.id(Msg.id(ObjC.cls("WKWebViewConfiguration"), ObjC.sel("alloc")), ObjC.sel("init"));
		var ucc = Msg.id(config, ObjC.sel("userContentController"));
		var name = ObjC.str("helder");
		Msg.vPtrPtr(ucc, ObjC.sel("addScriptMessageHandler:name:"), delegate, name);
		ObjC.release(name);
		// (macOS: through the content's own server where it has one, in order: WebKit's
		// script messages make a JSContext, whose stack check fails on helder's main stack there)
		var viaServer = !ios && content != null && content.local;
		var send = viaServer ? 'function(){var q=Promise.resolve(),u=${WebBridge.quote(content.url("__helder/post"))};'
			+ 'return function(s){q=q.then(function(){return fetch(u,{method:"POST",body:s,mode:"no-cors"});}).catch(function(){});};}()'
			: "function(s){window.webkit.messageHandlers.helder.postMessage(s);}";
		var js = WebBridge.script(ios ? "ios" : "macos", send, true);
		if (viaServer) content.onPost = s -> {
			lock.acquire();
			posted.push(s);
			lock.release();
			WkMsg.vPtrPtrBool(delegate, ObjC.sel("performSelectorOnMainThread:withObject:waitUntilDone:"), ObjC.sel("hxmcPosted:"), Ptr.nil(), false);
		};
		if (options.zoom != true)
			js += 'document.addEventListener("DOMContentLoaded",function(){var m=document.querySelector("meta[name=viewport]");'
				+ 'if(!m){m=document.createElement("meta");m.name="viewport";m.content="width=device-width, initial-scale=1";document.head.appendChild(m);}'
				+ 'if(m.content.indexOf("user-scalable")<0)m.content+=", maximum-scale=1, user-scalable=no";});';
		var src = ObjC.str(js);
		var script = WkMsg.idPtrIntBool(Msg.id(ObjC.cls("WKUserScript"), ObjC.sel("alloc")), ObjC.sel("initWithSource:injectionTime:forMainFrameOnly:"), src, 0, true);
		ObjC.release(src);
		Msg.vPtr(ucc, ObjC.sel("addUserScript:"), script);
		ObjC.release(script);
		if (content != null && !content.local) {
			var scheme = ObjC.str(content.scheme);
			Msg.vPtrPtr(config, ObjC.sel("setURLSchemeHandler:forURLScheme:"), delegate, scheme);
			ObjC.release(scheme);
		}
		if (ios) {
			Msg.vBool(config, ObjC.sel("setAllowsInlineMediaPlayback:"), true);
			Msg.vInt(config, ObjC.sel("setMediaTypesRequiringUserActionForPlayback:"), 0);
		}
		var alloc = Msg.id(ObjC.cls("WKWebView"), ObjC.sel("alloc")), init = ObjC.sel("initWithFrame:configuration:");
		if (fullScreen) web = WkMsg.idRectPtr(alloc, init, Msg.rect(Msg.id(ObjC.cls("UIScreen"), ObjC.sel("mainScreen")), ObjC.sel("bounds")), config) else
			web = Arena.scopedValue(a -> {
				var r = a.make(CGRect);
				r.value.size.width = 1;
				r.value.size.height = 1;
				WkMsg.idRectPtr(alloc, init, r.value, config);
			});
		ObjC.release(config);
		Msg.vPtr(web, ObjC.sel("setNavigationDelegate:"), delegate);
		for (k in ["title", "estimatedProgress", "URL"]) {
			var key = ObjC.str(k);
			WkMsg.vPtrPtrIntPtr(web, ObjC.sel("addObserver:forKeyPath:options:context:"), delegate, key, 1, Ptr.nil());
			ObjC.release(key);
		}
		Msg.vBool(web, ObjC.sel("setAllowsBackForwardNavigationGestures:"), options.backGesture != false);
		var inspect = options.inspectable ?? #if (hxmc.dev || helder.inspectable) true #else false #end;
		if (inspect && Msg.bPtr(web, ObjC.sel("respondsToSelector:"), ObjC.sel("setInspectable:"))) Msg.vBool(web, ObjC.sel("setInspectable:"), true);
		if (ios) {
			var sv = Msg.id(web, ObjC.sel("scrollView"));
			if (options.zoom != true) {
				Msg.vFloat(sv, ObjC.sel("setMinimumZoomScale:"), 1);
				Msg.vFloat(sv, ObjC.sel("setMaximumZoomScale:"), 1);
				Msg.vBool(sv, ObjC.sel("setBouncesZoom:"), false);
			}
			// (the page's own safe area: env(safe-area-inset-*), the scroll view not inset for it)
			if (fullScreen) Msg.vInt(sv, ObjC.sel("setContentInsetAdjustmentBehavior:"), 2);
			if (options.transparent == true) {
				Msg.vBool(web, ObjC.sel("setOpaque:"), false);
				Msg.vPtr(web, ObjC.sel("setBackgroundColor:"), Msg.id(ObjC.cls("UIColor"), ObjC.sel("clearColor")));
			}
		} else if (options.transparent == true) {
			var no = Msg.idInt(ObjC.cls("NSNumber"), ObjC.sel("numberWithBool:"), 0), key = ObjC.str("drawsBackground");
			Msg.vPtrPtr(web, ObjC.sel("setValue:forKey:"), no, key);
			ObjC.release(key);
		}
		if (fullScreen) {
			// (flexible width and height: the window's size)
			Msg.vInt(web, ObjC.sel("setAutoresizingMask:"), 18);
			this.parent = Ptr.nil();
		} else {
			this.parent = ios ? parent : Msg.id(Msg.id(parent, ObjC.sel("window")), ObjC.sel("contentView"));
			Msg.vBool(web, ObjC.sel("setHidden:"), true);
			Msg.vPtr(this.parent, ObjC.sel("addSubview:"), web);
		}
		Runtime.objc_autoreleasePoolPop(pool);
		views.push(this);
	}

	// ---- the whole screen (iOS: WebShell's): a window whose controller's view is the web view

	static var shellWindow = Ptr.nil();

	public static function fullScreen(options:WebViewOptions, queued:Void->Void):AppleWebView {
		var v = new AppleWebView(Ptr.nil(), options, queued, true);
		var screen = Msg.id(ObjC.cls("UIScreen"), ObjC.sel("mainScreen"));
		var bounds = Msg.rect(screen, ObjC.sel("bounds"));
		shellWindow = Msg.idRect(Msg.id(ObjC.cls("UIWindow"), ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), bounds);
		var vc = Msg.id(Msg.id(ObjC.cls("UIViewController"), ObjC.sel("alloc")), ObjC.sel("init"));
		Msg.vPtr(vc, ObjC.sel("setView:"), v.web);
		Msg.vPtr(shellWindow, ObjC.sel("setRootViewController:"), vc);
		Msg.v(shellWindow, ObjC.sel("makeKeyAndVisible"));
		return v;
	}

	// ---- PlatformWebView

	public function listen(l:WebViewListener)
		listener = l;

	public function place(x:Float, y:Float, width:Float, height:Float, shown:Bool) {
		if (disposed || parent.isNull()) return;
		if (shown != lastShown) {
			lastShown = shown;
			Msg.vBool(web, ObjC.sel("setHidden:"), !shown);
		}
		if (x == lastX && y == lastY && width == lastW && height == lastH) return;
		lastX = x;
		lastY = y;
		lastW = width;
		lastH = height;
		Arena.scoped(a -> {
			var r = a.make(CGRect);
			r.value.origin.x = x;
			// (macOS: the content view's y up)
			r.value.origin.y = ios ? y : Msg.rect(parent, ObjC.sel("bounds")).size.height - y - height;
			r.value.size.width = Math.max(1, width);
			r.value.size.height = Math.max(1, height);
			Msg.vRect(web, ObjC.sel("setFrame:"), r.value);
		});
	}

	public function load(url:String) {
		if (disposed) return;
		var pool = Runtime.objc_autoreleasePoolPush();
		var u = nsUrl(url);
		if (!u.isNull()) Msg.idPtr(web, ObjC.sel("loadRequest:"), Msg.idPtr(ObjC.cls("NSURLRequest"), ObjC.sel("requestWithURL:"), u));
		else push(error(url, "not a URL", -1));
		Runtime.objc_autoreleasePoolPop(pool);
	}

	public function loadHtml(html:String, ?baseUrl:String) {
		if (disposed) return;
		var pool = Runtime.objc_autoreleasePoolPush();
		var s = ObjC.str(html);
		var base = baseUrl ?? (content != null ? content.url("") : null);
		Msg.idPtrPtr(web, ObjC.sel("loadHTMLString:baseURL:"), s, base == null ? Ptr.nil() : nsUrl(base));
		ObjC.release(s);
		Runtime.objc_autoreleasePoolPop(pool);
	}

	public function eval(js:String) {
		if (disposed) return;
		var s = ObjC.str(js);
		Msg.vPtrPtr(web, ObjC.sel("evaluateJavaScript:completionHandler:"), s, Ptr.nil());
		ObjC.release(s);
	}

	public function goBack()
		if (!disposed) Msg.id(web, ObjC.sel("goBack"));

	public function goForward()
		if (!disposed) Msg.id(web, ObjC.sel("goForward"));

	public function reload()
		if (!disposed) Msg.id(web, ObjC.sel("reload"));

	public function stop()
		if (!disposed) Msg.v(web, ObjC.sel("stopLoading"));

	public function canGoBack():Bool
		return !disposed && Msg.b(web, ObjC.sel("canGoBack"));

	public function snapshot(done:Null<WebSnapshot>->Void) {
		if (disposed) {
			done(null);
			return;
		}
		var id = nextSnapshot++;
		snapshots.set(id, done);
		Msg.vPtrPtr(web, ObjC.sel("takeSnapshotWithConfiguration:completionHandler:"), Ptr.nil(), block(Callback.addr(snapshotTaken), id));
	}

	public function poll() {
		while (queue.length > 0) {
			var e = queue.shift();
			if (listener != null) listener.webViewEvent(e);
		}
	}

	public function dispose() {
		if (disposed) return;
		disposed = true;
		views.remove(this);
		for (k in ["title", "estimatedProgress", "URL"]) {
			var key = ObjC.str(k);
			Msg.vPtrPtr(web, ObjC.sel("removeObserver:forKeyPath:"), delegate, key);
			ObjC.release(key);
		}
		var ucc = Msg.id(Msg.id(web, ObjC.sel("configuration")), ObjC.sel("userContentController"));
		var name = ObjC.str("helder");
		Msg.vPtr(ucc, ObjC.sel("removeScriptMessageHandlerForName:"), name);
		ObjC.release(name);
		Msg.vPtr(web, ObjC.sel("setNavigationDelegate:"), Ptr.nil());
		Msg.v(web, ObjC.sel("stopLoading"));
		if (!parent.isNull()) Msg.v(web, ObjC.sel("removeFromSuperview"));
		ObjC.release(web);
		listener = null;
	}

	// ---- the delegate's

	function push(e:WebViewEvent) {
		queue.push(e);
		queued();
	}

	static function of(web:Ptr):Null<AppleWebView> {
		for (v in views)
			if (v.web == web) return v;
		return null;
	}

	static function nsUrl(s:String):Ptr {
		var ns = ObjC.str(s);
		var u = Msg.idPtr(ObjC.cls("NSURL"), ObjC.sel("URLWithString:"), ns);
		ObjC.release(ns);
		return u;
	}

	static function urlOf(web:Ptr):String {
		var u = Msg.id(web, ObjC.sel("URL"));
		return u.isNull() ? "" : ObjC.string(Msg.id(u, ObjC.sel("absoluteString"))) ?? "";
	}

	static function error(url:String, text:String, code:Int):WebViewEvent {
		var e = new WebViewEvent(LoadError);
		e.url = url;
		e.text = text;
		e.code = code;
		return e;
	}

	static function start() {
		if (!delegateClass.isNull()) return;
		Posix.dlopen(Mem.cstr("/System/Library/Frameworks/WebKit.framework/WebKit"), 2);
		// (hxmc dev's host: the class an earlier build made, its methods this build's)
		var d = ObjC.cls("HxmcWebDelegate"), fresh = d.isNull();
		if (fresh) d = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcWebDelegate"), 0);
		Runtime.class_replaceMethod(d, ObjC.sel("userContentController:didReceiveScriptMessage:"), Callback.addr(scriptMessage), Mem.cstr("v@:@@"));
		Runtime.class_replaceMethod(d, ObjC.sel("webView:didStartProvisionalNavigation:"), Callback.addr(started), Mem.cstr("v@:@@"));
		Runtime.class_replaceMethod(d, ObjC.sel("webView:didCommitNavigation:"), Callback.addr(committed), Mem.cstr("v@:@@"));
		Runtime.class_replaceMethod(d, ObjC.sel("webView:didFinishNavigation:"), Callback.addr(finished), Mem.cstr("v@:@@"));
		Runtime.class_replaceMethod(d, ObjC.sel("webView:didFailNavigation:withError:"), Callback.addr(failed), Mem.cstr("v@:@@@"));
		Runtime.class_replaceMethod(d, ObjC.sel("webView:didFailProvisionalNavigation:withError:"), Callback.addr(failed), Mem.cstr("v@:@@@"));
		Runtime.class_replaceMethod(d, ObjC.sel("webViewWebContentProcessDidTerminate:"), Callback.addr(terminated), Mem.cstr("v@:@"));
		Runtime.class_replaceMethod(d, ObjC.sel("webView:startURLSchemeTask:"), Callback.addr(startTask), Mem.cstr("v@:@@"));
		Runtime.class_replaceMethod(d, ObjC.sel("webView:stopURLSchemeTask:"), Callback.addr(stopTask), Mem.cstr("v@:@@"));
		Runtime.class_replaceMethod(d, ObjC.sel("hxmcPosted:"), Callback.addr(postedOnMain), Mem.cstr("v@:@"));
		Runtime.class_replaceMethod(d, ObjC.sel("observeValueForKeyPath:ofObject:change:context:"), Callback.addr(observed), Mem.cstr("v@:@@@^v"));
		for (p in ["WKNavigationDelegate", "WKScriptMessageHandler", "WKURLSchemeHandler"]) {
			var proto = Arena.scopedValue(a -> ObjcProtocols.objc_getProtocol(a.cstring(p)));
			if (!proto.isNull()) ObjcProtocols.class_addProtocol(d, proto);
		}
		if (fresh) Runtime.objc_registerClassPair(d);
		delegateClass = d;
		delegate = Msg.id(Msg.id(d, ObjC.sel("alloc")), ObjC.sel("init"));
	}

	@:hxmc.callback static function scriptMessage(self:Ptr, cmd:Ptr, ucc:Ptr, message:Ptr):Void {
		var v = of(Msg.id(message, ObjC.sel("webView")));
		if (v == null) return;
		var body = Msg.id(message, ObjC.sel("body"));
		var s = body.isNull() ? "" : ObjC.string(Msg.id(body, ObjC.sel("description"))) ?? "";
		v.push(WebViewEvent.message(s));
	}

	// (the main thread: the server's messages into each view's queue)
	@:hxmc.callback static function postedOnMain(self:Ptr, cmd:Ptr, o:Ptr):Void
		for (v in views) {
			v.lock.acquire();
			var ms = v.posted.splice(0, v.posted.length);
			v.lock.release();
			for (m in ms)
				v.push(WebViewEvent.message(m));
		}

	@:hxmc.callback static function started(self:Ptr, cmd:Ptr, web:Ptr, nav:Ptr):Void {
		var v = of(web);
		if (v == null) return;
		var e = new WebViewEvent(Navigate);
		e.url = urlOf(web);
		v.push(e);
	}

	@:hxmc.callback static function committed(self:Ptr, cmd:Ptr, web:Ptr, nav:Ptr):Void {}

	@:hxmc.callback static function finished(self:Ptr, cmd:Ptr, web:Ptr, nav:Ptr):Void {
		var v = of(web);
		if (v == null) return;
		var e = new WebViewEvent(Load);
		e.url = urlOf(web);
		v.push(e);
	}

	@:hxmc.callback static function failed(self:Ptr, cmd:Ptr, web:Ptr, nav:Ptr, err:Ptr):Void {
		var v = of(web);
		if (v == null) return;
		var text = ObjC.string(Msg.id(err, ObjC.sel("localizedDescription"))) ?? "";
		var info = Msg.id(err, ObjC.sel("userInfo"));
		var failing = Ptr.nil();
		if (!info.isNull()) {
			var k = ObjC.str("NSErrorFailingURLStringKey");
			failing = Msg.idPtr(info, ObjC.sel("objectForKey:"), k);
			ObjC.release(k);
		}
		v.push(error(failing.isNull() ? urlOf(web) : ObjC.string(failing) ?? "", text, Msg.i(err, ObjC.sel("code")).toInt()));
	}

	@:hxmc.callback static function terminated(self:Ptr, cmd:Ptr, web:Ptr):Void {
		var v = of(web);
		if (v != null) v.push(new WebViewEvent(Crash));
	}

	@:hxmc.callback static function observed(self:Ptr, cmd:Ptr, keyPath:Ptr, object:Ptr, change:Ptr, context:Ptr):Void {
		var v = of(object);
		if (v == null) return;
		switch ObjC.string(keyPath) {
			case "title":
				var e = new WebViewEvent(Title);
				e.text = ObjC.string(Msg.id(object, ObjC.sel("title"))) ?? "";
				e.url = urlOf(object);
				v.push(e);
			case "estimatedProgress":
				var e = new WebViewEvent(Progress);
				e.progress = WkMsg.f(object, ObjC.sel("estimatedProgress"));
				v.push(e);
			case "URL":
				var e = new WebViewEvent(UrlChange);
				e.url = urlOf(object);
				v.push(e);
			case _:
		}
	}

	// a request of the content's scheme, answered at once
	@:hxmc.callback static function startTask(self:Ptr, cmd:Ptr, web:Ptr, task:Ptr):Void {
		var v = of(web);
		var pool = Runtime.objc_autoreleasePoolPush();
		var url = Msg.id(Msg.id(task, ObjC.sel("request")), ObjC.sel("URL"));
		var s = ObjC.string(Msg.id(url, ObjC.sel("absoluteString"))) ?? "";
		var r = v == null || v.content == null ? WebResponse.error(404, "text/plain", "no content") : v.content.respond(s);
		var dict = Msg.id(ObjC.cls("NSMutableDictionary"), ObjC.sel("dictionary"));
		function set(k:String, val:String) {
			var nk = ObjC.str(k), nv = ObjC.str(val);
			Msg.vPtrPtr(dict, ObjC.sel("setObject:forKey:"), nv, nk);
			ObjC.release(nk);
			ObjC.release(nv);
		}
		set("Content-Type", r.mime);
		set("Content-Length", Std.string(r.body.length));
		for (k => val in r.headers)
			set(k, val);
		var version = ObjC.str("HTTP/1.1");
		var response = WkMsg.idPtrIntPtrPtr(Msg.id(ObjC.cls("NSHTTPURLResponse"), ObjC.sel("alloc")), ObjC.sel("initWithURL:statusCode:HTTPVersion:headerFields:"), url,
			r.status, version, dict);
		ObjC.release(version);
		Msg.vPtr(task, ObjC.sel("didReceiveResponse:"), response);
		ObjC.release(response);
		var n = r.body.length, copy = LibC.malloc((n + 1 : Int64));
		if (n > 0) LibC.memcpy(copy, BytesPtr.of(r.body, 0, n), (n : Int64));
		var data = Msg.idPtrInt(ObjC.cls("NSData"), ObjC.sel("dataWithBytes:length:"), copy, n);
		LibC.free(copy);
		Msg.vPtr(task, ObjC.sel("didReceiveData:"), data);
		Msg.v(task, ObjC.sel("didFinish"));
		Runtime.objc_autoreleasePoolPop(pool);
	}

	@:hxmc.callback static function stopTask(self:Ptr, cmd:Ptr, web:Ptr, task:Ptr):Void {}

	// ---- blocks: a global one (Block_copy keeps it as it is), its invoke f, an int after its descriptor

	static function block(f:Ptr, id:Int):Ptr {
		if (blockDescriptor.isNull()) {
			blockDescriptor = LibC.malloc(16);
			Mem.setI64(blockDescriptor, 0, 0);
			Mem.setI64(blockDescriptor, 8, 40);
		}
		// (never freed: WebKit may touch it after its call)
		var b = LibC.malloc(40);
		Mem.setPtr(b, 0, Posix.dlsym(Ptr.ofI64(-2), Mem.cstr("_NSConcreteGlobalBlock")));
		Mem.setI32(b, 8, 1 << 28); // BLOCK_IS_GLOBAL
		Mem.setI32(b, 12, 0);
		Mem.setPtr(b, 16, f);
		Mem.setPtr(b, 24, blockDescriptor);
		Mem.setI64(b, 32, id);
		return b;
	}

	@:hxmc.callback static function snapshotTaken(block:Ptr, image:Ptr, err:Ptr):Void {
		var id = Mem.getI64(block, 32).toInt();
		var done = snapshots.get(id);
		snapshots.remove(id);
		if (done == null) return;
		if (image.isNull()) {
			done(null);
			return;
		}
		var cg = Mem.platform() >= 1 ? Msg.id(image, ObjC.sel("CGImage")) : Msg.idPtrPtrPtr(image, ObjC.sel("CGImageForProposedRect:context:hints:"), Ptr.nil(),
			Ptr.nil(), Ptr.nil());
		done(cg.isNull() ? null : pixels(cg));
	}

	// a CGImage's pixels: RGBA8, straight alpha
	static function pixels(img:Ptr):WebSnapshot {
		var w = WkCG.CGImageGetWidth(img).toInt(), h = WkCG.CGImageGetHeight(img).toInt();
		var n = w * h * 4, buf = LibC.malloc((n : Int64));
		LibC.memset(buf, 0, (n : Int64));
		var space = WkCG.CGColorSpaceCreateDeviceRGB();
		// (kCGImageAlphaPremultipliedLast: R G B A)
		var ctx = WkCG.CGBitmapContextCreate(buf, w, h, 8, w * 4, space, 1);
		Arena.scoped(a -> {
			var r = a.make(CGRect);
			r.value.size.width = w;
			r.value.size.height = h;
			WkCG.CGContextDrawImage(ctx, r.value, img);
		});
		var out = haxe.io.Bytes.alloc(n);
		BytesPtr.copyIn(out, 0, buf, n);
		LibC.free(buf);
		WkCG.CGContextRelease(ctx);
		WkCG.CGColorSpaceRelease(space);
		unpremultiply(out);
		return {width: w, height: h, pixels: out};
	}

	public static function unpremultiply(b:haxe.io.Bytes) {
		var i = 0;
		while (i < b.length) {
			var a = b.get(i + 3);
			if (a != 0 && a != 255) {
				b.set(i, Std.int(Math.min(255, b.get(i) * 255 / a + 0.5)));
				b.set(i + 1, Std.int(Math.min(255, b.get(i + 1) * 255 / a + 0.5)));
				b.set(i + 2, Std.int(Math.min(255, b.get(i + 2) * 255 / a + 0.5)));
			}
			i += 4;
		}
	}
}
