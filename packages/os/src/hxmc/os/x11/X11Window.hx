package hxmc.os.x11;

import hxmc.os.Event;
import hxmc.os.x11.Xlib;
import hxmc.unsafe.*;

// hxmc.os.Window on X11: one Display connection for the process, opened
// with the first window; WM_DELETE_WINDOW turns the close button into a
// Close event.
@:allow(hxmc.os)
class X11Window {
	static var display = Ptr.nil();
	static var wmDelete:Int64 = 0;
	// one XEvent buffer, and the Event dispatched from it
	static var xev:Ptr = Ptr.nil();
	static final event = new Event();
	static final open:Array<X11Window> = [];
	// the clipboard: the atoms, the text this process owns it with (null: it
	// does not), the reads waiting for SelectionNotify
	static var CLIPBOARD:Int64 = 0;
	static var UTF8_STRING:Int64 = 0;
	static var TARGETS:Int64 = 0;
	static var HXMC_CLIPBOARD:Int64 = 0;
	static var clipboardText:Null<String> = null;
	static final clipboardReads:Array<{window:X11Window, callback:Null<String>->Void}> = [];
	// the cursors made (by Cursor; 0: not yet)
	static final cursors:Array<Int64> = [];

	final owner:Window;
	final id:Int64;
	final surface:Surface;

	function new(owner:Window, title:String, width:Int, height:Int) {
		this.owner = owner;
		if (display.isNull()) connect();
		var screen = Xlib.XDefaultScreen(display);
		var black = Xlib.XBlackPixel(display, screen);
		id = Xlib.XCreateSimpleWindow(display, Xlib.XRootWindow(display, screen), 0, 0, width, height, 0, black, black);
		Arena.scoped(a -> {
			Xlib.XStoreName(display, id, a.cstring(title));
			var atoms:Ptr<Int64> = a.alloc(8);
			atoms.value = wmDelete;
			Xlib.XSetWMProtocols(display, id, atoms, 1);
		});
		Xlib.XSelectInput(display, id, (X.KeyPressMask | X.KeyReleaseMask | X.ButtonPressMask | X.ButtonReleaseMask | X.PointerMotionMask
			| X.StructureNotifyMask | X.ExposureMask : Int64));
		Xlib.XMapWindow(display, id);
		Xlib.XFlush(display);
		surface = new Surface(X11, display, Ptr.ofI64(id), width, height);
		open.push(this);
	}

	static function connect() {
		display = Xlib.XOpenDisplay(Ptr.nil());
		if (display.isNull()) throw "hxmc.os: cannot open the X display (DISPLAY=" + Sys.getEnv("DISPLAY") + ")";
		wmDelete = Xlib.XInternAtom(display, Mem.cstr("WM_DELETE_WINDOW"), 0);
		CLIPBOARD = Xlib.XInternAtom(display, Mem.cstr("CLIPBOARD"), 0);
		UTF8_STRING = Xlib.XInternAtom(display, Mem.cstr("UTF8_STRING"), 0);
		TARGETS = Xlib.XInternAtom(display, Mem.cstr("TARGETS"), 0);
		HXMC_CLIPBOARD = Xlib.XInternAtom(display, Mem.cstr("HXMC_CLIPBOARD"), 0);
		xev = LibC.malloc((X.EVENT_SIZE : Int64));
	}

	function destroy() {
		open.remove(this);
		Xlib.XDestroyWindow(display, id);
		Xlib.XFlush(display);
		for (r in clipboardReads.copy())
			if (r.window == this) {
				clipboardReads.remove(r);
				r.callback(null);
			}
		if (open.length == 0) {
			// (the cursors and the selection go with the connection)
			cursors.resize(0);
			clipboardText = null;
			Xlib.XCloseDisplay(display);
			LibC.free(xev);
			display = Ptr.nil();
		}
	}

	// (cursorfont.h: XC_left_ptr, XC_hand2, XC_xterm, XC_crosshair, XC_fleur,
	// XC_X_cursor, XC_sb_h_double_arrow, XC_sb_v_double_arrow)
	function setCursor(c:Cursor) {
		var i:Int = c;
		while (cursors.length <= i)
			cursors.push(0);
		if (cursors[i] == 0) cursors[i] = Xlib.XCreateFontCursor(display, [68, 60, 152, 34, 52, 0, 108, 116][i]);
		Xlib.XDefineCursor(display, id, cursors[i]);
		Xlib.XFlush(display);
	}

