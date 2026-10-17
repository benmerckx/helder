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
// The content view holds the layer's view and, under it, a text view of a
// class made at run time (HxmcTextView): while text input is on
// (Window.startTextInput) it is the first responder, placed at the caret,
// and the keys go through it (interpretKeyEvents:), so that input methods
// and dead keys compose in it: its marked text comes as TextEditing events,
// what it is given to insert as TextInput (and not kept), its commands
// (moves, deletions: KeyDown's) ignored.
// Sizes and positions are in pixels (points times the backing scale), y down.
@:allow(hxmc.os)
class CocoaWindow {
	static var app = Ptr.nil();
	static var delegate = Ptr.nil();
	static var mode = Ptr.nil(); // the run loop's default mode, an NSString
	static var textViewClass = Ptr.nil();
	static final event = new Event();
	static final open:Array<CocoaWindow> = [];
	// the App.run callback, for the delegate's events
	static var onEvent:Null<Event->Void>;

	final owner:Window;
	final window:Ptr; // NSWindow*
	final view:Ptr; // the layer's view, filling the content view
	final textView:Ptr; // HxmcTextView, under it
	// text input on; the composition last told (TextEditing)
	var typing = false;
	var marked = "";
	final layer:Ptr; // CAMetalLayer*
	final surface:Surface;
	var scale = 1.0;
	var cursor:Cursor = Default;
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
		var content = Msg.id(window, ObjC.sel("contentView"));
		textView = Msg.idRect(Msg.id(textViewClass, ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), rect.value);
		Msg.vBool(textView, ObjC.sel("setRichText:"), false);
		Msg.vPtr(content, ObjC.sel("addSubview:"), textView);
		view = Msg.idRect(Msg.id(ObjC.cls("NSView"), ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), rect.value);
		Msg.vInt(view, ObjC.sel("setAutoresizingMask:"), 18); // (width and height sizable)
		Msg.vPtr(content, ObjC.sel("addSubview:"), view);
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
		// (an NSRange by value after the text: not read)
		var t = Runtime.objc_allocateClassPair(ObjC.cls("NSTextView"), Mem.cstr("HxmcTextView"), 0);
		Runtime.class_addMethod(t, ObjC.sel("insertText:replacementRange:"), Callback.addr(insertText), Mem.cstr("v@:@{_NSRange=QQ}"));
		Runtime.class_addMethod(t, ObjC.sel("insertText:"), Callback.addr(insertText), Mem.cstr("v@:@"));
		Runtime.class_addMethod(t, ObjC.sel("doCommandBySelector:"), Callback.addr(doCommand), Mem.cstr("v@::"));
		Runtime.objc_registerClassPair(t);
		textViewClass = t;
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
		Runtime.objc_release(view);
		Runtime.objc_release(textView);
		LibC.free(rect);
		LibC.free(size);
	}

	function setTitle(t:String) {
		var s = ObjC.str(t);
		Msg.vPtr(window, ObjC.sel("setTitle:"), s);
		ObjC.release(s);
	}

	function resize(w:Int, h:Int) {
		size.value.width = w;
		size.value.height = h;
		Msg.vSize(window, ObjC.sel("setContentSize:"), size.value);
		measure();
	}

	function setMinSize(w:Int, h:Int) {
		size.value.width = w;
		size.value.height = h;
		Msg.vSize(window, ObjC.sel("setContentMinSize:"), size.value);
		measure();
	}

	function setCursor(c:Cursor) {
		cursor = c;
		applyCursor();
	}

	// (AppKit puts the arrow back as the pointer enters the window: set again on each move)
	function applyCursor() {
		var cls = ObjC.cls("NSCursor");
		var ns = switch cursor {
			case Pointer: Msg.id(cls, ObjC.sel("pointingHandCursor"));
			case Text: Msg.id(cls, ObjC.sel("IBeamCursor"));
			case Crosshair: Msg.id(cls, ObjC.sel("crosshairCursor"));
			case Move: Msg.id(cls, ObjC.sel("openHandCursor"));
			case NotAllowed: Msg.id(cls, ObjC.sel("operationNotAllowedCursor"));
			case ResizeEW: Msg.id(cls, ObjC.sel("resizeLeftRightCursor"));
			case ResizeNS: Msg.id(cls, ObjC.sel("resizeUpDownCursor"));
			case _: Msg.id(cls, ObjC.sel("arrowCursor"));
		}
		Msg.v(ns, ObjC.sel("set"));
	}

	// text input on: the text view at that area (pixels from the top left)
	// and the first responder; off: neither, its composition dropped
	function textInput(on:Bool, x:Int, y:Int, width:Int, height:Int) {
		if (!on) {
			if (!typing) return;
			typing = false;
			if (marked != "") Msg.v(Msg.id(textView, ObjC.sel("inputContext")), ObjC.sel("discardMarkedText"));
			marked = "";
			clearText(textView);
			Msg.bPtr(window, ObjC.sel("makeFirstResponder:"), Ptr.nil());
			return;
		}
		var b = Msg.rect(view, ObjC.sel("bounds"));
		rect.value.origin.x = x / scale;
		rect.value.origin.y = b.size.height - (y + height) / scale;
		rect.value.size.width = Math.max(1, width / scale);
		rect.value.size.height = Math.max(1, height / scale);
		Msg.vRect(textView, ObjC.sel("setFrame:"), rect.value);
		if (!typing) {
			typing = true;
			Msg.bPtr(window, ObjC.sel("makeFirstResponder:"), textView);
		}
		Msg.v(Msg.id(textView, ObjC.sel("inputContext")), ObjC.sel("invalidateCharacterCoordinates"));
	}

	static function clearText(tv:Ptr) {
		var e = ObjC.str("");
		Msg.vPtr(tv, ObjC.sel("setString:"), e);
		ObjC.release(e);
	}

	// the text view's marked text, told when it changed (TextEditing: the caret at its end)
	function composition() {
		if (!typing) return;
		var now = Msg.b(textView, ObjC.sel("hasMarkedText")) ? ObjC.string(Msg.id(textView, ObjC.sel("string"))) ?? "" : "";
		if (now == marked) return;
		marked = now;
		var e = event;
		e.kind = TextEditing;
		e.window = owner;
		e.text = now;
		e.x = now.length;
		dispatch(e);
	}

	// the text view is given text (an NSString or NSAttributedString): typed,
	// not kept; the composition it commits ends
	@:hxmc.callback static function insertText(self:Ptr, cmd:Ptr, text:Ptr):Void {
		var w:Null<CocoaWindow> = null;
		for (o in open)
			if (o.textView == self) w = o;
		if (w == null || text.isNull()) return;
		var s = Msg.bPtr(text, ObjC.sel("isKindOfClass:"), ObjC.cls("NSAttributedString")) ? Msg.id(text, ObjC.sel("string")) : text;
		var str = ObjC.string(s) ?? "";
		clearText(self);
		var e = event;
		e.window = w.owner;
		if (w.marked != "") {
			w.marked = "";
			e.kind = TextEditing;
			e.text = "";
			e.x = 0;
			dispatch(e);
		}
		var typed = new StringBuf();
		for (cp in new haxe.iterators.StringIteratorUnicode(str))
			if (cp >= 0x20 && cp != 0x7F && (cp < 0xF700 || cp > 0xF8FF)) typed.addChar(cp);
		if (typed.length == 0) return;
		e.kind = TextInput;
		e.text = typed.toString();
		e.mods = 0;
		dispatch(e);
	}

	// (its commands are the keys': KeyDown events)
	@:hxmc.callback static function doCommand(self:Ptr, cmd:Ptr, command:Ptr):Void {}

	// the general pasteboard's string (NSPasteboardTypeString: public.utf8-plain-text)
	static function writeClipboard(text:String) {
		var pb = Msg.id(ObjC.cls("NSPasteboard"), ObjC.sel("generalPasteboard"));
		Msg.i(pb, ObjC.sel("clearContents"));
		var s = ObjC.str(text), type = ObjC.str("public.utf8-plain-text");
		Msg.idPtrPtr(pb, ObjC.sel("setString:forType:"), s, type);
		ObjC.release(s);
		ObjC.release(type);
	}

	static function readClipboard():Null<String> {
		var pool = Runtime.objc_autoreleasePoolPush();
		var pb = Msg.id(ObjC.cls("NSPasteboard"), ObjC.sel("generalPasteboard"));
		var type = ObjC.str("public.utf8-plain-text");
		var text = ObjC.string(Msg.idPtr(pb, ObjC.sel("stringForType:"), type));
		ObjC.release(type);
		Runtime.objc_autoreleasePoolPop(pool);
		return text;
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

	// waits for an event (left in the queue for poll), or seconds
	static function wait(seconds:Float) {
		if (app.isNull()) return;
		var pool = Runtime.objc_autoreleasePoolPush();
		var until = Msg.idFloat(ObjC.cls("NSDate"), ObjC.sel("dateWithTimeIntervalSinceNow:"), seconds);
		Msg.idIntPtrPtrBool(app, ObjC.sel("nextEventMatchingMask:untilDate:inMode:dequeue:"), -1, until, mode, false);
		Runtime.objc_autoreleasePoolPop(pool);
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
			if (w != null) w.composition();
			// (keys stay ours: unhandled, AppKit would beep at each)
			if (!key || w == null) Msg.vPtr(app, ObjC.sel("sendEvent:"), ev);
		}
		// (a composition changed outside a key: the input method's own window, a message)
		for (w in open.copy())
			w.composition();
	}

	function translate(ev:Ptr, type:Int) {
		var e = event;
		e.kind = None;
		e.window = owner;
		switch type {
			case NS.KeyDown | NS.KeyUp:
				e.kind = type == NS.KeyDown ? KeyDown : KeyUp;
				e.key = keySym(ev);
				e.mods = mods(ev);
				if (type == NS.KeyDown && typing && e.mods & (Mods.CONTROL | Mods.META) == 0) {
					// (while an input method composes, its keys are its own)
					if (marked == "") dispatch(e);
					var pool = Runtime.objc_autoreleasePoolPush();
					Msg.vPtr(textView, ObjC.sel("interpretKeyEvents:"), Msg.idPtr(ObjC.cls("NSArray"), ObjC.sel("arrayWithObject:"), ev));
					Runtime.objc_autoreleasePoolPop(pool);
					return;
				}
				if (type == NS.KeyDown) {
					dispatch(e);
					// then its characters (not with Command or Control; not the function keys' private-use ones)
					if (e.mods & (Mods.CONTROL | Mods.META) != 0) return;
					var s = Msg.id(ev, ObjC.sel("characters"));
					if (s.isNull()) return;
					var str = ObjC.string(s);
					if (str == null) return;
					for (cp in new haxe.iterators.StringIteratorUnicode(str)) {
						if (cp < 0x20 || cp == 0x7F || (cp >= 0xF700 && cp <= 0xF8FF)) continue;
						e.kind = TextInput;
						e.text = String.fromCharCode(cp);
						dispatch(e);
					}
					return;
				}
			case NS.LeftMouseDown | NS.RightMouseDown | NS.OtherMouseDown:
				e.kind = MouseDown;
				e.mods = mods(ev);
				e.button = button(ev, type);
			case NS.LeftMouseUp | NS.RightMouseUp | NS.OtherMouseUp:
				e.kind = MouseUp;
				e.button = button(ev, type);
			case NS.MouseMoved | NS.LeftMouseDragged | NS.RightMouseDragged | NS.OtherMouseDragged:
				e.kind = MouseMove;
				e.button = 0;
				if (cursor != Default) applyCursor();
			case NS.ScrollWheel:
				var dx = Msg.f(ev, ObjC.sel("scrollingDeltaX")), dy = Msg.f(ev, ObjC.sel("scrollingDeltaY"));
				if (dx == 0 && dy == 0) return;
				// (a trackpad's points, exact; a wheel's lines, 40 pixels each; the
				// content follows the fingers, so the view scrolls the other way)
				var k = Msg.b(ev, ObjC.sel("hasPreciseScrollingDeltas")) ? scale : 40 * scale;
				e.kind = Scroll;
				e.mods = mods(ev);
				e.deltaX = -dx * k;
				e.deltaY = -dy * k;
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
	}

	// NSEventModifierFlags: Shift 1 << 17, Control 1 << 18, Option 1 << 19, Command 1 << 20
	static function mods(ev:Ptr):Int {
		var f = Msg.i(ev, ObjC.sel("modifierFlags")).toInt();
		return (f & (1 << 17) != 0 ? Mods.SHIFT : 0) | (f & (1 << 18) != 0 ? Mods.CONTROL : 0) | (f & (1 << 19) != 0 ? Mods.ALT : 0)
			| (f & (1 << 20) != 0 ? Mods.META : 0);
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
