package helder.ui.native.appkit;

import helder.os.objc.*;
import helder.ui.*;
import helder.ui.native.*;
import hxmc.unsafe.*;

// NativeBackend on macOS: an NSWindow whose content view is flipped (y
// down, as the layout) and holds AppKit's controls (NSButton push and
// check box, NSTextField editable or a wrapping label, NSSlider,
// NSProgressIndicator) at the layout's frames. A target object of a class
// made at run time takes their actions (the control's tag is its handle),
// the text fields' controlTextDidChange: and the window's delegate calls.
// Measured with fittingSize (a label at a width: its preferred maximum
// layout width). The loop: NSApp's events, as helder.os's CocoaWindow.
class AppKitBackend implements NativeBackend implements NativeDriver {
	static var app = Ptr.nil();
	static var target = Ptr.nil();
	static var viewClass = Ptr.nil();
	static var mode = Ptr.nil();
	static var nextHandle = 1;
	static final backends = new Map<Int, AppKitBackend>();

	final views = new Map<Int, Ptr>();
	final nodes = new Map<Int, Node>();
	final kinds = new Map<Int, Int>();
	var host:Null<NativeHost>;
	var window = Ptr.nil();
	var content = Ptr.nil();
	var measurer = Ptr.nil();
	var windowId = 0;
	var width = 0.0;
	var height = 0.0;
	var open = false;
	var updating = false;

	public function new() {
		if (app.isNull()) start();
	}