	// owns CLIPBOARD with text (answering SelectionRequest from then on)
	function writeClipboard(text:String) {
		clipboardText = text;
		Xlib.XSetSelectionOwner(display, CLIPBOARD, id, 0);
		if (Xlib.XGetSelectionOwner(display, CLIPBOARD) != id) clipboardText = null;
		Xlib.XFlush(display);
	}

	// the text this process owns the clipboard with, else the owner's
	// (converted to UTF8_STRING into a property of this window: SelectionNotify)
	function readClipboard(callback:Null<String>->Void) {
		if (clipboardText != null && Xlib.XGetSelectionOwner(display, CLIPBOARD) == id) {
			callback(clipboardText);
			return;
		}
		if (Xlib.XGetSelectionOwner(display, CLIPBOARD) == 0) {
			callback(null);
			return;
		}
		clipboardReads.push({window: this, callback: callback});
		Xlib.XConvertSelection(display, CLIPBOARD, UTF8_STRING, HXMC_CLIPBOARD, id, 0);
		Xlib.XFlush(display);
	}

	// another client asks for the selection this process owns: its text into
	// the property it names (UTF-8 for UTF8_STRING, Latin-1 for STRING; the
	// two for TARGETS), then SelectionNotify (property 0: refused)
	static function answerSelection(r:Ptr<XSelectionRequestEvent>) {
		var property = r.value.property == 0 ? r.value.target : r.value.property;
		var ok = clipboardText != null && r.value.selection == CLIPBOARD;
		if (ok) Arena.scoped(a -> {
			if (r.value.target == TARGETS) {
				var atoms:Ptr<Int64> = a.alloc(24);
				atoms[0] = TARGETS;
				atoms[1] = UTF8_STRING;
				atoms[2] = X.XA_STRING;
				Xlib.XChangeProperty(display, r.value.requestor, property, X.XA_ATOM, 32, X.PropModeReplace, atoms, 3);
			} else if (r.value.target == UTF8_STRING || r.value.target == X.XA_STRING) {
				var b = r.value.target == UTF8_STRING ? haxe.io.Bytes.ofString(clipboardText) : latin1(clipboardText);
				Xlib.XChangeProperty(display, r.value.requestor, property, r.value.target, 8, X.PropModeReplace, a.copyBytes(b), b.length);
			} else ok = false;
			var raw = a.alloc(X.EVENT_SIZE);
			var n:Ptr<XSelectionEvent> = raw;
			n.value.type = X.SelectionNotify;
			n.value.display = display;
			n.value.requestor = r.value.requestor;
			n.value.selection = r.value.selection;
			n.value.target = r.value.target;
			n.value.property = ok ? property : 0;
			n.value.time = r.value.time;
			Xlib.XSendEvent(display, r.value.requestor, 0, 0, raw);
		}) else Arena.scoped(a -> {
			var raw = a.alloc(X.EVENT_SIZE);
			var n:Ptr<XSelectionEvent> = raw;
			n.value.type = X.SelectionNotify;
			n.value.display = display;
			n.value.requestor = r.value.requestor;
			n.value.selection = r.value.selection;
			n.value.target = r.value.target;
			n.value.property = 0;
			n.value.time = r.value.time;
			Xlib.XSendEvent(display, r.value.requestor, 0, 0, raw);
		});
		Xlib.XFlush(display);
	}

	static function latin1(s:String):haxe.io.Bytes {
		var b = haxe.io.Bytes.alloc(s.length);
		for (i in 0...s.length) {
			var c = StringTools.fastCodeAt(s, i);
			b.set(i, c < 256 ? c : "?".code);
		}
		return b;
	}

	// the converted selection arrived (or was refused): the first read of
	// this window gets it. (A selection sent in parts, INCR, over 256 KB or
	// so, is not read: the callback gets null.)
	function selectionArrived(e:Ptr<XSelectionEvent>) {
		var text:Null<String> = null;
		if (e.value.property != (0 : Int64)) Arena.scoped(a -> {
			var type:Ptr<Int64> = a.alloc(8), format:Ptr<Int32> = a.alloc(4), count:Ptr<Int64> = a.alloc(8), after:Ptr<Int64> = a.alloc(8);
			var data:Ptr<Ptr> = a.alloc(8);
			if (Xlib.XGetWindowProperty(display, id, e.value.property, 0, 1 << 24, 1, X.AnyPropertyType, type, format, count, after, data) == 0
				&& !data.value.isNull()) {
				if (format.value == 8 && (type.value == UTF8_STRING || type.value == X.XA_STRING)) {
					var n = count.value.toInt();
					var b = haxe.io.Bytes.alloc(n);
					LibC.memcpy(Mem.addr(b).add(8), data.value, (n : Int64));
					text = type.value == UTF8_STRING ? b.toString() : [for (i in 0...n) String.fromCharCode(b.get(i))].join("");
				}
				Xlib.XFree(data.value);
			}
		});
		for (r in clipboardReads)
			if (r.window == this) {
				clipboardReads.remove(r);
				r.callback(text);
				break;
			}
	}

