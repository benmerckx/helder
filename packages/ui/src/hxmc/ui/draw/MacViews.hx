package hxmc.ui.draw;

import hxmc.os.objc.*;
import hxmc.ui.*;
import hxmc.ui.native.appkit.AkMsg;
import hxmc.ui.native.appkit.AppKitBackend;
import hxmc.unsafe.*;

// macOS's own views over a window (Ui.platform there): one-line text
// editors, NSTextFields borderless and transparent over the window's
// content view (above the drawn one), placed where their nodes are laid
// out (points: the layout's pixels; the content view's y up). One delegate
// (HxmcFieldDelegate, made at first use) hears them all: an edit
// (controlTextDidChange:), editing begun and ended (the focus), and the
// commands they leave to the program (control:textView:doCommandBySelector:
// insertTab:, insertBacktab:, cancelOperation:, insertNewline:, moveUp:,
// moveDown:); each queued and a frame asked for. In the node's font (by
// family, else the system's), colour and alignment; a password's an
// NSSecureTextField (the field made again when that changes); a text area
// stays drawn.
class MacViews implements PlatformViews {
	static var delegateClass = Ptr.nil();
	static var delegate = Ptr.nil();
	static final editors:Array<MacEditor> = [];

	final view:Ptr;
	final ui:Ui;
	final queue:Array<{e:MacEditor, kind:Int, key:Int, mods:Int}> = [];

	public function new(view:Ptr, ui:Ui) {
		this.view = view;
		this.ui = ui;
		if (delegateClass.isNull()) {
			var d = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcFieldDelegate"), 0);
			Runtime.class_addMethod(d, ObjC.sel("controlTextDidChange:"), Callback.addr(changed), Mem.cstr("v@:@"));
			Runtime.class_addMethod(d, ObjC.sel("controlTextDidBeginEditing:"), Callback.addr(began), Mem.cstr("v@:@"));
			Runtime.class_addMethod(d, ObjC.sel("controlTextDidEndEditing:"), Callback.addr(ended), Mem.cstr("v@:@"));
			Runtime.class_addMethod(d, ObjC.sel("control:textView:doCommandBySelector:"), Callback.addr(command), Mem.cstr("c@:@@:"));
			Runtime.objc_registerClassPair(d);
			delegateClass = d;
			delegate = Msg.id(Msg.id(d, ObjC.sel("alloc")), ObjC.sel("init"));
		}
	}

	// (the window's content view: the fields over the drawn view)
	function content():Ptr
		return Msg.id(Msg.id(view, ObjC.sel("window")), ObjC.sel("contentView"));

	public function editor(multiline:Bool):Null<PlatformEditor> {
		if (multiline) return null;
		var e = new MacEditor(this, field(false));
		editors.push(e);
		return e;
	}

	// (a field, hidden, in the content view: a password's NSSecureTextField)
	@:allow(hxmc.ui.draw.MacEditor) function field(secure:Bool):Ptr {
		var f = Arena.scopedValue(a -> {
			var r = a.make(CGRect);
			r.value.size.width = 10;
			r.value.size.height = 10;
			Msg.idRect(Msg.id((secure ? ObjC.cls("NSSecureTextField") : ObjC.cls("NSTextField")), ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), r.value);
		});
		Msg.vBool(f, ObjC.sel("setBordered:"), false);
		Msg.vBool(f, ObjC.sel("setBezeled:"), false);
		Msg.vBool(f, ObjC.sel("setDrawsBackground:"), false);
		Msg.vInt(f, ObjC.sel("setFocusRingType:"), 1); // NSFocusRingTypeNone
		Msg.vBool(f, ObjC.sel("setHidden:"), true);
		Msg.vPtr(f, ObjC.sel("setDelegate:"), delegate);
		Msg.vPtr(content(), ObjC.sel("addSubview:"), f);
		return f;
	}

	@:allow(hxmc.ui.draw.MacEditor) function push(e:MacEditor, kind:Int, key = 0, mods = 0) {
		queue.push({e: e, kind: kind, key: key, mods: mods});
		ui.requestFrame();
	}

	public function poll() {
		while (queue.length > 0) {
			var q = queue.shift(), e = q.e, l = e.listener;
			if (l == null) continue;
			switch q.kind {
				case 1:
					var t = @:privateAccess e.text();
					l.editorEdited(t, t.length, t.length);
				case 2:
					l.editorFocused(true);
				case 3:
					l.editorFocused(false);
				case 4:
					l.editorKey(q.key, q.mods);
				case _:
			}
		}
	}

	// (a notification's field: its editor)
	static function of(field:Ptr):Null<MacEditor> {
		for (e in editors)
			if (@:privateAccess e.field == field) return e;
		return null;
	}

	@:hxmc.callback static function changed(self:Ptr, cmd:Ptr, note:Ptr) {
		var e = of(Msg.id(note, ObjC.sel("object")));
		if (e != null) @:privateAccess e.views.push(e, 1);
	}

	@:hxmc.callback static function began(self:Ptr, cmd:Ptr, note:Ptr) {
		var e = of(Msg.id(note, ObjC.sel("object")));
		if (e != null && !@:privateAccess e.focusing) @:privateAccess e.views.push(e, 2);
	}

	@:hxmc.callback static function ended(self:Ptr, cmd:Ptr, note:Ptr) {
		var e = of(Msg.id(note, ObjC.sel("object")));
		if (e != null && !@:privateAccess e.focusing) @:privateAccess e.views.push(e, 3);
	}

