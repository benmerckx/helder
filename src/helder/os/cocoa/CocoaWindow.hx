package helder.os.cocoa;

import helder.os.Event;
import helder.os.objc.*;
import hxmc.unsafe.*;

// helder.os.Window on macOS: an NSWindow whose content view hosts a
// CAMetalLayer. One NSApplication for the process, set up with the first
// window. The loop stays hxmc's own (App.run): each frame drains Cocoa's
// event queue without waiting (nextEventMatchingMask with a past date) and
// the frame's pace comes from the layer's drawables (vsync), as on X11; a
// display link would call back on another thread, and the GPU layer is main
// thread only. A delegate class made at run time turns the close button into
// a Close event, resizes into Resize events and a new backing scale (another
// display) into ScaleChange (from inside sendEvent:). A drag of the window's
// edge is AppKit's own loop until the mouse is up: each of its resizes draws
// a frame (onFrame), and the layer shows a drawable of another size at its
// top left, unscaled, until the next.
// The content view holds the layer's view and, under it, a text view of a
// class made at run time (HxmcTextView): while text input is on
// (Window.startTextInput) it is the first responder, placed at the caret,
// and the keys go through it (interpretKeyEvents:), so that input methods
// and dead keys compose in it: its marked text comes as TextEditing events,
// what it is given to insert as TextInput (and not kept), its commands
// (moves, deletions: KeyDown's) ignored.
// The application has the menu bar Mac apps have: its own menu (Hide,
// Hide Others, Show All, Quit) and a Window menu (Minimize, Zoom, Close,
// the windows), their shortcuts taken before the keys are ours. Quit (and
// the Dock's) asks every window to close: a Close event each, as their
// close buttons; the app ends when it closes them.
// Sizes and positions are in pixels (points times the backing scale), y down.
@:allow(helder.os)
class CocoaWindow {
	static var app = Ptr.nil();
	static var delegate = Ptr.nil();
	static var mode = Ptr.nil(); // the run loop's default mode, an NSString
	static var textViewClass = Ptr.nil();
	static final event = new Event();
	static final open:Array<CocoaWindow> = [];
	// the App.run callbacks, for the delegate's events and a live resize's frames
	static var onEvent:Null<Event->Void>;
	static var onFrame:Null<Void->Void>;

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
	var over = false; // the pointer over the content, at the last move
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
		#if hxmc.dev_host
		// (hxmc dev's host: the first window, its views and layer as the last build left them)
		var kept = helder.dev.Hosted.hosted() && open.length == 0 ? helder.dev.Hosted.get(helder.dev.Hosted.UI_WINDOW) : Ptr.nil();
		if (!kept.isNull()) {
			window = kept;
			textView = helder.dev.Hosted.get(helder.dev.Hosted.UI_CONTROLLER);
			view = helder.dev.Hosted.get(helder.dev.Hosted.UI_VIEW);
			Msg.vBool(textView, ObjC.sel("setHidden:"), true);
			layer = helder.dev.Hosted.get(helder.dev.Hosted.MAC_LAYER);
			var t = ObjC.str(title);
			Msg.vPtr(window, ObjC.sel("setTitle:"), t);
			ObjC.release(t);
			surface = new Surface(Cocoa, layer, view, width, height);
			open.push(this);
			measure();
			return;
		}
		#end
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
		// (hidden while text input is off: shown, it takes the clicks over it,
		// their drags and releases, and shows its I-beam)
		Msg.vBool(textView, ObjC.sel("setHidden:"), true);
		Msg.vPtr(content, ObjC.sel("addSubview:"), textView);
		view = Msg.idRect(Msg.id(ObjC.cls("NSView"), ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), rect.value);
		Msg.vInt(view, ObjC.sel("setAutoresizingMask:"), 18); // (width and height sizable)
		Msg.vPtr(content, ObjC.sel("addSubview:"), view);
		// a layer-hosting view: the layer first, then wantsLayer
		layer = Runtime.objc_retain(Msg.id(ObjC.cls("CAMetalLayer"), ObjC.sel("layer")));
		// (a drawable of another size than the view's, between a resize and its
		// frame: shown as it is, not stretched)
		var gravity = ObjC.str("topLeft");
		Msg.vPtr(layer, ObjC.sel("setContentsGravity:"), gravity);
		ObjC.release(gravity);
		Msg.vPtr(view, ObjC.sel("setLayer:"), layer);
		Msg.vBool(view, ObjC.sel("setWantsLayer:"), true);
		surface = new Surface(Cocoa, layer, view, width, height);
		open.push(this);
		#if hxmc.dev_host
		if (helder.dev.Hosted.hosted() && open.length == 1) {
			helder.dev.Hosted.set(helder.dev.Hosted.UI_WINDOW, window);
			helder.dev.Hosted.set(helder.dev.Hosted.UI_CONTROLLER, textView);
			helder.dev.Hosted.set(helder.dev.Hosted.UI_VIEW, view);
			helder.dev.Hosted.set(helder.dev.Hosted.MAC_LAYER, layer);
		}
		#end
		measure();
		Msg.v(window, ObjC.sel("center"));
		Msg.vPtr(window, ObjC.sel("makeKeyAndOrderFront:"), Ptr.nil());
		Msg.vBool(app, ObjC.sel("activateIgnoringOtherApps:"), true);
	}

	static function start() {
		// (loads AppKit: its classes are found by name, so nothing else imports from it)
		AppKit.NSApplicationLoad();
		app = Msg.id(ObjC.cls("NSApplication"), ObjC.sel("sharedApplication"));
		#if hxmc.dev_host
		// (hxmc dev: the classes an earlier build made, their methods this build's; its delegate)
		var made = Runtime.objc_getClass(Mem.cstr("HxmcWindowDelegate"));
		if (!made.isNull() && helder.dev.Hosted.hosted()) {
			mode = ObjC.str("kCFRunLoopDefaultMode");
			Runtime.class_replaceMethod(made, ObjC.sel("windowShouldClose:"), Callback.addr(shouldClose), Mem.cstr("c@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("windowDidResize:"), Callback.addr(didResize), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("windowDidChangeBackingProperties:"), Callback.addr(didChangeScale), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("windowWillStartLiveResize:"), Callback.addr(startResize), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("windowDidEndLiveResize:"), Callback.addr(endResize), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("liveFrame:"), Callback.addr(liveFrame), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(made, ObjC.sel("applicationShouldTerminate:"), Callback.addr(shouldTerminate), Mem.cstr("Q@:@"));
			delegate = helder.dev.Hosted.get(helder.dev.Hosted.MAC_DELEGATE);
			var t = Runtime.objc_getClass(Mem.cstr("HxmcTextView"));
			Runtime.class_replaceMethod(t, ObjC.sel("insertText:replacementRange:"), Callback.addr(insertText), Mem.cstr("v@:@{_NSRange=QQ}"));
			Runtime.class_replaceMethod(t, ObjC.sel("insertText:"), Callback.addr(insertText), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(t, ObjC.sel("doCommandBySelector:"), Callback.addr(doCommand), Mem.cstr("v@::"));
			textViewClass = t;
			return;
		}
		#end
		Msg.iInt(app, ObjC.sel("setActivationPolicy:"), 0); // regular: a Dock icon, key windows
		Msg.v(app, ObjC.sel("finishLaunching"));
		mode = ObjC.str("kCFRunLoopDefaultMode");
		var cls = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcWindowDelegate"), 0);
		Runtime.class_addMethod(cls, ObjC.sel("windowShouldClose:"), Callback.addr(shouldClose), Mem.cstr("c@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("windowDidResize:"), Callback.addr(didResize), Mem.cstr("v@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("windowDidChangeBackingProperties:"), Callback.addr(didChangeScale), Mem.cstr("v@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("windowWillStartLiveResize:"), Callback.addr(startResize), Mem.cstr("v@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("windowDidEndLiveResize:"), Callback.addr(endResize), Mem.cstr("v@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("liveFrame:"), Callback.addr(liveFrame), Mem.cstr("v@:@"));
		// (the application's delegate too)
		Runtime.class_addMethod(cls, ObjC.sel("applicationShouldTerminate:"), Callback.addr(shouldTerminate), Mem.cstr("Q@:@"));
		Runtime.objc_registerClassPair(cls);
		delegate = Msg.id(Msg.id(cls, ObjC.sel("alloc")), ObjC.sel("init"));
		Msg.vPtr(app, ObjC.sel("setDelegate:"), delegate);
		#if hxmc.dev_host
		if (helder.dev.Hosted.hosted()) helder.dev.Hosted.set(helder.dev.Hosted.MAC_DELEGATE, delegate);
		#end
		menus();
		// (an NSRange by value after the text: not read)
		var t = Runtime.objc_allocateClassPair(ObjC.cls("NSTextView"), Mem.cstr("HxmcTextView"), 0);
		Runtime.class_addMethod(t, ObjC.sel("insertText:replacementRange:"), Callback.addr(insertText), Mem.cstr("v@:@{_NSRange=QQ}"));
		Runtime.class_addMethod(t, ObjC.sel("insertText:"), Callback.addr(insertText), Mem.cstr("v@:@"));
		Runtime.class_addMethod(t, ObjC.sel("doCommandBySelector:"), Callback.addr(doCommand), Mem.cstr("v@::"));
		Runtime.objc_registerClassPair(t);
		textViewClass = t;
	}

	// the menu bar: the application's menu and the Window menu
	static function menus() {
		var name = ObjC.string(Msg.id(Msg.id(ObjC.cls("NSProcessInfo"), ObjC.sel("processInfo")), ObjC.sel("processName")));
		function menu(title:String):Ptr {
			var t = ObjC.str(title);
			var m = Msg.idPtr(Msg.id(ObjC.cls("NSMenu"), ObjC.sel("alloc")), ObjC.sel("initWithTitle:"), t);
			ObjC.release(t);
			return m;
		}
		// (modifiers: NSEventModifierFlagOption, Command)
		function item(m:Ptr, title:String, action:Ptr, key:String, ?mods:Int) {
			var t = ObjC.str(title), k = ObjC.str(key);
			var it = Msg.idPtrPtrPtr(Msg.id(ObjC.cls("NSMenuItem"), ObjC.sel("alloc")), ObjC.sel("initWithTitle:action:keyEquivalent:"), t, action, k);
			if (mods != null) Msg.vInt(it, ObjC.sel("setKeyEquivalentModifierMask:"), mods);
			Msg.vPtr(m, ObjC.sel("addItem:"), it);
			ObjC.release(it);
			ObjC.release(t);
			ObjC.release(k);
		}
		function separator(m:Ptr)
			Msg.vPtr(m, ObjC.sel("addItem:"), Msg.id(ObjC.cls("NSMenuItem"), ObjC.sel("separatorItem")));
		function submenu(bar:Ptr, m:Ptr) {
			var it = Msg.id(Msg.id(ObjC.cls("NSMenuItem"), ObjC.sel("alloc")), ObjC.sel("init"));
			Msg.vPtr(it, ObjC.sel("setSubmenu:"), m);
			Msg.vPtr(bar, ObjC.sel("addItem:"), it);
			ObjC.release(it);
		}
		var bar = menu("");
		var own = menu(name);
		item(own, "Hide " + name, ObjC.sel("hide:"), "h");
		item(own, "Hide Others", ObjC.sel("hideOtherApplications:"), "h", (1 << 19) | (1 << 20));
		item(own, "Show All", ObjC.sel("unhideAllApplications:"), "");
		separator(own);
		item(own, "Quit " + name, ObjC.sel("terminate:"), "q");
		submenu(bar, own);
		var windows = menu("Window");
		item(windows, "Minimize", ObjC.sel("performMiniaturize:"), "m");
		item(windows, "Zoom", ObjC.sel("performZoom:"), "");
		item(windows, "Close", ObjC.sel("performClose:"), "w");
		separator(windows);
		submenu(bar, windows);
		Msg.vPtr(app, ObjC.sel("setMainMenu:"), bar);
		Msg.vPtr(app, ObjC.sel("setWindowsMenu:"), windows);
		ObjC.release(own);
		ObjC.release(windows);
		ObjC.release(bar);
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
		#if hxmc.dev_host
		// (handing over: the window, its views and layer left to the next build)
		if (helder.dev.Hosted.handingOver && helder.dev.Hosted.get(helder.dev.Hosted.UI_WINDOW) == window) {
			LibC.free(rect);
			LibC.free(size);
			return;
		}
		#end
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
		if (measure()) resized();
	}

	function setMinSize(w:Int, h:Int) {
		size.value.width = w;
		size.value.height = h;
		Msg.vSize(window, ObjC.sel("setContentMinSize:"), size.value);
		if (measure()) resized();
	}

	// a resize told: as a Resize event, or at the next poll when there is
	// no loop yet (a size set before App.run: setContentSize: tells the
	// delegate at once)
	var pending = false;

	function resized() {
		if (onEvent == null) {
			pending = true;
			return;
		}
		pending = false;
		var e = event;
		e.kind = Resize;
		e.window = owner;
		e.x = surface.width;
		e.y = surface.height;
		dispatch(e);
	}

	function setCursor(c:Cursor) {
		cursor = c;
		applyCursor();
	}

	// the cursor at a move: the app's over the content (and while a button is
	// held), the arrow once as the pointer leaves it (AppKit's then: the
	// edges' resize cursors, the other windows')
	function hover(inside:Bool) {
		if (inside && (cursor != Default || !over)) applyCursor() else if (!inside && over)
			Msg.v(Msg.id(ObjC.cls("NSCursor"), ObjC.sel("arrowCursor")), ObjC.sel("set"));
		over = inside;
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
			case Grab: Msg.id(cls, ObjC.sel("openHandCursor"));
			case Grabbing: Msg.id(cls, ObjC.sel("closedHandCursor"));
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
			Msg.vBool(textView, ObjC.sel("setHidden:"), true);
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
			Msg.vBool(textView, ObjC.sel("setHidden:"), false);
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

	// Quit: each window asked to close; NSTerminateCancel (the loop is ours)
	@:hxmc.callback static function shouldTerminate(self:Ptr, cmd:Ptr, sender:Ptr):Int64 {
		for (w in open.copy()) {
			var e = event;
			e.kind = Close;
			e.window = w.owner;
			dispatch(e);
		}
		return 0;
	}

	// another display: a new scale (ScaleChange), and a Resize when the pixels changed
	@:hxmc.callback static function didChangeScale(self:Ptr, cmd:Ptr, note:Ptr):Void {
		var w = find(Msg.id(note, ObjC.sel("object")));
		if (w == null) return;
		var scale = w.scale, resized = w.measure();
		if (w.scale != scale) {
			var e = event;
			e.kind = ScaleChange;
			e.window = w.owner;
			dispatch(e);
		}
		if (resized) w.resized();
	}

	@:hxmc.callback static function didResize(self:Ptr, cmd:Ptr, note:Ptr):Void {
		var w = find(Msg.id(note, ObjC.sel("object")));
		if (w == null || !w.measure()) return;
		w.resized();
		// (a drag of the window's edge runs AppKit's own loop until the mouse is up, and
		// App.run draws nothing: a frame at the new size from here, as Win32Window's timer)
		if (onFrame != null && App.windows.length > 0 && Msg.b(w.window, ObjC.sel("inLiveResize"))) onFrame();
	}

	// while an edge is dragged, frames from a timer too: AppKit's loop runs
	// it (the common modes: its tracking mode's too), and the content moves
	// while the mouse holds still (as Win32Window's WM_TIMER)
	static var timer = Ptr.nil();

	@:hxmc.callback static function startResize(self:Ptr, cmd:Ptr, note:Ptr):Void {
		if (!timer.isNull()) return;
		var t = Msg.idFloatPtrPtrPtrBool(ObjC.cls("NSTimer"), ObjC.sel("timerWithTimeInterval:target:selector:userInfo:repeats:"), 1 / 120, delegate,
			ObjC.sel("liveFrame:"), Ptr.nil(), true);
		timer = Runtime.objc_retain(t);
		var modes = ObjC.str("kCFRunLoopCommonModes");
		Msg.vPtrPtr(Msg.id(ObjC.cls("NSRunLoop"), ObjC.sel("currentRunLoop")), ObjC.sel("addTimer:forMode:"), timer, modes);
		ObjC.release(modes);
	}

	@:hxmc.callback static function endResize(self:Ptr, cmd:Ptr, note:Ptr):Void {
		if (timer.isNull()) return;
		Msg.v(timer, ObjC.sel("invalidate"));
		Runtime.objc_release(timer);
		timer = Ptr.nil();
	}

	@:hxmc.callback static function liveFrame(self:Ptr, cmd:Ptr, t:Ptr):Void
		if (onFrame != null && App.windows.length > 0) onFrame();

	// waits for an event (left in the queue for poll), or seconds
	static function wait(seconds:Float) {
		if (app.isNull()) return;
		var pool = Runtime.objc_autoreleasePoolPush();
		var until = Msg.idFloat(ObjC.cls("NSDate"), ObjC.sel("dateWithTimeIntervalSinceNow:"), seconds);
		Msg.idIntPtrPtrBool(app, ObjC.sel("nextEventMatchingMask:untilDate:inMode:dequeue:"), -1, until, mode, false);
		Runtime.objc_autoreleasePoolPop(pool);
	}

	// dispatches the pending events
	static function poll(onFrame:Void->Void, onEvent:Event->Void) {
		CocoaWindow.onFrame = onFrame;
		CocoaWindow.onEvent = onEvent;
		for (w in open.copy())
			if (w.pending) w.resized();
		var past = Msg.id(ObjC.cls("NSDate"), ObjC.sel("distantPast"));
		while (!app.isNull()) {
			var ev = Msg.idIntPtrPtrBool(app, ObjC.sel("nextEventMatchingMask:untilDate:inMode:dequeue:"), -1, past, mode, true);
			if (ev.isNull()) break;
			var w = find(Msg.id(ev, ObjC.sel("window")));
			var type = Msg.i(ev, ObjC.sel("type")).toInt();
			// (a press on the title bar or an edge is AppKit's, a move or a resize:
			// its loop takes the release too, which the app would never see)
			if (w != null && (type == NS.LeftMouseDown || type == NS.RightMouseDown || type == NS.OtherMouseDown) && !w.inside(ev)) {
				Msg.vPtr(app, ObjC.sel("sendEvent:"), ev);
				continue;
			}
			var key = type == NS.KeyDown || type == NS.KeyUp;
			// (the menus' shortcuts first: Command and a key one of them has)
			if (type == NS.KeyDown && Msg.i(ev, ObjC.sel("modifierFlags")).toInt() & (1 << 20) != 0
				&& Msg.bPtr(Msg.id(app, ObjC.sel("mainMenu")), ObjC.sel("performKeyEquivalent:"), ev)) continue;
			if (w != null) w.translate(ev, type);
			if (w != null) w.composition();
			// (keys stay ours: unhandled, AppKit would beep at each)
			if (!key || w == null) Msg.vPtr(app, ObjC.sel("sendEvent:"), ev);
		}
		// (a composition changed outside a key: the input method's own window, a message)
		for (w in open.copy())
			w.composition();
	}

	// whether a press is on the content, not the window's frame
	function inside(ev:Ptr):Bool {
		var content = Msg.id(window, ObjC.sel("contentView"));
		var hit = Msg.idPoint(Msg.id(content, ObjC.sel("superview")), ObjC.sel("hitTest:"), Msg.point(ev, ObjC.sel("locationInWindow")));
		return !hit.isNull() && Msg.bPtr(hit, ObjC.sel("isDescendantOf:"), content);
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
			if (e.kind == MouseMove) hover(type != NS.MouseMoved || p.x >= 0 && p.y >= 0 && p.x < b.size.width && p.y < b.size.height);
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
			case 115: return 0xFF50; // Home
			case 119: return 0xFF57; // End
			case 116: return 0xFF55; // Page Up
			case 121: return 0xFF56; // Page Down
			case 110: return 0xFF67; // Menu (kVK_ContextualMenu)
			// (F1 to F12: their key codes; their characters are private ones)
			case 122: return 0xFFBE;
			case 120: return 0xFFBF;
			case 99: return 0xFFC0;
			case 118: return 0xFFC1;
			case 96: return 0xFFC2;
			case 97: return 0xFFC3;
			case 98: return 0xFFC4;
			case 100: return 0xFFC5;
			case 101: return 0xFFC6;
			case 109: return 0xFFC7;
			case 103: return 0xFFC8;
			case 111: return 0xFFC9;
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
