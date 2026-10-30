package helder.os.uikit;

import helder.os.Event;
import helder.os.objc.*;
import helder.os.uikit.UIKitApp;
import hxmc.unsafe.*;

// helder.os.Window on iOS: a UIWindow on the main screen, full screen (its
// title and size are the system's), whose root view controller's view is
// an HxmcView (a UIView subclass made at run time) backed by a
// CAMetalLayer (+layerClass), which gfx's Metal back end draws to as on
// macOS (Surface kind Cocoa: the layer, the view). One window per app.
// The program runs inside UIKit's loop (UIKitApp): App.run turns the main
// run loop without waiting (poll: CFRunLoopRunInMode until nothing is
// left), and the frames are a CADisplayLink's on the main run loop (the
// view its target): asked for (requestVsync: the link running), its
// callback keeps the vsync's time (the link's timestamp, in
// haxe.Timer.stamp()'s seconds) and stops the run loop's wait, and the
// next turn draws; paused while the app sleeps (App.wait), is inactive or
// in the background.
// Every finger and pencil is a pointer (Pointers: Pointer* events,
// coalesced touches as samples, cancels); the first finger's compatibility
// gesture (Pointers.emulate) is as in the browser and on Android
// (TouchDrag): a tap clicks (the left button where it came
// down, once it lifts), a drag scrolls what is under where it started
// (Scrolls with Mods.TOUCH, ending with one of nothing without it, then a
// glide's when let go moving); positions in pixels from the top left. The
// view's size and safe area (the status bar, the notch, the home
// indicator: Window.safeTop, ...) are measured in layoutSubviews and
// safeAreaInsetsDidChange: a Resize event when either changed, ScaleChange
// when the scale did (another screen); a rotation is a new size, a Resize.
// The app going to the background is
// a Suspend event (UIKitApp's delegate; no frame is drawn then: iOS
// refuses GPU work in the background, and App.run sleeps in the run loop),
// coming back Resume; the layer stays, so the Surface is not lost. While
// the app is inactive (willResignActive: a call, the app switcher) no
// frame is drawn either, without an event. The controller is an
// HxmcViewController (made at run time) whose status bar and home
// indicator Window.immersive hides. Keys
// and text input come later (a UIKeyInput view, as the macOS text view).
@:allow(helder.os)
class UIKitWindow {
	static var current:Null<UIKitWindow> = null;
	static var viewClass = Ptr.nil();
	static var mode = Ptr.nil(); // the run loop's default mode, a CFString
	static var suspended = false;
	// (willResignActive until didBecomeActive)
	static var inactive = false;
	// the display link (CADisplayLink*), whether it runs, its last vsync not drawn yet and its time
	static var link = Ptr.nil();
	static var linked = false;
	static var due = false;
	static var vsyncAt = 0.0;
	static var hidden = false;
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
	var immersive = false;
	// the safe area's insets, in pixels
	var safeTop = 0;
	var safeLeft = 0;
	var safeBottom = 0;
	var safeRight = 0;
	// the finger followed (a UITouch*), its last position in pixels; its gesture
	var touch = Ptr.nil();
	var lastX = 0.0;
	var lastY = 0.0;
	static final drag = new TouchDrag();
	final size:Ptr<CGSize>;

