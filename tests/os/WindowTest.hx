import helder.os.*;
import helder.os.objc.*;
import helder.os.win32.User32;
import helder.os.x11.Xlib;
import hxmc.unsafe.*;

// helder.os's windows (`bun run test window`; Linux: Xvfb, Windows: also
// under Wine): files dropped through each system's own mechanism, Event.Drop
// with their paths and where; moveTo and position; fullscreen asked.
//
// - X11: a second connection is a drag source speaking XDND 5 to the window
//   (XdndEnter, XdndPosition, XdndDrop; the selection's text/uri-list
//   answered), the XdndStatus and XdndFinished it gets back checked;
// - Windows: an HDROP of two wide paths (DROPFILES) posted as WM_DROPFILES;
// - macOS: a dragging info of a class made here (a pasteboard of file URLs,
//   the destination window) given to the window's dragging destination,
//   draggingEntered: then performDragOperation:.
class WindowTest {
	static var failed = 0;

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println('WindowTest: ${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	static function main() {
		var window = new Window("WindowTest", 200, 150);
		var dropped:Null<{files:Array<String>, x:Int, y:Int}> = null;
		var start = haxe.Timer.stamp(), step = 0, frames = 0;
		// (macOS gives a path's characters decomposed, as its file systems
		// keep them: é as e and its accent; ASCII there)
		var want = Mem.os() == 2 ? ["C:\\photos\\a b.png", "C:\\photos\\é.jpg"] : Mem.os() == 1 ? ["/tmp/photos/a b.png", "/tmp/photos/c.jpg"] : ["/tmp/photos/a b.png", "/tmp/photos/é.jpg"];
		var source:Null<DropSource> = null;
		App.run(() -> {
			frames++;
			var t = haxe.Timer.stamp() - start;
			if (step == 0 && frames > 3) {
				step = 1;
				// (clear of macOS's menu bar, which a window's frame stays under)
				window.moveTo(120, 160);
				source = new DropSource(window, want, 20, 30);
			}
			if (step == 1) source.pump();
			if (step == 1 && (dropped != null || t > 5)) {
				step = 2;
				check("a drop: its files", dropped != null && dropped.files.join("|") == want.join("|"), dropped == null ? "none" : dropped.files.join("|"));
				// (where: X11 and Windows exactly, macOS where the pointer is)
				if (dropped != null && Mem.os() != 1) check("a drop: where", dropped.x == 20 && dropped.y == 30, '${dropped.x}, ${dropped.y}');
				source.finish(check);
				var p = window.position();
				check("moveTo, position", p != null && p.x == 120 && p.y == 160, p == null ? "null" : '${p.x}, ${p.y}');
				window.fullscreen = true;
			}
			if (step == 2 && t > 6.5) {
				step = 3;
				// (asked: a window manager, Windows and macOS's spaces may take a while; X11 without one never)
				Sys.println('WindowTest: fullscreen ${window.fullscreen}, ${window.width}x${window.height}');
				window.fullscreen = false;
				App.quit();
			}
			App.wait(0.02);
		}, e -> switch e.kind {
			case Drop:
				dropped = {files: e.files.copy(), x: e.x, y: e.y};
			case Close:
				window.close();
			case _:
		});
		Sys.exit(failed > 0 ? 1 : 0);
	}
}

// a drop made by the system's own means (above)
private class DropSource {
	final window:Window;
	final files:Array<String>;
	final x:Int;
	final y:Int;
	var d = Ptr.nil();
	var src:Int64 = 0;
	var target:Int64 = 0;
	var atoms:Map<String, Int64> = [];
	var accepted = -1;
	var finished = -1;
	var dropSent = false;
	var answered = false;

	public function new(window:Window, files:Array<String>, x:Int, y:Int) {
		this.window = window;
		this.files = files;
		this.x = x;
		this.y = y;
		if (Mem.os() == 2) windows() else if (Mem.os() == 1) mac() else x11();
	}

	public function pump()
		if (Mem.os() != 1 && Mem.os() != 2) pumpX11();

	public function finish(check:(String, Bool, String) -> Void) {
		if (Mem.os() == 1 || Mem.os() == 2) return;
		check("XDND: the position accepted (XdndStatus)", accepted == 1, 'accepted $accepted');
		check("XDND: XdndFinished, the drop taken", finished == 1, 'finished $finished');
	}