	@:hxmc.callback static function command(self:Ptr, cmd:Ptr, control:Ptr, textView:Ptr, sel:Ptr):Int {
		var e = of(control);
		if (e == null) return 0;
		var key = 0, mods = 0;
		if (sel == ObjC.sel("insertTab:")) key = Key.TAB else if (sel == ObjC.sel("insertBacktab:")) {
			key = Key.TAB;
			mods = Key.MOD_SHIFT;
		} else if (sel == ObjC.sel("cancelOperation:")) key = Key.ESCAPE else if (sel == ObjC.sel("insertNewline:")) key = Key.ENTER else
			if (sel == ObjC.sel("moveUp:")) key = Key.UP else if (sel == ObjC.sel("moveDown:")) key = Key.DOWN;
		if (key == 0) return 0;
		@:privateAccess e.views.push(e, 4, key, mods);
		return 1;
	}
}

class MacEditor implements PlatformEditor {
	final views:MacViews;
	var field:Ptr;
	var secure = false;
	var focusing = false;

	public var listener(default, null):Null<PlatformEditorListener> = null;

	public function new(views:MacViews, field:Ptr) {
		this.views = views;
		this.field = field;
	}

	public function listen(l:PlatformEditorListener)
		listener = l;

	function text():String {
		var s = ObjC.string(Msg.id(field, ObjC.sel("stringValue")));
		return s == null ? "" : s;
	}

	public function setText(text:String, start:Int, end:Int) {
		var s = ObjC.str(text);
		Msg.vPtr(field, ObjC.sel("setStringValue:"), s);
		ObjC.release(s);
	}

	public function place(x:Float, y:Float, width:Float, height:Float, shown:Bool) {
		var c = @:privateAccess views.content(), b = Msg.rect(c, ObjC.sel("bounds"));
		Arena.scoped(a -> {
			var r = a.make(CGRect);
			r.value.origin.x = x;
			r.value.origin.y = b.size.height - y - height;
			r.value.size.width = width;
			r.value.size.height = height;
			Msg.vRect(field, ObjC.sel("setFrame:"), r.value);
		});
		Msg.vBool(field, ObjC.sel("setHidden:"), !shown);
	}

	public function setStyle(font:Font, color:Color, background:Color, placeholder:String, placeholderColor:Color, align:TextAlign, secret:Bool) {
		if (secret != secure) remake(secret);
		Msg.vPtr(field, ObjC.sel("setFont:"), @:privateAccess AppKitBackend.font(font));
		Msg.vPtr(field, ObjC.sel("setTextColor:"), AkMsg.idFloat4(ObjC.cls("NSColor"), ObjC.sel("colorWithSRGBRed:green:blue:alpha:"), color.r / 255,
			color.g / 255, color.b / 255, color.a / 255));
		// (NSTextAlignment: left 0, right 1, center 2, justified 3)
		Msg.vInt(field, ObjC.sel("setAlignment:"), align == Center ? 2 : align == Right ? 1 : align == Justify ? 3 : 0);
		var p = ObjC.str(placeholder);
		Msg.vPtr(field, ObjC.sel("setPlaceholderString:"), p);
		ObjC.release(p);
	}

	// (the field made again as a password's or not: its text, frame and
	// visibility kept, and the focus if it had it)
	function remake(secret:Bool) {
		var old = field, had = editing(), w = Msg.id(old, ObjC.sel("window"));
		var f = views.field(secret);
		Msg.vPtr(f, ObjC.sel("setStringValue:"), Msg.id(old, ObjC.sel("stringValue")));
		Msg.vRect(f, ObjC.sel("setFrame:"), Msg.rect(old, ObjC.sel("frame")));
		Msg.vBool(f, ObjC.sel("setHidden:"), Msg.b(old, ObjC.sel("isHidden")));
		focusing = true;
		if (had) Msg.bPtr(w, ObjC.sel("makeFirstResponder:"), Ptr.nil());
		Msg.vPtr(old, ObjC.sel("setDelegate:"), Ptr.nil());
		Msg.v(old, ObjC.sel("removeFromSuperview"));
		ObjC.release(old);
		field = f;
		secure = secret;
		if (had) Msg.bPtr(w, ObjC.sel("makeFirstResponder:"), f);
		focusing = false;
	}

	public function focus(on:Bool) {
		var w = Msg.id(field, ObjC.sel("window"));
		if (w.isNull()) return;
		focusing = true;
		if (on) Msg.bPtr(w, ObjC.sel("makeFirstResponder:"), field) else if (editing()) Msg.bPtr(w, ObjC.sel("makeFirstResponder:"), Ptr.nil());
		focusing = false;
	}

	// (the field editing: the window's first responder its field editor, whose delegate it is)
	function editing():Bool {
		var w = Msg.id(field, ObjC.sel("window")), r = Msg.id(w, ObjC.sel("firstResponder"));
		return r == field || (!r.isNull() && Msg.id(r, ObjC.sel("delegate")) == field);
	}

	public function dispose() {
		@:privateAccess MacViews.editors.remove(this);
		if (editing()) Msg.bPtr(Msg.id(field, ObjC.sel("window")), ObjC.sel("makeFirstResponder:"), Ptr.nil());
		Msg.vPtr(field, ObjC.sel("setDelegate:"), Ptr.nil());
		Msg.v(field, ObjC.sel("removeFromSuperview"));
		ObjC.release(field);
		listener = null;
	}
}
