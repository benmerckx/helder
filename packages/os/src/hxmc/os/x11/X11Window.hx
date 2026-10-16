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
			| X.StructureNotifyMask : Int64));
		Xlib.XMapWindow(display, id);
		Xlib.XFlush(display);
		surface = new Surface(X11, display, Ptr.ofI64(id), width, height);
		open.push(this);
	}

	static function connect() {
		display = Xlib.XOpenDisplay(Ptr.nil());
		if (display.isNull()) throw "hxmc.os: cannot open the X display (DISPLAY=" + Sys.getEnv("DISPLAY") + ")";
		wmDelete = Xlib.XInternAtom(display, Mem.cstr("WM_DELETE_WINDOW"), 0);
		xev = LibC.malloc((X.EVENT_SIZE : Int64));
	}

	function destroy() {
		open.remove(this);
		Xlib.XDestroyWindow(display, id);
		Xlib.XFlush(display);
		if (open.length == 0) {
			// (the cursors go with the connection)
			cursors.resize(0);
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
