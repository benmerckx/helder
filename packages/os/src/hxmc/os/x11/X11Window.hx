package hxmc.os.x11;

import hxmc.os.Event;
import hxmc.os.x11.Xlib;
import hxmc.unsafe.*;

// hxmc.os.Window on X11: one Display connection for the process, opened
// with the first window; WM_DELETE_WINDOW turns the close button into a
// Close event. A key's text comes from XLookupString (Latin-1, or a Unicode
// KeySym; no input method yet: compose sequences and IMEs), the wheel
// from buttons 4 to 7. The scale stays 1.
@:allow(hxmc.os)
class X11Window {
	static var display = Ptr.nil();
	static var wmDelete:Int64 = 0;
	// one XEvent buffer, and the Event dispatched from it
	static var xev:Ptr = Ptr.nil();
	static var text:Ptr<UInt8> = Ptr.nil(); // XLookupString's buffer and KeySym
	static var keysym:Ptr<Int64> = Ptr.nil();
	static final event = new Event();
	static final open:Array<X11Window> = [];

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
		text = LibC.malloc(16);
		keysym = LibC.malloc(8);
	}

	function destroy() {
		open.remove(this);
		Xlib.XDestroyWindow(display, id);
		Xlib.XFlush(display);
		if (open.length == 0) {
			Xlib.XCloseDisplay(display);
			LibC.free(xev);
			LibC.free(text);
			LibC.free(keysym);
			display = Ptr.nil();
		}
	}

	static function find(id:Int64):Null<X11Window> {
		for (w in open)
			if (w.id == id) return w;
		return null;
	}

	// the text of the KeyPress in xev: a Text event per character
	static function typed(w:X11Window, onEvent:Event->Void) {
		var n = Xlib.XLookupString(xev, text, 16, keysym, Ptr.nil());
		var e = event;
		e.kind = Text;
		e.window = w.owner;
		if (n == 0) {
			// (a Unicode KeySym: 0x1000000 + the code point)
			var k = keysym.value;
			if (k >> 24 == 1) {
				e.char = (k & 0xFFFFFF).toInt();
				if (e.char >= 0x20) onEvent(e);
			}
			return;
		}
		for (i in 0...n) {
			var c:Int = text[i];
			if (c >= 0x20 && c != 0x7F) {
				e.char = c;
				onEvent(e);
			}
		}
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
					e.kind = t == X.KeyPress ? KeyDown : KeyUp;
					e.key = Xlib.XLookupKeysym(xev, 0).toInt();
					if (t == X.KeyPress) {
						onEvent(e);
						typed(w, onEvent);
						continue;
					}
				case t = X.ButtonPress | X.ButtonRelease | X.MotionNotify:
					var b:Ptr<XKeyEvent> = xev;
					var button:Int = t == X.MotionNotify ? 0 : (b.value.keycode : Int);
					e.x = b.value.x;
					e.y = b.value.y;
					if (button >= 4 && button <= 7) {
						// (the wheel: a press per notch, up, down, left, right)
						if (t != X.ButtonPress) continue;
						e.kind = Wheel;
						e.dx = button == 6 ? -1 : button == 7 ? 1 : 0;
						e.dy = button == 4 ? 1 : button == 5 ? -1 : 0;
					} else {
						e.kind = t == X.ButtonPress ? MouseDown : t == X.ButtonRelease ? MouseUp : MouseMove;
						e.button = button;
					}
			}
			if (e.kind != None) onEvent(e);
		}
	}
}
