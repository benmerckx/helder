package hxmc.os.uikit;

import hxmc.os.Event;
import hxmc.os.objc.*;
import hxmc.os.uikit.UIKitApp;
import hxmc.unsafe.*;

// hxmc.os.Window on iOS: a UIWindow on the main screen, full screen (its
// title and size are the system's), whose root view controller's view is
// an HxmcView (a UIView subclass made at run time) backed by a
// CAMetalLayer (+layerClass), which gfx's Metal back end draws to as on
// macOS (Surface kind Cocoa: the layer, the view). One window per app.
// The program runs inside UIKit's loop (UIKitApp): App.run turns the main
// run loop without waiting (poll: CFRunLoopRunInMode until nothing is
// left), and the frame's pace comes from the layer's drawables (vsync).
// A touch is the left button (MouseDown, MouseMove, MouseUp at the
// finger: the first finger down, until it lifts), and its drag scrolls too
// (Scroll by its motion), as on Android; positions in pixels from the top
// left. The view's size and safe area (the status bar, the notch, the home
// indicator: Window.safeTop, ...) are measured in layoutSubviews and
// safeAreaInsetsDidChange: a Resize event when either changed, ScaleChange
// when the scale did (another screen). The app going to the background is
// a Suspend event (UIKitApp's delegate; no frame is drawn then: iOS
// refuses GPU work in the background, and App.run sleeps in the run loop),
// coming back Resume; the layer stays, so the Surface is not lost. Keys
// and text input come later (a UIKeyInput view, as the macOS text view).
@:allow(hxmc.os)
class UIKitWindow {
	static var current:Null<UIKitWindow> = null;
	static var viewClass = Ptr.nil();
	static var mode = Ptr.nil(); // the run loop's default mode, a CFString
	static var suspended = false;
	static final event = new Event();
	// the App.run callback, for the view's and the delegate's events
	static var onEvent:Null<Event->Void>;

	final owner:Window;
	final window:Ptr; // UIWindow*
	final controller:Ptr; // its root UIViewController
	final view:Ptr; // HxmcView
	final layer:Ptr; // CAMetalLayer*, the view's
	final surface:Surface;
	var scale = 1.0;
	// the safe area's insets, in pixels
	var safeTop = 0;
	var safeLeft = 0;
	var safeBottom = 0;
	var safeRight = 0;
	// the finger followed (a UITouch*), and its last position in pixels
	var touch = Ptr.nil();
	var lastX = 0.0;
	var lastY = 0.0;
	final size:Ptr<CGSize>;

	function new(owner:Window, title:String, width:Int, height:Int) {
		if (current != null) throw "hxmc.os: an iOS app has one window";
		this.owner = owner;
		if (viewClass.isNull()) start();
		size = LibC.malloc(16);
		var screen = Msg.id(ObjC.cls("UIScreen"), ObjC.sel("mainScreen"));
		var bounds = Msg.rect(screen, ObjC.sel("bounds"));
		window = Msg.idRect(Msg.id(ObjC.cls("UIWindow"), ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), bounds);
		view = Msg.idRect(Msg.id(viewClass, ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), bounds);
		Msg.vBool(view, ObjC.sel("setMultipleTouchEnabled:"), false);
		layer = Msg.id(view, ObjC.sel("layer"));
		controller = Msg.id(Msg.id(ObjC.cls("UIViewController"), ObjC.sel("alloc")), ObjC.sel("init"));
		Msg.vPtr(controller, ObjC.sel("setView:"), view);
		Msg.vPtr(window, ObjC.sel("setRootViewController:"), controller);
		surface = new Surface(Cocoa, layer, view, 1, 1);
		current = this;
		measure();
		Msg.v(window, ObjC.sel("makeKeyAndVisible"));
	}