	// --- Windows: WM_DROPFILES of an HDROP
	function windows() {
		var hwnd = @:privateAccess (cast @:privateAccess window.native : helder.os.win32.Win32Window).hwnd;
		var chars = 0;
		for (f in files)
			chars += f.length + 1;
		// (DROPFILES: pFiles 20, pt, fNC, fWide; the paths, a 0 after each and one more)
		var mem = helder.os.win32.User32.Kernel32.GlobalAlloc(0x42, (20 + 2 * (chars + 1) : Int64));
		var p:Ptr<UInt8> = helder.os.win32.User32.Kernel32.GlobalLock(mem);
		var h:Ptr<Int32> = cast p;
		h[0] = 20;
		h[1] = x;
		h[2] = y;
		h[3] = 0;
		h[4] = 1;
		var w:Ptr<UInt16> = cast p.add(20), k = 0;
		for (f in files) {
			for (i in 0...f.length)
				w[k++] = StringTools.fastCodeAt(f, i);
			w[k++] = 0;
		}
		w[k] = 0;
		helder.os.win32.User32.Kernel32.GlobalUnlock(mem);
		helder.os.win32.User32.PostMessageW(hwnd, 0x0233, mem.toI64(), 0);
	}

	// --- macOS: the window's dragging destination given a dragging info of our own
	function mac() {
		var w = @:privateAccess (cast @:privateAccess window.native : helder.os.cocoa.CocoaWindow).window;
		MacDrag.make(w, files);
	}

	// --- X11: XDND from a second connection
	function x11() {
		target = @:privateAccess (cast @:privateAccess window.native : helder.os.x11.X11Window).id;
		d = helder.os.x11.Xlib.XOpenDisplay(Ptr.nil());
		var root = helder.os.x11.Xlib.XDefaultRootWindow(d);
		src = helder.os.x11.Xlib.XCreateSimpleWindow(d, root, 0, 0, 10, 10, 0, 0, 0);
		for (n in ["XdndEnter", "XdndPosition", "XdndStatus", "XdndDrop", "XdndFinished", "XdndSelection", "XdndActionCopy", "text/uri-list"])
			Arena.scoped(a -> atoms.set(n, helder.os.x11.Xlib.XInternAtom(d, a.cstring(n), 0)));
		helder.os.x11.Xlib.XSetSelectionOwner(d, atoms["XdndSelection"], src, 0);
		var p = window.position();
		send("XdndEnter", src, (5 : Int64) << 24, atoms["text/uri-list"], 0, 0);
		send("XdndPosition", src, 0, ((p.x + x : Int64) << 16) | (p.y + y), 0, atoms["XdndActionCopy"]);
		helder.os.x11.Xlib.XFlush(d);
	}

	function send(type:String, l0:Int64, l1:Int64, l2:Int64, l3:Int64, l4:Int64)
		Arena.scoped(a -> {
			var raw:Ptr<UInt8> = a.alloc(192);
			for (i in 0...192)
				raw[i] = 0;
			var m:Ptr<helder.os.x11.Xlib.XClientMessageEvent> = cast raw;
			m.value.type = 33;
			m.value.display = d;
			m.value.window = target;
			m.value.message_type = atoms[type];
			m.value.format = 32;
			var l:Ptr<Int64> = cast raw.add(56);
			l[0] = l0;
			l[1] = l1;
			l[2] = l2;
			l[3] = l3;
			l[4] = l4;
			helder.os.x11.Xlib.XSendEvent(d, target, 0, 0, cast raw);
		});

