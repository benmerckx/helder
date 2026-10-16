package hxmc.os.cocoa;

import hxmc.os.Event;
import hxmc.os.objc.*;
import hxmc.unsafe.*;

// hxmc.os.Window on macOS: an NSWindow whose content view hosts a
// CAMetalLayer. One NSApplication for the process, set up with the first
// window. The loop stays hxmc's own (App.run): each frame drains Cocoa's
// event queue without waiting (nextEventMatchingMask with a past date) and
// the frame's pace comes from the layer's drawables (vsync), as on X11; a
// display link would call back on another thread, and the GPU layer is main
// thread only. A delegate class made at run time turns the close button into
// a Close event and resizes into Resize events (both from inside sendEvent:).
// Sizes and positions are in pixels (points times the backing scale), y down.
@:allow(hxmc.os)
class CocoaWindow {
	static var app = Ptr.nil();
	static var delegate = Ptr.nil();
	static var mode = Ptr.nil(); // the run loop's default mode, an NSString
	static final event = new Event();
	static final open:Array<CocoaWindow> = [];
	// the App.run callback, for the delegate's events
	static var onEvent:Null<Event->Void>;

	final owner:Window;
	final window:Ptr; // NSWindow*
	final view:Ptr; // its content view
	final layer:Ptr; // CAMetalLayer*
	final surface:Surface;
	var scale = 1.0;
	// (an NSRect and a CGSize to pass by value)
	final rect:Ptr<CGRect>;
	final size:Ptr<CGSize>;

	function new(owner:Window, title:String, width:Int, height:Int) {
		this.owner = owner;
		if (app.isNull()) start();
		rect = LibC.malloc(32);
		size = LibC.malloc(16);
		rect.value.origin.x = 0;
		rect.value.origin.y = 0;
		rect.value.size.width = width;
		rect.value.size.height = height;
		// titled, closable, miniaturizable, resizable; buffered backing
		window = Msg.idRectIntIntBool(Msg.id(ObjC.cls("NSWindow"), ObjC.sel("alloc")), ObjC.sel("initWithContentRect:styleMask:backing:defer:"), rect.value, 15,
			2, false);
		Msg.vBool(window, ObjC.sel("setReleasedWhenClosed:"), false);
		var t = ObjC.str(title);
		Msg.vPtr(window, ObjC.sel("setTitle:"), t);
		ObjC.release(t);
		Msg.vPtr(window, ObjC.sel("setDelegate:"), delegate);
		Msg.vBool(window, ObjC.sel("setAcceptsMouseMovedEvents:"), true);
		// (no line under the title bar: it would hide the content's top pixels)
		Msg.vInt(window, ObjC.sel("setTitlebarSeparatorStyle:"), 1);
		view = Msg.id(window, ObjC.sel("contentView"));
		// a layer-hosting view: the layer first, then wantsLayer
		layer = Runtime.objc_retain(Msg.id(ObjC.cls("CAMetalLayer"), ObjC.sel("layer")));
		Msg.vPtr(view, ObjC.sel("setLayer:"), layer);
		Msg.vBool(view, ObjC.sel("setWantsLayer:"), true);
		surface = new Surface(Cocoa, layer, view, width, height);
		open.push(this);
		measure();
		Msg.v(window, ObjC.sel("center"));
		Msg.vPtr(window, ObjC.sel("makeKeyAndOrderFront:"), Ptr.nil());
		Msg.vBool(app, ObjC.sel("activateIgnoringOtherApps:"), true);
	}