	static function start() {
		mode = ObjC.str("kCFRunLoopDefaultMode");
		var cls = Runtime.objc_allocateClassPair(ObjC.cls("UIView"), Mem.cstr("HxmcView"), 0);
		// (+layerClass: a class method, on the metaclass)
		Runtime.class_addMethod(Runtime.object_getClass(cls), ObjC.sel("layerClass"), Callback.addr(layerClass), Mem.cstr("#@:"));
		Runtime.class_addMethod(cls, ObjC.sel("layoutSubviews"), Callback.addr(layoutSubviews), Mem.cstr("v@:"));
		Runtime.class_addMethod(cls, ObjC.sel("safeAreaInsetsDidChange"), Callback.addr(layoutSubviews), Mem.cstr("v@:"));
		Runtime.class_addMethod(cls, ObjC.sel("touchesBegan:withEvent:"), Callback.addr(touchesBegan), Mem.cstr("v@:@@"));
		Runtime.class_addMethod(cls, ObjC.sel("touchesMoved:withEvent:"), Callback.addr(touchesMoved), Mem.cstr("v@:@@"));
		Runtime.class_addMethod(cls, ObjC.sel("touchesEnded:withEvent:"), Callback.addr(touchesEnded), Mem.cstr("v@:@@"));
		Runtime.class_addMethod(cls, ObjC.sel("touchesCancelled:withEvent:"), Callback.addr(touchesEnded), Mem.cstr("v@:@@"));
		Runtime.objc_registerClassPair(cls);
		viewClass = cls;
		UIKitApp.running = true;
	}

	@:hxmc.callback static function layerClass(self:Ptr, cmd:Ptr):Ptr
		return ObjC.cls("CAMetalLayer");

	// the size in pixels, the scale and the safe area, from the view; the
	// layer's drawables follow. Whether the size or the safe area changed
	function measure():Bool {
		var s = Msg.f(Msg.id(ObjC.cls("UIScreen"), ObjC.sel("mainScreen")), ObjC.sel("nativeScale"));
		if (s <= 0) s = 1;
		var scaled = s != scale;
		scale = s;
		Msg.vFloat(view, ObjC.sel("setContentScaleFactor:"), s);
		Msg.vFloat(layer, ObjC.sel("setContentsScale:"), s);
		var b = Msg.rect(view, ObjC.sel("bounds"));
		var w = Math.round(b.size.width * s), h = Math.round(b.size.height * s);
		if (w < 1) w = 1;
		if (h < 1) h = 1;
		size.value.width = w;
		size.value.height = h;
		Msg.vSize(layer, ObjC.sel("setDrawableSize:"), size.value);
		var i = Msg.insets(view, ObjC.sel("safeAreaInsets"));
		var t = Math.round(i.top * s), l = Math.round(i.left * s), bt = Math.round(i.bottom * s), r = Math.round(i.right * s);
		var changed = w != surface.width || h != surface.height || t != safeTop || l != safeLeft || bt != safeBottom || r != safeRight;
		safeTop = t;
		safeLeft = l;
		safeBottom = bt;
		safeRight = r;
		if (w != surface.width || h != surface.height) surface.resized(w, h);
		if (scaled && onEvent != null) {
			var e = event;
			e.kind = ScaleChange;
			e.window = owner;
			dispatch(e);
		}
		return changed;
	}

	@:hxmc.callback static function layoutSubviews(self:Ptr, cmd:Ptr):Void {
		var w = current;
		if (w == null || w.view != self || !w.measure()) return;
		var e = event;
		e.kind = Resize;
		e.window = w.owner;
		e.x = w.surface.width;
		e.y = w.surface.height;
		dispatch(e);
	}

	// ---- touches: the first finger down is the left button

	@:hxmc.callback static function touchesBegan(self:Ptr, cmd:Ptr, touches:Ptr, ev:Ptr):Void {
		var w = current;
		if (w == null || !w.touch.isNull()) return;
		var t = Msg.id(touches, ObjC.sel("anyObject"));
		if (t.isNull()) return;
		w.touch = t;
		w.locate(t);
		w.send(MouseMove, 0);
		w.send(MouseDown, 1);
	}