	static function start() {
		helder.os.cocoa.CocoaWindow.AppKit.NSApplicationLoad();
		app = AkMsg.id(ObjC.cls("NSApplication"), ObjC.sel("sharedApplication"));
		AkMsg.idInt(app, ObjC.sel("setActivationPolicy:"), 0);
		AkMsg.v(app, ObjC.sel("finishLaunching"));
		mode = ObjC.str("kCFRunLoopDefaultMode");
		var cls = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcNativeTarget"), 0);
		Runtime.class_addMethod(cls, ObjC.sel("act:"), Callback.addr(onAction), Mem.cstr("v@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("controlTextDidChange:"), Callback.addr(onTextChange), Mem.cstr("v@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("windowShouldClose:"), Callback.addr(onShouldClose), Mem.cstr("c@:@"));
		Runtime.class_addMethod(cls, ObjC.sel("windowDidResize:"), Callback.addr(onResize), Mem.cstr("v@:@"));
		Runtime.objc_registerClassPair(cls);
		target = AkMsg.id(AkMsg.id(cls, ObjC.sel("alloc")), ObjC.sel("init"));
		viewClass = Runtime.objc_allocateClassPair(ObjC.cls("NSView"), Mem.cstr("HxmcFlippedView"), 0);
		Runtime.class_addMethod(viewClass, ObjC.sel("isFlipped"), Callback.addr(isFlipped), Mem.cstr("c@:"));
		Runtime.objc_registerClassPair(viewClass);
	}

	@:hxmc.callback static function isFlipped(self:Ptr, cmd:Ptr):Int
		return 1;

	static function rect(x:Float, y:Float, w:Float, h:Float, r:Ptr<CGRect>):CGRect {
		r.value.origin.x = x;
		r.value.origin.y = y;
		r.value.size.width = w;
		r.value.size.height = h;
		return r.value;
	}

	public function openWindow(title:String, w:Int, h:Int, host:NativeHost) {
		this.host = host;
		width = w;
		height = h;
		windowId = nextHandle++;
		backends.set(windowId, this);
		Arena.scoped(a -> {
			var r:Ptr<CGRect> = a.alloc(32);
			window = AkMsg.idRectIntIntBool(AkMsg.id(ObjC.cls("NSWindow"), ObjC.sel("alloc")), ObjC.sel("initWithContentRect:styleMask:backing:defer:"),
				rect(0, 0, w, h, r), 15, 2, false);
			content = AkMsg.idRect(AkMsg.id(viewClass, ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), rect(0, 0, w, h, r));
		});
		AkMsg.vBool(window, ObjC.sel("setReleasedWhenClosed:"), false);
		var t = ObjC.str(title);
		AkMsg.vPtr(window, ObjC.sel("setTitle:"), t);
		ObjC.release(t);
		AkMsg.vPtr(window, ObjC.sel("setContentView:"), content);
		AkMsg.vPtr(window, ObjC.sel("setDelegate:"), target);
		AkMsg.v(window, ObjC.sel("center"));
		AkMsg.vPtr(window, ObjC.sel("makeKeyAndOrderFront:"), Ptr.nil());
		AkMsg.vBool(app, ObjC.sel("activateIgnoringOtherApps:"), true);
		var empty = ObjC.str("");
		measurer = Runtime.objc_retain(AkMsg.idPtr(ObjC.cls("NSTextField"), ObjC.sel("wrappingLabelWithString:"), empty));
		ObjC.release(empty);
		open = true;
	}

	public function closeWindow() {
		if (!open) return;
		open = false;
		AkMsg.vPtr(window, ObjC.sel("setDelegate:"), Ptr.nil());
		AkMsg.v(window, ObjC.sel("close"));
	}

	public function windowWidth():Int
		return Math.round(width);

	public function windowHeight():Int
		return Math.round(height);

	public function create(n:Node):Int {
		var h = nextHandle++;
		var kind:Int = Std.isOfType(n, Control) ? (cast n : Control).kind : (ControlKind.Label : Int);
		var empty = ObjC.str("");
		var act = ObjC.sel("act:");
		var v = switch (cast kind : ControlKind) {
			case Button: AkMsg.idPtrPtrPtr(ObjC.cls("NSButton"), ObjC.sel("buttonWithTitle:target:action:"), empty, target, act);
			case CheckBox: AkMsg.idPtrPtrPtr(ObjC.cls("NSButton"), ObjC.sel("checkboxWithTitle:target:action:"), empty, target, act);
			case TextField:
				var f = AkMsg.idPtr(ObjC.cls("NSTextField"), ObjC.sel("textFieldWithString:"), empty);
				AkMsg.vPtr(f, ObjC.sel("setDelegate:"), target);
				AkMsg.vPtr(f, ObjC.sel("setTarget:"), target);
				AkMsg.vPtr(f, ObjC.sel("setAction:"), act);
				f;
			case Slider:
				var s = AkMsg.idFloat3PtrPtr(ObjC.cls("NSSlider"), ObjC.sel("sliderWithValue:minValue:maxValue:target:action:"), 0, 0, 1, target, act);
				AkMsg.vBool(s, ObjC.sel("setContinuous:"), true);
				s;
			case Progress:
				var p = AkMsg.id(AkMsg.id(ObjC.cls("NSProgressIndicator"), ObjC.sel("alloc")), ObjC.sel("init"));
				AkMsg.vBool(p, ObjC.sel("setIndeterminate:"), false);
				AkMsg.vFloat(p, ObjC.sel("setMinValue:"), 0);
				AkMsg.vFloat(p, ObjC.sel("setMaxValue:"), 1);
				p;
			case Label: AkMsg.idPtr(ObjC.cls("NSTextField"), ObjC.sel("wrappingLabelWithString:"), empty);
		}
		ObjC.release(empty);
		// (the factories' controls retained; alloc init's is owned already)
		if (kind != (ControlKind.Progress : Int)) Runtime.objc_retain(v);
		if (kind != (ControlKind.Progress : Int)) AkMsg.vInt(v, ObjC.sel("setTag:"), h);
		AkMsg.vPtr(content, ObjC.sel("addSubview:"), v);
		views.set(h, v);
		nodes.set(h, n);
		kinds.set(h, kind);
		backends.set(h, this);
		return h;
	}

	static function withString(s:String, f:Ptr->Void) {
		var ns = ObjC.str(s);
		f(ns);
		ObjC.release(ns);
	}

	public function update(h:Int, n:Node) {
		var v = views.get(h);
		if (v == null) return;
		updating = true;
		if (Std.isOfType(n, Control)) {
			var c:Control = cast n;
			switch c.kind {
				case Button:
					withString(c.text, s -> AkMsg.vPtr(v, ObjC.sel("setTitle:"), s));
				case CheckBox:
					withString(c.text, s -> AkMsg.vPtr(v, ObjC.sel("setTitle:"), s));
					AkMsg.vInt(v, ObjC.sel("setState:"), c.checked ? 1 : 0);
				case TextField:
					if (string(AkMsg.id(v, ObjC.sel("stringValue"))) != c.text) withString(c.text, s -> AkMsg.vPtr(v, ObjC.sel("setStringValue:"), s));
					withString(c.placeholder, s -> AkMsg.vPtr(v, ObjC.sel("setPlaceholderString:"), s));
				case Label:
					withString(c.text, s -> AkMsg.vPtr(v, ObjC.sel("setStringValue:"), s));
				case Slider:
					AkMsg.vFloat(v, ObjC.sel("setMinValue:"), c.min);
					AkMsg.vFloat(v, ObjC.sel("setMaxValue:"), c.max > c.min ? c.max : c.min + 1);
					AkMsg.vFloat(v, ObjC.sel("setDoubleValue:"), c.value);
				case Progress:
					AkMsg.vFloat(v, ObjC.sel("setDoubleValue:"), c.value < 0 ? 0 : c.value > 1 ? 1 : c.value);
			}
			if (c.kind != Progress) AkMsg.vBool(v, ObjC.sel("setEnabled:"), c.enabled);
		} else if (Std.isOfType(n, TextNode)) {
			var t:TextNode = cast n;
			withString(t.text, s -> AkMsg.vPtr(v, ObjC.sel("setStringValue:"), s));
			AkMsg.vPtr(v, ObjC.sel("setFont:"), font(t.font()));
			var col = t.textColor();
			AkMsg.vPtr(v, ObjC.sel("setTextColor:"), AkMsg.idFloat4(ObjC.cls("NSColor"), ObjC.sel("colorWithSRGBRed:green:blue:alpha:"), col.r / 255, col.g / 255,
				col.b / 255, col.a / 255));
			// (NSTextAlignment: left 0, right 1, center 2)
			var al = t.textAlign();
			AkMsg.vInt(v, ObjC.sel("setAlignment:"), al == Center ? 2 : al == Right ? 1 : 0);
		}
		updating = false;
	}

	// the font by family (else the system's), bold and italic through NSFontManager
	static function font(f:Font):Ptr {
		var name = ObjC.str(f.family);
		var nf = AkMsg.idPtrFloat(ObjC.cls("NSFont"), ObjC.sel("fontWithName:size:"), name, f.size);
		ObjC.release(name);
		if (nf.isNull()) nf = AkMsg.idFloat(ObjC.cls("NSFont"), ObjC.sel("systemFontOfSize:"), f.size);
		var fm = AkMsg.id(ObjC.cls("NSFontManager"), ObjC.sel("sharedFontManager"));
		// (NSFontTraitMask: italic 1, bold 2)
		if (f.weight >= 600) nf = AkMsg.idPtrInt(fm, ObjC.sel("convertFont:toHaveTrait:"), nf, 2);
		if (f.italic) nf = AkMsg.idPtrInt(fm, ObjC.sel("convertFont:toHaveTrait:"), nf, 1);
		return nf;
	}

	static function string(ns:Ptr):String {
		var s = ObjC.string(ns);
		return s == null ? "" : s;
	}

	public function place(h:Int, x:Float, y:Float, w:Float, ht:Float) {
		var v = views.get(h);
		if (v == null) return;
		Arena.scoped(a -> AkMsg.vRect(v, ObjC.sel("setFrame:"), rect(x, y, Math.max(1, w), Math.max(1, ht), a.alloc(32))));
	}

	public function destroy(h:Int) {
		var v = views.get(h);
		if (v == null) return;
		AkMsg.v(v, ObjC.sel("removeFromSuperview"));
		Runtime.objc_release(v);
		views.remove(h);
		nodes.remove(h);
		kinds.remove(h);
		backends.remove(h);
	}

	public function measure(c:Control, width:Float):Size {
		var v = views.get(c.handle);
		if (v == null) return new Size(0, 0);
		var s = AkMsg.size(v, ObjC.sel("fittingSize"));
		// (a field or slider has no width of its own: the layout's default)
		var w = c.kind == TextField || c.kind == Slider || c.kind == Progress ? Math.max(s.width, 150) : s.width;
		var h = c.kind == Progress ? Math.max(s.height, 16) : s.height;
		return new Size(Math.ceil(w), Math.ceil(h));
	}

	public function measureText(s:String, f:Font, maxWidth:Float):Size {
		withString(s, ns -> AkMsg.vPtr(measurer, ObjC.sel("setStringValue:"), ns));
		AkMsg.vPtr(measurer, ObjC.sel("setFont:"), font(f));
		AkMsg.vFloat(measurer, ObjC.sel("setPreferredMaxLayoutWidth:"), Math.isNaN(maxWidth) ? 100000 : maxWidth);
		var size = AkMsg.size(measurer, ObjC.sel("fittingSize"));
		return new Size(Math.ceil(size.width), Math.ceil(size.height));
	}

	public function pump(block:Bool):Bool {
		if (!open) return false;
		var pool = Runtime.objc_autoreleasePoolPush();
		var cls = ObjC.cls("NSDate");
		var first = true;
		while (open) {
			var until = first && block ? AkMsg.id(cls, ObjC.sel("distantFuture")) : AkMsg.id(cls, ObjC.sel("distantPast"));
			first = false;
			var ev = AkMsg.idIntPtrPtrBool(app, ObjC.sel("nextEventMatchingMask:untilDate:inMode:dequeue:"), -1, until, mode, true);
			if (ev.isNull()) break;
			AkMsg.vPtr(app, ObjC.sel("sendEvent:"), ev);
		}
		Runtime.objc_autoreleasePoolPop(pool);
		return open;
	}

	// --- the target's methods ---

	static function control(sender:Ptr):Null<{b:AppKitBackend, c:Control, h:Int}> {
		var h = AkMsg.i(sender, ObjC.sel("tag")).toInt();
		var b = backends.get(h);
		if (b == null || b.updating) return null;
		var n = b.nodes.get(h);
		return Std.isOfType(n, Control) ? {b: b, c: cast n, h: h} : null;
	}

	@:hxmc.callback static function onAction(self:Ptr, cmd:Ptr, sender:Ptr):Void {
		var x = control(sender);
		if (x == null) return;
		switch x.c.kind {
			case Button: x.c.platformClick();
			case CheckBox: x.c.platformChecked(AkMsg.i(sender, ObjC.sel("state")).toInt() == 1);
			case Slider: x.c.platformValue(AkMsg.f(sender, ObjC.sel("doubleValue")));
			case TextField: x.c.platformSubmit();
			case _:
		}
	}

	@:hxmc.callback static function onTextChange(self:Ptr, cmd:Ptr, note:Ptr):Void {
		var field = AkMsg.id(note, ObjC.sel("object"));
		var x = control(field);
		if (x != null && x.c.kind == TextField) x.c.platformText(string(AkMsg.id(field, ObjC.sel("stringValue"))));
	}

	static function ofWindow(w:Ptr):Null<AppKitBackend> {
		for (b in backends)
			if (b.window == w) return b;
		return null;
	}

	@:hxmc.callback static function onShouldClose(self:Ptr, cmd:Ptr, sender:Ptr):Int {
		var b = ofWindow(sender);
		if (b != null) {
			b.open = false;
			if (b.host != null) @:privateAccess b.host.windowClosed();
		}
		return 1;
	}

	@:hxmc.callback static function onResize(self:Ptr, cmd:Ptr, note:Ptr):Void {
		var b = ofWindow(AkMsg.id(note, ObjC.sel("object")));
		if (b == null) return;
		var r = AkMsg.rect(b.content, ObjC.sel("bounds"));
		b.width = r.size.width;
		b.height = r.size.height;
		if (b.host != null) @:privateAccess b.host.windowResized();
	}

	// --- NativeDriver: the controls' own calls ---

	public function click(h:Int)
		AkMsg.vPtr(views.get(h), ObjC.sel("performClick:"), Ptr.nil());

	// (setStringValue: is not typing: reported as the delegate reports an edit)
	public function type(h:Int, s:String) {
		var v = views.get(h);
		withString(s, ns -> AkMsg.vPtr(v, ObjC.sel("setStringValue:"), ns));
		var c:Control = cast nodes.get(h);
		c.platformText(s);
	}

	public function toggle(h:Int, on:Bool)
		if ((AkMsg.i(views.get(h), ObjC.sel("state")).toInt() == 1) != on) click(h);

	public function slide(h:Int, v:Float) {
		var s = views.get(h);
		AkMsg.vFloat(s, ObjC.sel("setDoubleValue:"), v);
		// (as a drag sends the slider's action)
		AkMsg.bPtrPtr(s, ObjC.sel("sendAction:to:"), ObjC.sel("act:"), target);
	}

	public function fieldText(h:Int):String
		return string(AkMsg.id(views.get(h), ObjC.sel("stringValue")));

	public function sliderValue(h:Int):Float
		return AkMsg.f(views.get(h), ObjC.sel("doubleValue"));

	public function allocation(h:Int):Array<Int> {
		var v = views.get(h);
		if (v == null) return [];
		var r = AkMsg.rect(v, ObjC.sel("frame"));
		return [Math.round(r.origin.x), Math.round(r.origin.y), Math.round(r.size.width), Math.round(r.size.height)];
	}

	// the content view drawn into a bitmap, saved as PNG (NSBitmapImageFileTypePNG: 4)
	public function screenshot(path:String):Bool {
		var b = AkMsg.rect(content, ObjC.sel("bounds"));
		var rep = Arena.scopedValue(a -> AkMsg.idRect(content, ObjC.sel("bitmapImageRepForCachingDisplayInRect:"), rect(0, 0, b.size.width, b.size.height, a.alloc(32))));
		if (rep.isNull()) return false;
		Arena.scoped(a -> AkMsg.vRectPtr(content, ObjC.sel("cacheDisplayInRect:toBitmapImageRep:"), rect(0, 0, b.size.width, b.size.height, a.alloc(32)), rep));
		var data = AkMsg.idIntPtr(rep, ObjC.sel("representationUsingType:properties:"), 4, AkMsg.id(ObjC.cls("NSDictionary"), ObjC.sel("dictionary")));
		if (data.isNull()) return false;
		var p = ObjC.str(path);
		var ok = AkMsg.bPtrBool(data, ObjC.sel("writeToFile:atomically:"), p, true);
		ObjC.release(p);
		return ok;
	}
}