	static function start() {
		// (loads AppKit: its classes are found by name, so nothing else imports from it)
		AppKit.NSApplicationLoad();
		app = Msg.id(ObjC.cls("NSApplication"), ObjC.sel("sharedApplication"));
		Msg.iInt(app, ObjC.sel("setActivationPolicy:"), 0); // regular: a Dock icon, key windows
		Msg.v(app, ObjC.sel("finishLaunching"));
		mode = ObjC.str("kCFRunLoopDefaultMode");
		var cls = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcWindowDelegate"), 0);
		Runtime.class_addMethod(cls, ObjC.sel("windowShouldClose:"), Callback.addr(shouldClose), Mem.cstr("c@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("windowDidResize:"), Callback.addr(didResize), Mem.cstr("v@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("windowDidChangeBackingProperties:"), Callback.addr(didResize), Mem.cstr("v@:@"));
		Runtime.objc_registerClassPair(cls);
		delegate = Msg.id(Msg.id(cls, ObjC.sel("alloc")), ObjC.sel("init"));
	}

	// the size in pixels and the backing scale, from the content view; the
	// layer's drawables follow
	function measure():Bool {
		scale = Msg.f(window, ObjC.sel("backingScaleFactor"));
		var b = Msg.rect(view, ObjC.sel("bounds"));
		var w = Math.round(b.size.width * scale), h = Math.round(b.size.height * scale);
		Msg.vFloat(layer, ObjC.sel("setContentsScale:"), scale);
		size.value.width = w;
		size.value.height = h;
		Msg.vSize(layer, ObjC.sel("setDrawableSize:"), size.value);
		if (w == surface.width && h == surface.height) return false;
		surface.resized(w, h);
		return true;
	}

	function destroy() {
		open.remove(this);
		Msg.vPtr(window, ObjC.sel("setDelegate:"), Ptr.nil());
		Msg.v(window, ObjC.sel("close"));
		Runtime.objc_release(window);
		Runtime.objc_release(layer);
		LibC.free(rect);
		LibC.free(size);
	}

	static function find(window:Ptr):Null<CocoaWindow> {
		for (w in open)
			if (w.window == window) return w;
		return null;
	}

	static function dispatch(e:Event)
		if (onEvent != null) onEvent(e);

	@:hxmc.callback static function shouldClose(self:Ptr, cmd:Ptr, sender:Ptr):Int {
		var w = find(sender);
		if (w != null) {
			var e = event;
			e.kind = Close;
			e.window = w.owner;
			dispatch(e);
		}
		// (NO: the window stays open until close())
		return 0;
	}

	@:hxmc.callback static function didResize(self:Ptr, cmd:Ptr, note:Ptr):Void {
		var w = find(Msg.id(note, ObjC.sel("object")));
		if (w == null || !w.measure()) return;
		var e = event;
		e.kind = Resize;
		e.window = w.owner;
		e.x = w.surface.width;
		e.y = w.surface.height;
		dispatch(e);
	}

	// dispatches the pending events
	static function poll(onEvent:Event->Void) {
		CocoaWindow.onEvent = onEvent;
		var past = Msg.id(ObjC.cls("NSDate"), ObjC.sel("distantPast"));
		while (!app.isNull()) {
			var ev = Msg.idIntPtrPtrBool(app, ObjC.sel("nextEventMatchingMask:untilDate:inMode:dequeue:"), -1, past, mode, true);
			if (ev.isNull()) break;
			var w = find(Msg.id(ev, ObjC.sel("window")));
			var type = Msg.i(ev, ObjC.sel("type")).toInt();
			var key = type == NS.KeyDown || type == NS.KeyUp;
			if (w != null) w.translate(ev, type);
			// (keys stay ours: unhandled, AppKit would beep at each)
			if (!key || w == null) Msg.vPtr(app, ObjC.sel("sendEvent:"), ev);
		}
	}

	function translate(ev:Ptr, type:Int) {
		var e = event;
		e.kind = None;
		e.window = owner;
		switch type {
			case NS.KeyDown | NS.KeyUp:
				e.kind = type == NS.KeyDown ? KeyDown : KeyUp;
				e.key = keySym(ev);
			case NS.LeftMouseDown | NS.RightMouseDown | NS.OtherMouseDown:
				e.kind = MouseDown;
				e.button = button(ev, type);
			case NS.LeftMouseUp | NS.RightMouseUp | NS.OtherMouseUp:
				e.kind = MouseUp;
				e.button = button(ev, type);
			case NS.MouseMoved | NS.LeftMouseDragged | NS.RightMouseDragged | NS.OtherMouseDragged:
				e.kind = MouseMove;
				e.button = 0;
			case NS.ScrollWheel:
				var dy = Msg.f(ev, ObjC.sel("scrollingDeltaY"));
				if (dy == 0) return;
				// (the wheel as X11 has it: a press and a release of button 4 or 5)
				e.kind = MouseDown;
				e.button = dy > 0 ? 4 : 5;
			case _:
				return;
		}
		if (e.kind != KeyDown && e.kind != KeyUp) {
			var p = Msg.pointPointPtr(view, ObjC.sel("convertPoint:fromView:"), Msg.point(ev, ObjC.sel("locationInWindow")), Ptr.nil());
			var b = Msg.rect(view, ObjC.sel("bounds"));
			e.x = Math.floor(p.x * scale);
			e.y = Math.floor((b.size.height - p.y) * scale);
		}
		dispatch(e);
		if (type == NS.ScrollWheel) {
			e.kind = MouseUp;
			dispatch(e);
		}
	}

	static function button(ev:Ptr, type:Int):Int
		return switch type {
			case NS.LeftMouseDown | NS.LeftMouseUp: 1;
			case NS.RightMouseDown | NS.RightMouseUp: 3;
			case _: Msg.i(ev, ObjC.sel("buttonNumber")).toInt() == 2 ? 2 : 0;
		}

	// the key as an X11 KeySym (Event.key): the keys without a character by
	// their key code, the others by their character without modifiers
	static function keySym(ev:Ptr):Int {
		switch Msg.i(ev, ObjC.sel("keyCode")).toInt() {
			case 53: return 0xFF1B; // Escape
			case 36 | 76: return 0xFF0D; // Return, Enter
			case 48: return 0xFF09; // Tab
			case 51: return 0xFF08; // BackSpace
			case 117: return 0xFFFF; // Delete
			case 123: return 0xFF51; // Left
			case 124: return 0xFF53; // Right
			case 125: return 0xFF54; // Down
			case 126: return 0xFF52; // Up
			case _:
		}
		var s = Msg.id(ev, ObjC.sel("charactersIgnoringModifiers"));
		if (s.isNull() || Msg.i(s, ObjC.sel("length")) == 0) return 0;
		var c:Int = Msg.u16Int(s, ObjC.sel("characterAtIndex:"), 0);
		// (Shift still applies: the unshifted letter, as X11's first KeySym)
		return c >= "A".code && c <= "Z".code ? c + 32 : c;
	}
}

// AppKit's C functions: one, to load the framework (CocoaWindow.start)
@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/AppKit.framework/AppKit") extern class AppKit {
	static function NSApplicationLoad():Bool;
}

// NSEventType
class NS {
	public static inline var LeftMouseDown = 1;
	public static inline var LeftMouseUp = 2;
	public static inline var RightMouseDown = 3;
	public static inline var RightMouseUp = 4;
	public static inline var MouseMoved = 5;
	public static inline var LeftMouseDragged = 6;
	public static inline var RightMouseDragged = 7;
	public static inline var KeyDown = 10;
	public static inline var KeyUp = 11;
	public static inline var ScrollWheel = 22;
	public static inline var OtherMouseDown = 25;
	public static inline var OtherMouseUp = 26;
	public static inline var OtherMouseDragged = 27;
}
