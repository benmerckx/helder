package helder.ui.draw;

import helder.os.objc.*;
import helder.ui.*;
import helder.ui.native.appkit.AkMsg;
import helder.ui.native.appkit.AppKitBackend;
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
// NSSecureTextField (the field made again when that changes). A text area:
// an NSTextView (plain text, no inset or line padding, the drawn area's
// geometry) in a borderless NSScrollView, the same delegate hearing its
// textDidChange:, its editing begun and ended, and Tab, Shift+Tab and
// Escape (textView:doCommandBySelector:) left to the program. Menus: an NSMenu popped up at the next poll (its own loop
// until chosen or dismissed), each item's tag its id, its action the
// delegate's hxmcMenuPick:, its shortcut a key equivalent (a character's,
// with its modifiers; Mod: Command). The menu bar's menus: inserted after
// the application's menu, their items' action hxmcBarPick:, queued (their
// key equivalents taken by the menu bar before the window, as the
// system's).
class MacViews implements PlatformViews {
	static var delegateClass = Ptr.nil();
	static var delegate = Ptr.nil();
	static final editors:Array<MacEditor> = [];

	final view:Ptr;
	final ui:Ui;
	final queue:Array<{e:MacEditor, kind:Int, key:Int, mods:Int}> = [];
	// (a menu asked for: shown at the next poll; the item chosen in it)
	var pending:Null<{items:Array<PlatformMenuItem>, x:Float, y:Float, chosen:Int->Void}> = null;
	static var picked = -1;
	// (the menus put in the menu bar, and what a choice there calls)
	var barItems:Array<Ptr> = [];
	var barChosen:Null<Int->Void> = null;
	static var current:Null<MacViews> = null;
	// (the menu up, while it is: what a test acts on)
	static var shown = Ptr.nil();