	static function find(id:Int64):Null<X11Window> {
		for (w in open)
			if (w.id == id) return w;
		return null;
	}

	// dispatches the pending events
	static function poll(onEvent:Event->Void) {
		while (!display.isNull() && Xlib.XPending(display) > 0) {
			Xlib.XNextEvent(display, xev);
			var any:Ptr<XAnyEvent> = xev;
			var w = find(any.value.window);
			if (w == null) continue;
			var e = event;
			e.kind = None;
			e.window = w.owner;
			switch any.value.type {
				case X.ClientMessage:
					var m:Ptr<XClientMessageEvent> = xev;
					if (m.value.l0 == wmDelete) e.kind = Close;
				case X.SelectionRequest:
					answerSelection(xev);
				case X.SelectionClear:
					clipboardText = null;
				case X.SelectionNotify:
					w.selectionArrived(xev);
				case X.Expose:
					var x:Ptr<XExposeEvent> = xev;
					if (x.value.count == 0) e.kind = Redraw;
				case X.ConfigureNotify:
					var c:Ptr<XConfigureEvent> = xev;
					if (c.value.width != w.surface.width || c.value.height != w.surface.height) {
						w.surface.resized(c.value.width, c.value.height);
						e.kind = Resize;
						e.x = c.value.width;
						e.y = c.value.height;
					}
				case t = X.KeyPress | X.KeyRelease:
					var k:Ptr<XKeyEvent> = xev;
					e.kind = t == X.KeyPress ? KeyDown : KeyUp;
					e.key = Xlib.XLookupKeysym(xev, 0).toInt();
					e.mods = mods(k.value.state);
					if (t == X.KeyPress) {
						onEvent(e);
						// then its character
						var cp = character(k);
						if (cp == 0 || e.mods & (Mods.CONTROL | Mods.ALT) != 0) continue;
						e.kind = TextInput;
						e.text = String.fromCharCode(cp);
					}
				case t = X.ButtonPress | X.ButtonRelease | X.MotionNotify:
					var b:Ptr<XKeyEvent> = xev;
					e.kind = t == X.ButtonPress ? MouseDown : t == X.ButtonRelease ? MouseUp : MouseMove;
					e.x = b.value.x;
					e.y = b.value.y;
					e.button = t == X.MotionNotify ? 0 : (b.value.keycode : Int);
					e.mods = mods(b.value.state);
			}
			if (e.kind != None) onEvent(e);
		}
	}

	// waits for the connection's socket to have data, or seconds
	static function wait(seconds:Float) {
		if (display.isNull() || Xlib.XPending(display) > 0) return;
		var fd = Xlib.XConnectionNumber(display);
		Arena.scoped(a -> {
			var set:Ptr<Int64> = a.alloc(128);
			set[fd >> 6] = (1 : Int64) << (fd & 63);
			var tv:Ptr<Int64> = a.alloc(16);
			tv[0] = Std.int(seconds);
			tv[1] = Std.int((seconds - Std.int(seconds)) * 1e6);
			Select.select(fd + 1, set, Ptr.nil(), Ptr.nil(), tv);
		});
	}

	// the modifiers of an event's state (ShiftMask, ControlMask, Mod1Mask: Alt, Mod4Mask: Super)
	static function mods(state:Int):Int
		return (state & 1 != 0 ? Mods.SHIFT : 0) | (state & 4 != 0 ? Mods.CONTROL : 0) | (state & 8 != 0 ? Mods.ALT : 0) | (state & 64 != 0 ? Mods.META : 0);

	// the code point a key press types (0: none): its KeySym with the
	// modifiers applied, Latin-1 or a Unicode KeySym (0x100xxxx)
	static function character(k:Ptr<XKeyEvent>):Int
		return Arena.scopedValue(a -> {
			var buf = a.alloc(16);
			var ks:Ptr<Int64> = a.alloc(8);
			Xlib.XLookupString(k, buf, 15, ks, Ptr.nil());
			var s = ks.value.toInt();
			s >= 0x20 && s <= 0x7E || s >= 0xA0 && s <= 0xFF ? s : s & 0xFF000000 == 0x01000000 ? s & 0xFFFFFF : 0;
		});
}