	// (a path's bytes percent-encoded but for letters, digits, / . - _)
	static function escape(path:String):String {
		var b = haxe.io.Bytes.ofString(path), out = new StringBuf();
		for (i in 0...b.length) {
			var c = b.get(i);
			if ((c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || (c >= "0".code && c <= "9".code) || c == "/".code || c == ".".code || c == "-".code || c == "_".code)
				out.addChar(c)
			else
				out.add("%" + StringTools.hex(c, 2));
		}
		return out.toString();
	}

	function pumpX11() {
		var ev:Ptr<UInt8> = LibC.malloc(192);
		while (helder.os.x11.Xlib.XPending(d) > 0) {
			helder.os.x11.Xlib.XNextEvent(d, cast ev);
			var type = (cast ev : Ptr<Int32>).value;
			if (type == 33) {
				var m:Ptr<helder.os.x11.Xlib.XClientMessageEvent> = cast ev, l:Ptr<Int64> = cast ev.add(56);
				if (m.value.message_type == atoms["XdndStatus"]) {
					accepted = l[1].toInt() & 1;
					if (!dropSent) {
						dropSent = true;
						send("XdndDrop", src, 0, 0, 0, 0);
					}
				}
				if (m.value.message_type == atoms["XdndFinished"]) finished = l[1].toInt() & 1;
			} else if (type == 30) {
				// (SelectionRequest: the files as text/uri-list into the requestor's property)
				var r:Ptr<helder.os.x11.Xlib.XSelectionRequestEvent> = cast ev;
				var list = [for (f in files) "file://" + escape(f)].join("\r\n") + "\r\n";
				var b = haxe.io.Bytes.ofString(list);
				Arena.scoped(a -> {
					helder.os.x11.Xlib.XChangeProperty(d, r.value.requestor, r.value.property, atoms["text/uri-list"], 8, 0, a.copyBytes(b), b.length);
					var raw:Ptr<UInt8> = a.alloc(192);
					for (i in 0...192)
						raw[i] = 0;
					var n:Ptr<helder.os.x11.Xlib.XSelectionEvent> = cast raw;
					n.value.type = 31;
					n.value.display = d;
					n.value.requestor = r.value.requestor;
					n.value.selection = r.value.selection;
					n.value.target = r.value.target;
					n.value.property = r.value.property;
					n.value.time = r.value.time;
					helder.os.x11.Xlib.XSendEvent(d, r.value.requestor, 0, 0, cast raw);
				});
				answered = true;
			}
		}
		LibC.free(ev);
		helder.os.x11.Xlib.XFlush(d);
	}
}

// (a dragging info: NSDraggingInfo's draggingPasteboard, draggingDestinationWindow
// and draggingSourceOperationMask, from a class made at run time)
private class MacDrag {
	static var pasteboard = Ptr.nil();
	static var destination = Ptr.nil();

	public static function make(window:Ptr, files:Array<String>) {
		destination = window;
		pasteboard = Runtime.objc_retain(Msg.id(ObjC.cls("NSPasteboard"), ObjC.sel("pasteboardWithUniqueName")));
		Msg.i(pasteboard, ObjC.sel("clearContents"));
		var urls = Msg.id(Msg.id(ObjC.cls("NSMutableArray"), ObjC.sel("alloc")), ObjC.sel("init"));
		for (f in files) {
			var s = ObjC.str(f);
			Msg.vPtr(urls, ObjC.sel("addObject:"), Msg.idPtr(ObjC.cls("NSURL"), ObjC.sel("fileURLWithPath:"), s));
			ObjC.release(s);
		}
		Msg.bPtr(pasteboard, ObjC.sel("writeObjects:"), urls);
		var cls = Runtime.objc_allocateClassPair(ObjC.cls("NSObject"), Mem.cstr("HxmcTestDrag"), 0);
		Runtime.class_addMethod(cls, ObjC.sel("draggingPasteboard"), Callback.addr(board), Mem.cstr("@@:"));
		Runtime.class_addMethod(cls, ObjC.sel("draggingDestinationWindow"), Callback.addr(dest), Mem.cstr("@@:"));
		Runtime.class_addMethod(cls, ObjC.sel("draggingSourceOperationMask"), Callback.addr(mask), Mem.cstr("Q@:"));
		Runtime.objc_registerClassPair(cls);
		var info = Msg.id(Msg.id(cls, ObjC.sel("alloc")), ObjC.sel("init"));
		var delegate = Msg.id(window, ObjC.sel("delegate"));
		var op = Msg.iPtr(delegate, ObjC.sel("draggingEntered:"), info);
		Sys.println('WindowTest: draggingEntered: $op');
		Msg.bPtr(delegate, ObjC.sel("performDragOperation:"), info);
	}

	@:hxmc.callback static function board(self:Ptr, cmd:Ptr):Ptr
		return pasteboard;

	@:hxmc.callback static function dest(self:Ptr, cmd:Ptr):Ptr
		return destination;

	@:hxmc.callback static function mask(self:Ptr, cmd:Ptr):Int64
		return 1;
}