	public function new(view:Ptr, ui:Ui) {
		this.view = view;
		this.ui = ui;
		if (delegateClass.isNull()) {
			// (hxmc dev's host: the class an earlier build made, its methods this build's)
			var d = ObjC.cls("HxmcFieldDelegate"), fresh = d.isNull();
			if (fresh) d = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcFieldDelegate"), 0);
			Runtime.class_replaceMethod(d, ObjC.sel("controlTextDidChange:"), Callback.addr(changed), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(d, ObjC.sel("controlTextDidBeginEditing:"), Callback.addr(began), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(d, ObjC.sel("controlTextDidEndEditing:"), Callback.addr(ended), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(d, ObjC.sel("control:textView:doCommandBySelector:"), Callback.addr(command), Mem.cstr("c@:@@:"));
			Runtime.class_replaceMethod(d, ObjC.sel("hxmcMenuPick:"), Callback.addr(pick), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(d, ObjC.sel("hxmcBarPick:"), Callback.addr(barPick), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(d, ObjC.sel("textDidChange:"), Callback.addr(changed), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(d, ObjC.sel("textDidBeginEditing:"), Callback.addr(began), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(d, ObjC.sel("textDidEndEditing:"), Callback.addr(ended), Mem.cstr("v@:@"));
			Runtime.class_replaceMethod(d, ObjC.sel("textView:doCommandBySelector:"), Callback.addr(areaCommand), Mem.cstr("c@:@:"));
			if (fresh) Runtime.objc_registerClassPair(d);
			delegateClass = d;
			delegate = Msg.id(Msg.id(d, ObjC.sel("alloc")), ObjC.sel("init"));
		}
	}

	// (the window's content view: the fields over the drawn view)
	function content():Ptr
		return Msg.id(Msg.id(view, ObjC.sel("window")), ObjC.sel("contentView"));

	public function editor(multiline:Bool):Null<PlatformEditor> {
		if (multiline) {
			var e = area();
			editors.push(e);
			return e;
		}
		var e = new MacEditor(this, field(false));
		editors.push(e);
		return e;
	}

	// (a text area: an NSTextView in an NSScrollView, hidden, in the content view)
	function area():MacAreaEditor {
		var make = (cls:Ptr) -> Arena.scopedValue(a -> {
			var r = a.make(CGRect);
			r.value.size.width = 10;
			r.value.size.height = 10;
			Msg.idRect(Msg.id(cls, ObjC.sel("alloc")), ObjC.sel("initWithFrame:"), r.value);
		});
		var sv = make(ObjC.cls("NSScrollView")), tv = make(ObjC.cls("NSTextView"));
		Msg.vInt(sv, ObjC.sel("setBorderType:"), 0); // NSNoBorder
		Msg.vBool(sv, ObjC.sel("setDrawsBackground:"), false);
		Msg.vBool(sv, ObjC.sel("setHasVerticalScroller:"), true);
		Msg.vBool(sv, ObjC.sel("setAutohidesScrollers:"), true);
		Msg.vBool(sv, ObjC.sel("setHidden:"), true);
		Msg.vBool(tv, ObjC.sel("setRichText:"), false);
		Msg.vBool(tv, ObjC.sel("setDrawsBackground:"), false);
		Msg.vInt(tv, ObjC.sel("setFocusRingType:"), 1);
		Msg.vBool(tv, ObjC.sel("setVerticallyResizable:"), true);
		Msg.vBool(tv, ObjC.sel("setHorizontallyResizable:"), false);
		Msg.vInt(tv, ObjC.sel("setAutoresizingMask:"), 2); // NSViewWidthSizable
		Arena.scoped(a -> {
			var z = a.make(CGSize);
			Msg.vSize(tv, ObjC.sel("setTextContainerInset:"), z.value);
			z.value.width = 1e7;
			z.value.height = 1e7;
			Msg.vSize(tv, ObjC.sel("setMaxSize:"), z.value);
		});
		var tc = Msg.id(tv, ObjC.sel("textContainer"));
		Msg.vFloat(tc, ObjC.sel("setLineFragmentPadding:"), 0);
		Msg.vBool(tc, ObjC.sel("setWidthTracksTextView:"), true);
		Msg.vPtr(tv, ObjC.sel("setDelegate:"), delegate);
		Msg.vPtr(sv, ObjC.sel("setDocumentView:"), tv);
		ObjC.release(tv);
		Msg.vPtr(content(), ObjC.sel("addSubview:"), sv);
		return new MacAreaEditor(this, sv, tv);
	}

	// (a field, hidden, in the content view: a password's NSSecureTextField)
	@:allow(helder.ui.draw.MacEditor) function field(secure:Bool):Ptr {
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

	@:allow(helder.ui.draw.MacEditor) function push(e:MacEditor, kind:Int, key = 0, mods = 0) {
		queue.push({e: e, kind: kind, key: key, mods: mods});
		ui.requestFrame();
	}

	public function menu(items:Array<PlatformMenuItem>, x:Float, y:Float, chosen:Int->Void):Bool {
		if (pending != null) pending.chosen(-1);
		pending = {items: items, x: x, y: y, chosen: chosen};
		ui.requestFrame();
		return true;
	}

	// (hxmc dev's host, at a hand-over: the editors and the menu bar's items
	// gone with this build, whose code they call; the next build makes its own)
	public function dispose() {
		for (e in editors.copy())
			if (@:privateAccess e.views == this) e.dispose();
		pending = null;
		menuBar([], _ -> {});
		barChosen = null;
		if (current == this) current = null;
	}

	public function menuBar(menus:Array<PlatformMenuItem>, chosen:Int->Void):Bool {
		var main = Msg.id(Msg.id(ObjC.cls("NSApplication"), ObjC.sel("sharedApplication")), ObjC.sel("mainMenu"));
		if (main.isNull()) return false;
		for (it in barItems) {
			Msg.vPtr(main, ObjC.sel("removeItem:"), it);
			ObjC.release(it);
		}
		barItems = [];
		barChosen = chosen;
		current = this;
		for (k in 0...menus.length) {
			var m = menus[k], sub = nsMenu(m.items ?? [], ObjC.sel("hxmcBarPick:"), m.label);
			var item = Msg.id(Msg.id(ObjC.cls("NSMenuItem"), ObjC.sel("alloc")), ObjC.sel("init"));
			Msg.vPtr(item, ObjC.sel("setSubmenu:"), sub);
			ObjC.release(sub);
			AkMsg.vPtrInt(main, ObjC.sel("insertItem:atIndex:"), item, 1 + k);
			barItems.push(item);
		}
		return true;
	}

	// (an NSMenu of the items: enabled as given, checked as NSControlStateValueOn)
	static function nsMenu(items:Array<PlatformMenuItem>, ?action:Ptr, title = ""):Ptr {
		if (action == null) action = ObjC.sel("hxmcMenuPick:");
		var t = ObjC.str(title);
		var m = Msg.idPtr(Msg.id(ObjC.cls("NSMenu"), ObjC.sel("alloc")), ObjC.sel("initWithTitle:"), t);
		Msg.vBool(m, ObjC.sel("setAutoenablesItems:"), false);
		for (it in items) {
			if (it.separator == true) {
				Msg.vPtr(m, ObjC.sel("addItem:"), Msg.id(ObjC.cls("NSMenuItem"), ObjC.sel("separatorItem")));
				continue;
			}
			var k = it.keys, equivalent = k != null && k.key > 32 && k.key < 127 ? String.fromCharCode(k.key).toLowerCase() : "";
			var title = ObjC.str(it.label), e = ObjC.str(equivalent);
			var item = Msg.idPtrPtrPtr(Msg.id(ObjC.cls("NSMenuItem"), ObjC.sel("alloc")), ObjC.sel("initWithTitle:action:keyEquivalent:"), title,
				it.items == null ? action : Ptr.nil(), e);
			ObjC.release(title);
			ObjC.release(e);
			Msg.vPtr(item, ObjC.sel("setTarget:"), delegate);
			Msg.vInt(item, ObjC.sel("setTag:"), it.id);
			Msg.vBool(item, ObjC.sel("setEnabled:"), it.disabled != true);
			// (NSEventModifierFlagShift 1 << 17, Control 1 << 18, Option 1 << 19, Command 1 << 20)
			if (equivalent != "")
				Msg.vInt(item, ObjC.sel("setKeyEquivalentModifierMask:"), (k.mod || k.mods & Key.MOD_META != 0 ? 1 << 20 : 0)
					| (k.mods & Key.MOD_SHIFT != 0 ? 1 << 17 : 0) | (k.mods & Key.MOD_CONTROL != 0 ? 1 << 18 : 0) | (k.mods & Key.MOD_ALT != 0 ? 1 << 19 : 0));
			if (it.checked == true) Msg.vInt(item, ObjC.sel("setState:"), 1);
			if (it.items != null) {
				var sub = nsMenu(it.items, action, it.label);
				Msg.vPtr(item, ObjC.sel("setSubmenu:"), sub);
				ObjC.release(sub);
			}
			Msg.vPtr(m, ObjC.sel("addItem:"), item);
			ObjC.release(item);
		}
		ObjC.release(t);
		return m;
	}

	public function poll() {
		var i = 0;
		while (i < queue.length)
			if (queue[i].kind == 5) {
				var q = queue.splice(i, 1)[0];
				if (barChosen != null) barChosen(q.key);
			} else i++;
		if (pending != null) {
			var p = pending;
			pending = null;
			var m = nsMenu(p.items);
			picked = -1;
			// (the view's points, y up)
			var b = Msg.rect(view, ObjC.sel("bounds")), flipped = Msg.b(view, ObjC.sel("isFlipped"));
			Arena.scoped(a -> {
				var pt = a.make(helder.os.objc.CGPoint);
				pt.value.x = p.x;
				pt.value.y = flipped ? p.y : b.size.height - p.y;
				shown = m;
				AkMsg.bPtrPointPtr(m, ObjC.sel("popUpMenuPositioningItem:atLocation:inView:"), Ptr.nil(), pt.value, view);
				shown = Ptr.nil();
			});
			ObjC.release(m);
			p.chosen(picked);
		}
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

	@:hxmc.callback static function pick(self:Ptr, cmd:Ptr, item:Ptr)
		picked = Msg.i(item, ObjC.sel("tag")).toInt();

	// (a menu bar's item chosen: queued, a frame asked for)
	@:hxmc.callback static function barPick(self:Ptr, cmd:Ptr, item:Ptr)
		if (current != null) current.push(null, 5, Msg.i(item, ObjC.sel("tag")).toInt());

	// (a text area's commands: Tab, Shift+Tab and Escape left to the program)
	@:hxmc.callback static function areaCommand(self:Ptr, cmd:Ptr, textView:Ptr, sel:Ptr):Int {
		var e = of(textView);
		if (e == null) return 0;
		var key = 0, mods = 0;
		if (sel == ObjC.sel("insertTab:")) key = Key.TAB else if (sel == ObjC.sel("insertBacktab:")) {
			key = Key.TAB;
			mods = Key.MOD_SHIFT;
		} else if (sel == ObjC.sel("cancelOperation:")) key = Key.ESCAPE;
		if (key == 0) return 0;
		@:privateAccess e.views.push(e, 4, key, mods);
		return 1;
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

// (a text area's editor: its NSTextView the field, placed by its scroll view)
class MacAreaEditor extends MacEditor {
	final scroll:Ptr;

	public function new(views:MacViews, scroll:Ptr, textView:Ptr) {
		super(views, textView);
		this.scroll = scroll;
	}

	override function text():String {
		var s = ObjC.string(Msg.id(field, ObjC.sel("string")));
		return s == null ? "" : s;
	}

	override public function setText(text:String, start:Int, end:Int) {
		var s = ObjC.str(text);
		Msg.vPtr(field, ObjC.sel("setString:"), s);
		ObjC.release(s);
	}

	override public function place(x:Float, y:Float, width:Float, height:Float, shown:Bool) {
		var c = @:privateAccess views.content(), b = Msg.rect(c, ObjC.sel("bounds"));
		Arena.scoped(a -> {
			var r = a.make(CGRect);
			r.value.origin.x = x;
			r.value.origin.y = b.size.height - y - height;
			r.value.size.width = width;
			r.value.size.height = height;
			Msg.vRect(scroll, ObjC.sel("setFrame:"), r.value);
		});
		Msg.vBool(scroll, ObjC.sel("setHidden:"), !shown);
	}

	// (no placeholder of its own: the drawn one shows while it is empty)
	override public function setStyle(font:Font, color:Color, background:Color, placeholder:String, placeholderColor:Color, align:TextAlign, secret:Bool) {
		Msg.vPtr(field, ObjC.sel("setFont:"), @:privateAccess AppKitBackend.font(font));
		Msg.vPtr(field, ObjC.sel("setTextColor:"), AkMsg.idFloat4(ObjC.cls("NSColor"), ObjC.sel("colorWithSRGBRed:green:blue:alpha:"), color.r / 255,
			color.g / 255, color.b / 255, color.a / 255));
		Msg.vInt(field, ObjC.sel("setAlignment:"), align == Center ? 2 : align == Right ? 1 : align == Justify ? 3 : 0);
	}

	override public function dispose() {
		@:privateAccess MacViews.editors.remove(this);
		if (editing()) Msg.bPtr(Msg.id(scroll, ObjC.sel("window")), ObjC.sel("makeFirstResponder:"), Ptr.nil());
		Msg.vPtr(field, ObjC.sel("setDelegate:"), Ptr.nil());
		Msg.v(scroll, ObjC.sel("removeFromSuperview"));
		ObjC.release(scroll);
		listener = null;
	}
}