	function new(owner:Window, title:String, width:Int, height:Int) {
		if (current != null) throw "helder.os: an iOS app has one window";
		this.owner = owner;
		if (viewClass.isNull()) start();
		size = LibC.malloc(16);
		#if hxmc.dev_host
		// (hxmc dev's host: the window, its controller and view as the last build left them)
		var kept = helder.dev.Hosted.hosted() ? helder.dev.Hosted.get(helder.dev.Hosted.UI_VIEW) : Ptr.nil();
		if (!kept.isNull()) {
			window = helder.dev.Hosted.get(helder.dev.Hosted.UI_WINDOW);
			controller = helder.dev.Hosted.get(helder.dev.Hosted.UI_CONTROLLER);
			view = kept;
			layer = Msg.id(view, ObjC.sel("layer"));
		} else {
		#end
		var screen = Msg.id(ObjC.cls("UIScreen"), ObjC.sel("mainScreen"));
		var bounds = Msg.rect(screen, ObjC.sel("bounds"));
		window = Msg.idRect(Msg.id(ObjC.cls("UIWindow"), ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), bounds);
		view = Msg.idRect(Msg.id(viewClass, ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), bounds);
		Msg.vBool(view, ObjC.sel("setMultipleTouchEnabled:"), true);
		layer = Msg.id(view, ObjC.sel("layer"));
		controller = Msg.id(Msg.id(controllerClass, ObjC.sel("alloc")), ObjC.sel("init"));
		Msg.vPtr(controller, ObjC.sel("setView:"), view);
		Msg.vPtr(window, ObjC.sel("setRootViewController:"), controller);
		#if hxmc.dev_host
		if (helder.dev.Hosted.hosted()) {
			helder.dev.Hosted.set(helder.dev.Hosted.UI_WINDOW, window);
			helder.dev.Hosted.set(helder.dev.Hosted.UI_CONTROLLER, controller);
			helder.dev.Hosted.set(helder.dev.Hosted.UI_VIEW, view);
		}
		}
		#end
		surface = new Surface(Cocoa, layer, view, 1, 1);
		current = this;
		measure();
		Msg.v(window, ObjC.sel("makeKeyAndVisible"));
		// (the display's frames: the link on the main run loop, held until a frame is asked for)
		link = Runtime.objc_retain(Msg.idPtrPtr(ObjC.cls("CADisplayLink"), ObjC.sel("displayLinkWithTarget:selector:"), view, ObjC.sel("hxmcFrame:")));
		Msg.vBool(link, ObjC.sel("setPaused:"), true);
		Msg.vPtrPtr(link, ObjC.sel("addToRunLoop:forMode:"), Msg.id(ObjC.cls("NSRunLoop"), ObjC.sel("mainRunLoop")), mode);
		linked = false;
		due = false;
		#if helder.fullscreen
		setImmersive(true);
		#end
	}

	static var controllerClass = Ptr.nil();

	// the controller's class: its status bar and home indicator hidden while immersive
	static function controllerMethods(cls:Ptr, replace:Bool) {
		for (sel in [ObjC.sel("prefersStatusBarHidden"), ObjC.sel("prefersHomeIndicatorAutoHidden")]) {
			if (replace) Runtime.class_replaceMethod(cls, sel, Callback.addr(prefersHidden), Mem.cstr("B@:")) else
				Runtime.class_addMethod(cls, sel, Callback.addr(prefersHidden), Mem.cstr("B@:"));
		}
	}

	@:hxmc.callback static function prefersHidden(self:Ptr, cmd:Ptr):Int
		return hidden ? 1 : 0;

	// Window.immersive: the status bar and the home indicator hidden (the controller asked again)
	function setImmersive(on:Bool) {
		immersive = on;
		hidden = on;
		Msg.v(controller, ObjC.sel("setNeedsStatusBarAppearanceUpdate"));
		Msg.v(controller, ObjC.sel("setNeedsUpdateOfHomeIndicatorAutoHidden"));
	}

	// ---- the display's frames (CADisplayLink)

	@:hxmc.callback static function displayFrame(self:Ptr, cmd:Ptr, sender:Ptr):Void {
		vsyncAt = FrameClock.toStamp(Msg.f(sender, ObjC.sel("timestamp")), QuartzCore.CACurrentMediaTime(), haxe.Timer.stamp());
		due = true;
		// (the turn's wait ends: the frame is drawn next)
		CF.CFRunLoopStop(CF.CFRunLoopGetMain());
	}

	static inline function vsynced():Bool
		return due;

	// the vsync's frame drawn now: its time
	static function takeVsync():Float {
		due = false;
		return vsyncAt;
	}

	// the link running: a callback at the next vsync
	static function requestVsync() {
		if (linked || link.isNull()) return;
		linked = true;
		Msg.vBool(link, ObjC.sel("setPaused:"), false);
	}

	// held: no callback until asked for again
	static function pauseVsync() {
		if (!linked) return;
		linked = false;
		Msg.vBool(link, ObjC.sel("setPaused:"), true);
	}

