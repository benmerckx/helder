package hxmc.os.x11;

import hxmc.os.Event;
import hxmc.os.x11.Xlib;
import hxmc.unsafe.*;

// hxmc.os.Window on X11: one Display connection for the process, opened
// with the first window; WM_DELETE_WINDOW turns the close button into a
// Close event. A key's text comes from XLookupString (Latin-1, or a Unicode
// KeySym; no input method yet: compose sequences and IMEs), the wheel
// from buttons 4 to 7. The scale stays 1. Run by hxmc dev's host
// (-D hxmc.dev-host: hxmc.dev.Hosted), the connection and the first window
// are the host's: made by the first build, left by each build that hands
// over (its input method and contexts closed) and taken by the next, at the
// size the window has.
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
	static var INCR:Int64 = 0;
	// the selections this process sends in parts (INCR): to a requestor's
	// property, the next part when it deletes the last
	static final sending:Array<{requestor:Int64, property:Int64, target:Int64, data:haxe.io.Bytes, at:Int}> = [];
	// (parts of 64 KB, for a text over 256 KB)
	static inline var PART = 65536;
	static inline var INCR_OVER = 262144;
	static var TARGETS:Int64 = 0;
	static var HXMC_CLIPBOARD:Int64 = 0;
	static var clipboardText:Null<String> = null;
	// the input method (nil: none, XLookupString then)
	static var im = Ptr.nil();
	static final clipboardReads:Array<{window:X11Window, callback:Null<String>->Void}> = [];
	// the cursors made (by Cursor; 0: not yet)
	static final cursors:Array<Int64> = [];

	final owner:Window;
	final id:Int64;
	final surface:Surface;
	// this window's input context (nil: none)
	var ic = Ptr.nil();

	function new(owner:Window, title:String, width:Int, height:Int) {
		this.owner = owner;
		if (display.isNull()) connect();
		var screen = Xlib.XDefaultScreen(display);
		var black = Xlib.XBlackPixel(display, screen);
		#if hxmc.dev_host
		// (the host's window, as the last build left it)
		var kept = hxmc.dev.Hosted.hosted() && open.length == 0 ? hxmc.dev.Hosted.get(hxmc.dev.Hosted.X11_WINDOW) : Ptr.nil();
		if (!kept.isNull()) {
			id = kept.toI64();
			var w = haxe.Int64.toInt(hxmc.dev.Hosted.get(hxmc.dev.Hosted.WIDTH).toI64()), h = haxe.Int64.toInt(hxmc.dev.Hosted.get(hxmc.dev.Hosted.HEIGHT).toI64());
			if (w > 0 && h > 0) {
				width = w;
				height = h;
			}
			Sys.stderr().writeString("hxmc.dev: the host's window 0x" + StringTools.hex(haxe.Int64.toInt(id)) + " (process " + hxmc.dev.Hosted.HostThreads.getpid() + ")\n");
		} else {
			id = Xlib.XCreateSimpleWindow(display, Xlib.XRootWindow(display, screen), 0, 0, width, height, 0, black, black);
			if (hxmc.dev.Hosted.hosted() && open.length == 0) {
				hxmc.dev.Hosted.set(hxmc.dev.Hosted.X11_WINDOW, Ptr.ofI64(id));
				hxmc.dev.Hosted.set(hxmc.dev.Hosted.WIDTH, Ptr.ofI64(width));
				hxmc.dev.Hosted.set(hxmc.dev.Hosted.HEIGHT, Ptr.ofI64(height));
				Sys.stderr().writeString("hxmc.dev: the host's window 0x" + StringTools.hex(haxe.Int64.toInt(id)) + " (process " + hxmc.dev.Hosted.HostThreads.getpid() + ")\n");
			}
		}
		#else
		id = Xlib.XCreateSimpleWindow(display, Xlib.XRootWindow(display, screen), 0, 0, width, height, 0, black, black);
		#end
		Arena.scoped(a -> {
			Xlib.XStoreName(display, id, a.cstring(title));
			var atoms:Ptr<Int64> = a.alloc(8);
			atoms.value = wmDelete;
			Xlib.XSetWMProtocols(display, id, atoms, 1);
		});
		Xlib.XSelectInput(display, id, (X.KeyPressMask | X.KeyReleaseMask | X.ButtonPressMask | X.ButtonReleaseMask | X.PointerMotionMask
			| X.StructureNotifyMask | X.ExposureMask | X.PropertyChangeMask : Int64));
		Xlib.XMapWindow(display, id);
		if (!im.isNull()) {
			// (XIMPreeditNothing | XIMStatusNothing: the input method draws its own)
			ic = Xlib.XCreateIC(im, Mem.cstr("inputStyle"), 0x0008 | 0x0400, Mem.cstr("clientWindow"), id, Mem.cstr("focusWindow"), id, Ptr.nil());
			if (!ic.isNull()) Xlib.XSetICFocus(ic);
		}
		Xlib.XFlush(display);
		surface = new Surface(X11, display, Ptr.ofI64(id), width, height);
		open.push(this);
		#if hxmc.dev_host
		// (handing over: the input context closed, the window left to the next build; another window closed)
		if (hxmc.dev.Hosted.hosted()) hxmc.dev.Hot.onDispose(() -> if (open.indexOf(this) >= 0) {
			if (hxmc.dev.Hosted.get(hxmc.dev.Hosted.X11_WINDOW).toI64() == id) {
				open.remove(this);
				if (!ic.isNull()) Xlib.XDestroyIC(ic);
				ic = Ptr.nil();
				if (open.length == 0) handOver();
			} else destroy();
		});
		#end
	}

	#if hxmc.dev_host
	// (the last window left to the host: the input method closed, the connection kept)
	static function handOver() {
		cursors.resize(0);
		clipboardText = null;
		if (!im.isNull()) Xlib.XCloseIM(im);
		im = Ptr.nil();
		Xlib.XFlush(display);
		LibC.free(xev);
		display = Ptr.nil();
	}
	#end

	static function connect() {
		#if hxmc.dev_host
		display = hxmc.dev.Hosted.hosted() ? hxmc.dev.Hosted.get(hxmc.dev.Hosted.X11_DISPLAY) : Ptr.nil();
		if (display.isNull()) {
			display = Xlib.XOpenDisplay(Ptr.nil());
			if (hxmc.dev.Hosted.hosted()) hxmc.dev.Hosted.set(hxmc.dev.Hosted.X11_DISPLAY, display);
		}
		#else
		display = Xlib.XOpenDisplay(Ptr.nil());
		#end
		if (display.isNull()) throw "hxmc.os: cannot open the X display (DISPLAY=" + Sys.getEnv("DISPLAY") + ")";
		wmDelete = Xlib.XInternAtom(display, Mem.cstr("WM_DELETE_WINDOW"), 0);
		CLIPBOARD = Xlib.XInternAtom(display, Mem.cstr("CLIPBOARD"), 0);
		UTF8_STRING = Xlib.XInternAtom(display, Mem.cstr("UTF8_STRING"), 0);
		TARGETS = Xlib.XInternAtom(display, Mem.cstr("TARGETS"), 0);
		HXMC_CLIPBOARD = Xlib.XInternAtom(display, Mem.cstr("HXMC_CLIPBOARD"), 0);
		INCR = Xlib.XInternAtom(display, Mem.cstr("INCR"), 0);
		xev = LibC.malloc((X.EVENT_SIZE : Int64));
		openInputMethod();
	}

	// the input method in a UTF-8 locale (the environment's, else C.UTF-8);
	// the user's (XMODIFIERS), else Xlib's own (dead keys and compose)
	static function openInputMethod() {
		var l = Select.setlocale(0, Mem.cstr("")); // LC_CTYPE
		var name = l.isNull() ? "" : (cast l : CString).toString();
		if (name.indexOf("UTF-8") < 0 && name.indexOf("utf8") < 0 && name.indexOf("UTF8") < 0) Select.setlocale(0, Mem.cstr("C.UTF-8"));
		Xlib.XSetLocaleModifiers(Mem.cstr(""));
		im = Xlib.XOpenIM(display, Ptr.nil(), Ptr.nil(), Ptr.nil());
		if (im.isNull()) {
			Xlib.XSetLocaleModifiers(Mem.cstr("@im=none"));
			im = Xlib.XOpenIM(display, Ptr.nil(), Ptr.nil(), Ptr.nil());
		}
	}

	function destroy() {
		#if hxmc.dev_host
		// (the host's window: left to the next build when handing over, else gone with the host's state)
		if (hxmc.dev.Hosted.hosted() && hxmc.dev.Hosted.get(hxmc.dev.Hosted.X11_WINDOW).toI64() == id) {
			if (hxmc.dev.Hosted.handingOver) {
				open.remove(this);
				if (!ic.isNull()) Xlib.XDestroyIC(ic);
				ic = Ptr.nil();
				if (open.length == 0) handOver();
				return;
			}
			hxmc.dev.Hosted.set(hxmc.dev.Hosted.X11_WINDOW, Ptr.nil());
			if (open.length == 1) hxmc.dev.Hosted.set(hxmc.dev.Hosted.X11_DISPLAY, Ptr.nil());
		}
		#end
		open.remove(this);
		if (!ic.isNull()) Xlib.XDestroyIC(ic);
		ic = Ptr.nil();
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

	// the title: WM_NAME (Latin-1 for old window managers) and _NET_WM_NAME (UTF-8)
	function setTitle(t:String)
		Arena.scoped(a -> {
			Xlib.XStoreName(display, id, a.cstring(t));
			var utf8 = haxe.io.Bytes.ofString(t), p = a.alloc(utf8.length + 1);
			for (i in 0...utf8.length)
				(p : Ptr<UInt8>)[i] = utf8.get(i);
			Xlib.XChangeProperty(display, id, Xlib.XInternAtom(display, a.cstring("_NET_WM_NAME"), 0), UTF8_STRING, 8, 0, p, utf8.length);
			Xlib.XFlush(display);
		});

	function resize(w:Int, h:Int) {
		Xlib.XResizeWindow(display, id, w, h);
		Xlib.XFlush(display);
	}

	// WM_NORMAL_HINTS: XSizeHints with PMinSize (flags at 0, min_width and min_height at 24 and 28)
	function setMinSize(w:Int, h:Int)
		Arena.scoped(a -> {
			var hints = a.alloc(80);
			for (i in 0...80)
				(hints : Ptr<UInt8>)[i] = 0;
			(hints : Ptr<Int64>).value = 1 << 4;
			(hints.add(24) : Ptr<Int32>).value = w;
			(hints.add(28) : Ptr<Int32>).value = h;
			Xlib.XSetWMNormalHints(display, id, hints);
			Xlib.XFlush(display);
		});

	// (cursorfont.h: XC_left_ptr, XC_hand2, XC_xterm, XC_crosshair, XC_fleur,
	// XC_X_cursor, XC_sb_h_double_arrow, XC_sb_v_double_arrow; the font has no
	// open or closed hand: XC_hand1 and XC_fleur)
	function setCursor(c:Cursor) {
		var i:Int = c;
		while (cursors.length <= i)
			cursors.push(0);
		if (cursors[i] == 0) cursors[i] = Xlib.XCreateFontCursor(display, [68, 60, 152, 34, 52, 0, 108, 116, 58, 52][i]);
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
				if (b.length > INCR_OVER) {
					// in parts: INCR (with the size), then each part as the requestor deletes the last
					var size:Ptr<Int64> = a.alloc(8);
					size.value = b.length;
					if (find(r.value.requestor) == null) Xlib.XSelectInput(display, r.value.requestor, (X.PropertyChangeMask : Int64));
					Xlib.XChangeProperty(display, r.value.requestor, property, INCR, 32, X.PropModeReplace, size, 1);
					sending.push({requestor: r.value.requestor, property: property, target: r.value.target, data: b, at: 0});
				} else
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

	// the parts of a selection coming in (INCR), and their type
	var incoming:Null<haxe.io.BytesBuffer> = null;
	var incomingType:Int64 = 0;

	// the property's contents, deleted (null: none)
	function takeProperty(property:Int64):Null<{type:Int64, format:Int, bytes:haxe.io.Bytes}>
		return Arena.scopedValue(a -> {
			var type:Ptr<Int64> = a.alloc(8), format:Ptr<Int32> = a.alloc(4), count:Ptr<Int64> = a.alloc(8), after:Ptr<Int64> = a.alloc(8);
			var data:Ptr<Ptr> = a.alloc(8);
			if (Xlib.XGetWindowProperty(display, id, property, 0, 1 << 24, 1, X.AnyPropertyType, type, format, count, after, data) != 0) null else {
				// (32-bit items come as longs)
				var n = count.value.toInt() * (format.value == 32 ? 8 : format.value == 16 ? 2 : 1);
				var b = haxe.io.Bytes.alloc(n);
				if (!data.value.isNull()) {
					if (n > 0) LibC.memcpy(Mem.addr(b).add(8), data.value, (n : Int64));
					Xlib.XFree(data.value);
				}
				{type: type.value, format: format.value, bytes: b};
			}
		});

	static function decode(type:Int64, b:haxe.io.Bytes):Null<String>
		return type == UTF8_STRING ? b.toString() : type == X.XA_STRING ? [for (i in 0...b.length) String.fromCharCode(b.get(i))].join("") : null;

	// the converted selection arrived (or was refused): the first read of
	// this window gets it; one sent in parts (INCR) when its last part comes
	function selectionArrived(e:Ptr<XSelectionEvent>) {
		var text:Null<String> = null;
		if (e.value.property != (0 : Int64)) {
			var p = takeProperty(e.value.property);
			if (p != null && p.type == INCR) {
				// (its deletion, done, asks for the first part)
				incoming = new haxe.io.BytesBuffer();
				Xlib.XFlush(display);
				return;
			}
			if (p != null && p.format == 8) text = decode(p.type, p.bytes);
		}
		deliver(text);
	}

	// a part of an incoming selection (a property with a new value): the last, empty, ends it
	function partArrived(property:Int64) {
		var p = takeProperty(property);
		Xlib.XFlush(display);
		if (p == null) return;
		if (p.bytes.length > 0) {
			incoming.add(p.bytes);
			incomingType = p.type;
			return;
		}
		var all = incoming.getBytes();
		incoming = null;
		deliver(decode(incomingType, all));
	}

	// the next part of a selection sent in parts, after the requestor deleted the last
	static function nextPart(requestor:Int64, property:Int64) {
		for (s in sending)
			if (s.requestor == requestor && s.property == property) {
				var n = s.data.length - s.at;
				if (n > PART) n = PART;
				Arena.scoped(a -> {
					var p:Ptr = n > 0 ? a.copyBytes(s.data.sub(s.at, n)) : a.alloc(1);
					Xlib.XChangeProperty(display, requestor, property, s.target, 8, X.PropModeReplace, p, n);
				});
				s.at += n;
				// (the empty part sent: done)
				if (n == 0) sending.remove(s);
				Xlib.XFlush(display);
				return;
			}
	}

	function deliver(text:Null<String>) {
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
			// (what the input method takes: a dead key, a compose sequence's keys)
			if (!im.isNull() && Xlib.XFilterEvent(xev, 0) != 0) continue;
			var any:Ptr<XAnyEvent> = xev;
			// (the keyboard mapping changed: another layout; it has no window)
			if (any.value.type == X.MappingNotify) {
				Xlib.XRefreshKeyboardMapping(xev);
				continue;
			}
			// (a requestor deleted a part this process sent: the next)
			if (any.value.type == X.PropertyNotify) {
				var pe:Ptr<XPropertyEvent> = xev;
				if (pe.value.state == X.PropertyDelete) nextPart(pe.value.window, pe.value.atom);
				var pw = find(pe.value.window);
				if (pe.value.state == X.PropertyNewValue && pw != null && pw.incoming != null && pe.value.atom == HXMC_CLIPBOARD) pw.partArrived(pe.value.atom);
				continue;
			}
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
						#if hxmc.dev_host
						if (hxmc.dev.Hosted.hosted() && hxmc.dev.Hosted.get(hxmc.dev.Hosted.X11_WINDOW).toI64() == w.id) {
							hxmc.dev.Hosted.set(hxmc.dev.Hosted.WIDTH, Ptr.ofI64(c.value.width));
							hxmc.dev.Hosted.set(hxmc.dev.Hosted.HEIGHT, Ptr.ofI64(c.value.height));
						}
						#end
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
						// then its characters
						var s = w.typed(k);
						if (s == "" || e.mods & (Mods.CONTROL | Mods.ALT) != 0) continue;
						e.kind = TextInput;
						e.text = s;
					}
				case t = X.ButtonPress | X.ButtonRelease | X.MotionNotify:
					var b:Ptr<XKeyEvent> = xev;
					var button = t == X.MotionNotify ? 0 : (b.value.keycode : Int);
					e.x = b.value.x;
					e.y = b.value.y;
					e.mods = mods(b.value.state);
					if (button >= 4 && button <= 7) {
						// (the wheel: buttons 4 and 5 up and down, 6 and 7 left and right; a notch on the press)
						if (t != X.ButtonPress) continue;
						e.kind = Scroll;
						e.deltaX = button == 6 ? -40 : button == 7 ? 40 : 0;
						e.deltaY = button == 4 ? -40 : button == 5 ? 40 : 0;
					} else {
						e.kind = t == X.ButtonPress ? MouseDown : t == X.ButtonRelease ? MouseUp : MouseMove;
						e.button = button;
					}
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

	// what a key press types: the input context's text (UTF-8), else the
	// KeySym's character; control characters left out
	function typed(k:Ptr<XKeyEvent>):String {
		if (ic.isNull()) {
			var cp = character(k);
			return cp == 0 ? "" : String.fromCharCode(cp);
		}
		return Arena.scopedValue(a -> {
			var buf:Ptr<UInt8> = a.alloc(64), ks:Ptr<Int64> = a.alloc(8), status:Ptr<Int32> = a.alloc(4);
			var n = Xlib.Xutf8LookupString(ic, k, buf, 63, ks, status);
			// (XLookupChars 2, XLookupBoth 4: text there)
			if (n <= 0 || (status.value != 2 && status.value != 4)) "" else {
				var b = haxe.io.Bytes.alloc(n);
				for (i in 0...n)
					b.set(i, buf[i]);
				var s = b.toString();
				var c = StringTools.fastCodeAt(s, 0);
				c < 0x20 || c == 0x7F ? "" : s;
			}
		});
	}

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