	@:hxmc.callback static function touchesMoved(self:Ptr, cmd:Ptr, touches:Ptr, ev:Ptr):Void {
		var w = current;
		if (w == null || w.touch.isNull() || !Msg.bPtr(touches, ObjC.sel("containsObject:"), w.touch)) return;
		var x = w.lastX, y = w.lastY;
		w.locate(w.touch);
		w.send(MouseMove, 0);
		var e = event;
		e.kind = Scroll;
		e.deltaX = x - w.lastX;
		e.deltaY = y - w.lastY;
		dispatch(e);
	}

	@:hxmc.callback static function touchesEnded(self:Ptr, cmd:Ptr, touches:Ptr, ev:Ptr):Void {
		var w = current;
		if (w == null || w.touch.isNull() || !Msg.bPtr(touches, ObjC.sel("containsObject:"), w.touch)) return;
		w.locate(w.touch);
		w.touch = Ptr.nil();
		w.send(MouseUp, 1);
	}

	function locate(t:Ptr) {
		var p = Msg.pointPtr(t, ObjC.sel("locationInView:"), view);
		lastX = p.x * scale;
		lastY = p.y * scale;
	}

	function send(kind:EventKind, button:Int) {
		var e = event;
		e.kind = kind;
		e.window = owner;
		e.x = Math.floor(lastX);
		e.y = Math.floor(lastY);
		e.button = button;
		e.mods = 0;
		e.text = "";
		dispatch(e);
	}

	// ---- the app's lifecycle (UIKitApp's delegate)

	static function suspend(on:Bool) {
		if (on == suspended) return;
		suspended = on;
		var w = current;
		if (w == null) return;
		var e = event;
		e.kind = on ? Suspend : Resume;
		e.window = w.owner;
		e.x = w.surface.width;
		e.y = w.surface.height;
		dispatch(e);
	}

	static function dispatch(e:Event)
		if (onEvent != null) onEvent(e);

	// whether a frame can be drawn now (not in the background)
	static function drawable():Bool
		return current != null && !suspended;

	// the run loop's pending sources, without waiting (the view's and the
	// delegate's callbacks come from inside)
	static function poll(onEvent:Event->Void) {
		UIKitWindow.onEvent = onEvent;
		if (mode.isNull()) return;
		while (CF.CFRunLoopRunInMode(mode, 0, true) == 4) {}
	}

	// waits for a source of the run loop, or seconds (< 0: no limit)
	static function wait(seconds:Float) {
		if (mode.isNull()) return;
		CF.CFRunLoopRunInMode(mode, seconds < 0 ? 1e9 : seconds, true);
	}

	function destroy() {
		current = null;
		Msg.vBool(window, ObjC.sel("setHidden:"), true);
		Runtime.objc_release(controller);
		Runtime.objc_release(view);
		Runtime.objc_release(window);
		LibC.free(size);
	}

	// the general pasteboard's text (UIPasteboard)
	static function writeClipboard(text:String) {
		var s = ObjC.str(text);
		Msg.vPtr(Msg.id(ObjC.cls("UIPasteboard"), ObjC.sel("generalPasteboard")), ObjC.sel("setString:"), s);
		ObjC.release(s);
	}

	static function readClipboard():Null<String> {
		var pool = Runtime.objc_autoreleasePoolPush();
		var text = ObjC.string(Msg.id(Msg.id(ObjC.cls("UIPasteboard"), ObjC.sel("generalPasteboard")), ObjC.sel("string")));
		Runtime.objc_autoreleasePoolPop(pool);
		return text;
	}

	// the system's appearance (the trait collection's interface style: 2 dark)
	static function dark():Bool
		return Msg.i(Msg.id(ObjC.cls("UITraitCollection"), ObjC.sel("currentTraitCollection")), ObjC.sel("userInterfaceStyle")) == 2;
}