	static function start() {
		mode = ObjC.str("kCFRunLoopDefaultMode");
		#if hxmc.dev_host
		// (hxmc dev: the view's class and the app delegate's an earlier build made: their methods this build's)
		var made = Runtime.objc_getClass(Mem.cstr("HxmcView"));
		if (!made.isNull()) {
			Runtime.class_replaceMethod(Runtime.object_getClass(made), ObjC.sel("layerClass"), Callback.addr(layerClass), Mem.cstr("#@:"));
			Runtime.class_replaceMethod(made, ObjC.sel("layoutSubviews"), Callback.addr(layoutSubviews), Mem.cstr("v@:"));
			Runtime.class_replaceMethod(made, ObjC.sel("safeAreaInsetsDidChange"), Callback.addr(layoutSubviews), Mem.cstr("v@:"));
			Runtime.class_replaceMethod(made, ObjC.sel("touchesBegan:withEvent:"), Callback.addr(touchesBegan), Mem.cstr("v@:@@"));
			Runtime.class_replaceMethod(made, ObjC.sel("touchesMoved:withEvent:"), Callback.addr(touchesMoved), Mem.cstr("v@:@@"));
			Runtime.class_replaceMethod(made, ObjC.sel("touchesEnded:withEvent:"), Callback.addr(touchesEnded), Mem.cstr("v@:@@"));
			Runtime.class_replaceMethod(made, ObjC.sel("touchesCancelled:withEvent:"), Callback.addr(touchesCancelled), Mem.cstr("v@:@@"));
			Runtime.class_replaceMethod(made, ObjC.sel("hxmcFrame:"), Callback.addr(displayFrame), Mem.cstr("v@:@"));
			var vc = Runtime.objc_getClass(Mem.cstr("HxmcViewController"));
			if (vc.isNull()) controllerClass = makeController() else {
				controllerMethods(vc, true);
				controllerClass = vc;
			}
			UIKitApp.adopt();
			viewClass = made;
			UIKitApp.running = true;
			return;
		}
		#end
		var cls = Runtime.objc_allocateClassPair(ObjC.cls("UIView"), Mem.cstr("HxmcView"), 0);
		// (+layerClass: a class method, on the metaclass)
		Runtime.class_addMethod(Runtime.object_getClass(cls), ObjC.sel("layerClass"), Callback.addr(layerClass), Mem.cstr("#@:"));
		Runtime.class_addMethod(cls, ObjC.sel("layoutSubviews"), Callback.addr(layoutSubviews), Mem.cstr("v@:"));
		Runtime.class_addMethod(cls, ObjC.sel("safeAreaInsetsDidChange"), Callback.addr(layoutSubviews), Mem.cstr("v@:"));
		Runtime.class_addMethod(cls, ObjC.sel("touchesBegan:withEvent:"), Callback.addr(touchesBegan), Mem.cstr("v@:@@"));
		Runtime.class_addMethod(cls, ObjC.sel("touchesMoved:withEvent:"), Callback.addr(touchesMoved), Mem.cstr("v@:@@"));
		Runtime.class_addMethod(cls, ObjC.sel("touchesEnded:withEvent:"), Callback.addr(touchesEnded), Mem.cstr("v@:@@"));
		Runtime.class_addMethod(cls, ObjC.sel("touchesCancelled:withEvent:"), Callback.addr(touchesCancelled), Mem.cstr("v@:@@"));
		Runtime.class_addMethod(cls, ObjC.sel("hxmcFrame:"), Callback.addr(displayFrame), Mem.cstr("v@:@"));
		Runtime.objc_registerClassPair(cls);
		viewClass = cls;
		controllerClass = makeController();
		UIKitApp.running = true;
	}

	static function makeController():Ptr {
		var vc = Runtime.objc_allocateClassPair(ObjC.cls("UIViewController"), Mem.cstr("HxmcViewController"), 0);
		controllerMethods(vc, false);
		Runtime.objc_registerClassPair(vc);
		return vc;
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

	// ---- touches: every finger a pointer (Pointers: a UITouch's slot by its
	// address, its coalesced touches as samples); the first finger down the
	// compatibility gesture's (TouchDrag, while Pointers.emulate)

	@:hxmc.callback static function touchesBegan(self:Ptr, cmd:Ptr, touches:Ptr, ev:Ptr):Void {
		var w = current;
		if (w == null) return;
		var all = Msg.id(touches, ObjC.sel("allObjects")), n = Msg.i(all, ObjC.sel("count"));
		var i:Int64 = 0;
		while (i < n) {
			var t = Msg.idInt(all, ObjC.sel("objectAtIndex:"), i);
			i++;
			w.locate(t);
			var p = Pointers.press(w.owner, key(t), type(t), w.lastX, w.lastY, force(t), time(t));
			if (p != null) w.send(PointerDown, p, 1);
			if (!w.touch.isNull() || !Pointers.emulate) continue;
			w.touch = t;
			drag.press(w.lastX, w.lastY, time(t), w.scale);
		}
	}

	@:hxmc.callback static function touchesMoved(self:Ptr, cmd:Ptr, touches:Ptr, ev:Ptr):Void {
		var w = current;
		if (w == null) return;
		var all = Msg.id(touches, ObjC.sel("allObjects")), n = Msg.i(all, ObjC.sel("count"));
		var i:Int64 = 0;
		while (i < n) {
			var t = Msg.idInt(all, ObjC.sel("objectAtIndex:"), i);
			i++;
			var p = Pointers.find(key(t), type(t));
			if (p == null) continue;
			// (the touches the screen saw since the last: the latest is t)
			var co = ev.isNull() ? Ptr.nil() : Msg.idPtr(ev, ObjC.sel("coalescedTouchesForTouch:"), t);
			var cn = co.isNull() ? 0 : Msg.i(co, ObjC.sel("count"));
			var j:Int64 = 0;
			while (j < cn - 1) {
				var c = Msg.idInt(co, ObjC.sel("objectAtIndex:"), j);
				j++;
				w.locate(c);
				@:privateAccess p.sample(w.lastX, w.lastY, time(c));
			}
			w.locate(t);
			@:privateAccess p.moveTo(w.lastX, w.lastY, force(t), time(t));
			w.send(PointerMove, p, 0);
			if (t == w.touch && drag.move(w.lastX, w.lastY, time(t))) w.scroll(Mods.TOUCH);
		}
	}

	@:hxmc.callback static function touchesEnded(self:Ptr, cmd:Ptr, touches:Ptr, ev:Ptr):Void
		lift(touches, false);

	@:hxmc.callback static function touchesCancelled(self:Ptr, cmd:Ptr, touches:Ptr, ev:Ptr):Void
		lift(touches, true);

	static function lift(touches:Ptr, cancelled:Bool) {
		var w = current;
		if (w == null) return;
		var all = Msg.id(touches, ObjC.sel("allObjects")), n = Msg.i(all, ObjC.sel("count"));
		var i:Int64 = 0;
		while (i < n) {
			var t = Msg.idInt(all, ObjC.sel("objectAtIndex:"), i);
			i++;
			var p = Pointers.find(key(t), type(t));
			if (p != null) {
				w.locate(t);
				@:privateAccess p.moveTo(w.lastX, w.lastY, p.pressure, time(t));
				Pointers.lift(p, cancelled, time(t));
				w.send(cancelled ? PointerCancel : PointerUp, p, cancelled ? 0 : 1);
			}
			if (t != w.touch) continue;
			var end = drag.lift(time(t), cancelled);
			w.touch = Ptr.nil();
			if (end == TouchDrag.END) w.scroll(0) else if (end == TouchDrag.TAP) {
				w.click(MouseMove);
				w.click(MouseDown);
				w.click(MouseUp);
			}
		}
	}

	// a UITouch's key (Pointers: its address, folded)
	static inline function key(t:Ptr):Int {
		var a = t.toI64();
		return (a >> 32).toInt() ^ a.toInt();
	}

	// UITouchTypePencil (2): a pen; the others fingers (indirect pointers too)
	static inline function type(t:Ptr):PointerType
		return Msg.i(t, ObjC.sel("type")) == 2 ? Pen : Touch;

	// its force, 0 to 1 (1 where the screen measures none)
	static function force(t:Ptr):Float {
		var max = Msg.f(t, ObjC.sel("maximumPossibleForce"));
		return max > 0 ? Math.min(1, Msg.f(t, ObjC.sel("force")) / max) : 1;
	}

	// a touch's time (ms: UITouch.timestamp, seconds since the boot)
	static function time(t:Ptr):Float
		return Msg.f(t, ObjC.sel("timestamp")) * 1000;

	function locate(t:Ptr) {
		var p = Msg.pointPtr(t, ObjC.sel("locationInView:"), view);
		lastX = p.x * scale;
		lastY = p.y * scale;
	}

	function send(kind:EventKind, p:Pointer, button:Int) {
		var e = event;
		Pointers.fill(e, kind, p, button);
		dispatch(e);
	}

	function scroll(mods:Int) {
		var e = event;
		drag.scroll(e, mods);
		e.window = owner;
		dispatch(e);
	}

	function click(kind:EventKind) {
		var e = event;
		drag.click(e, kind);
		e.window = owner;
		dispatch(e);
	}

	// ---- the app's lifecycle (UIKitApp's delegate)

	// willResignActive (on) and didBecomeActive: no frames meanwhile, no event
	static function activate(on:Bool) {
		inactive = !on;
		if (!on) pauseVsync();
	}

	static function suspend(on:Bool) {
		if (on == suspended) return;
		suspended = on;
		if (on) pauseVsync();
		drag.stop();
		var w = current;
		if (w == null) return;
		var e = event;
		// (the background: every finger let go)
		if (on) Pointers.cancelAll(w.owner, e, onEvent);
		e.kind = on ? Suspend : Resume;
		e.window = w.owner;
		e.x = w.surface.width;
		e.y = w.surface.height;
		dispatch(e);
	}

	static function dispatch(e:Event)
		if (onEvent != null) onEvent(e);

	// whether a frame can be drawn now (active: not in the background, nor inactive)
	static function drawable():Bool
		return current != null && !suspended && !inactive;

	// the run loop's pending sources, without waiting (the view's and the
	// delegate's callbacks come from inside)
	static function poll(onEvent:Event->Void) {
		UIKitWindow.onEvent = onEvent;
		if (mode.isNull()) return;
		while (CF.CFRunLoopRunInMode(mode, 0, true) == 4) {}
		// (a drag let go moving: its glide's scroll since the last)
		var w = current;
		if (w != null && drag.gliding && drag.glide(haxe.Timer.stamp() * 1000)) w.scroll(0);
	}

	// waits for a source of the run loop, or seconds (< 0: no limit; a
	// frame while a drag glides)
	static function wait(seconds:Float) {
		if (mode.isNull()) return;
		seconds = drag.wait(seconds);
		CF.CFRunLoopRunInMode(mode, seconds < 0 ? 1e9 : seconds, true);
	}

	function destroy() {
		current = null;
		// (the link's target is this build's view class's method: gone with it, also at a hand-over)
		if (!link.isNull()) {
			Msg.v(link, ObjC.sel("invalidate"));
			Runtime.objc_release(link);
			link = Ptr.nil();
			linked = due = false;
		}
		#if hxmc.dev_host
		// (handing over: the window, its controller and view left to the next build)
		if (helder.dev.Hosted.handingOver && helder.dev.Hosted.get(helder.dev.Hosted.UI_VIEW) == view) {
			LibC.free(size);
			return;
		}
		#end
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

	// helder.os.Haptics: a selection's tick (UISelectionFeedbackGenerator),
	// a medium impact (UIImpactFeedbackGenerator, style 1), each made and let go
	static function haptic(strong:Bool) {
		var g = strong ? Msg.idInt(Msg.id(ObjC.cls("UIImpactFeedbackGenerator"), ObjC.sel("alloc")), ObjC.sel("initWithStyle:"), 1) : Msg.id(Msg.id(ObjC.cls("UISelectionFeedbackGenerator"),
			ObjC.sel("alloc")), ObjC.sel("init"));
		if (g.isNull()) return;
		if (strong) Msg.v(g, ObjC.sel("impactOccurred")) else Msg.v(g, ObjC.sel("selectionChanged"));
		ObjC.release(g);
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
