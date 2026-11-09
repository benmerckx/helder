import helder.os.*;
import helder.os.TitleBar;
import helder.os.objc.*;
import hxmc.unsafe.*;

// An inset title bar (helder.os's TitleBar) on the system's own window
// (`bun run test window`): the app's answer (Window.titlebarAt) and the
// window's buttons where the system has them.
// - macOS: the content under the title bar (a full-size content view, the
//   bar transparent, no title), the system's buttons measured, placed where
//   the app asks and kept there through a resize; a press on the bar but
//   the buttons the app's, on a button AppKit's;
// - Windows: no caption (the client area the window's top), WM_NCHITTEST
//   answering the app's drag region (HTCAPTION) and maximise button
//   (HTMAXBUTTON), the top edge (HTTOP);
// - X11: undecorated (_MOTIF_WM_HINTS' decorations 0).
class TitleBarTest {
	static var failed = 0;

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println('TitleBarTest: ${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	static function main() {
		var window = new Window("TitleBarTest", 400, 300, Inset);
		var k = window.scale;
		// (the app's: a bar 40 points tall a drag region, its maximise button at the right)
		window.titlebarAt = (x, y) -> y >= 40 * k ? Content : x >= window.width - 46 * k ? Maximize : Drag;
		var frames = 0, step = 0;
		App.run(() -> {
			frames++;
			if (frames < 4) {
				App.wait(0.02);
				return;
			}
			if (step == 0) {
				step = 1;
				if (Mem.os() == 1) mac(window);
				if (Mem.os() == 2) windows(window);
				if (Mem.os() == 0 && !Std.isOfType(@:privateAccess window.native, helder.os.wayland.WaylandWindow)) x11(window);
				window.resize(500, 320);
			} else if (step == 1 && frames > 12) {
				step = 2;
				if (Mem.os() == 1) {
					var c = window.systemControls(), k = window.scale;
					check("macOS: the buttons kept where placed after a resize", c != null && Math.abs(c.x - 20 * k) <= 1 && Math.abs(c.y - 14 * k) <= 1,
						c == null ? "none" : '${c.x}, ${c.y}');
				}
				App.quit();
			}
			App.wait(0.02);
		}, e -> switch e.kind {
			case Close: window.close();
			case _:
		});
		Sys.exit(failed > 0 ? 1 : 0);
	}

	static function mac(window:Window) {
		var c:helder.os.cocoa.CocoaWindow = cast @:privateAccess window.native;
		var ns:Ptr = @:privateAccess c.window;
		var mask = Msg.i(ns, ObjC.sel("styleMask")).toInt();
		check("macOS: a full-size content view", mask & (1 << 15) != 0, '$mask');
		check("macOS: the title bar transparent", Msg.b(ns, ObjC.sel("titlebarAppearsTransparent")));
		var b = window.systemControls(), k = window.scale;
		check("macOS: the system's buttons over the content", b != null && b.x > 0 && b.width > b.height * 2, b == null ? "none" : '${b.x}, ${b.y}, ${b.width}x${b.height}');
		var a = window.titlebarArea();
		check("macOS: the title bar's area right of them", a != null && b != null && a.x == b.x + b.width && a.width == window.width - a.x && a.height >= Math.round(28 * k),
			a == null ? "none" : '${a.x}, ${a.y}, ${a.width}x${a.height}');
		window.placeControls(Math.round(20 * k), Math.round(14 * k));
		var p = window.systemControls();
		check("macOS: the buttons placed", p != null && Math.abs(p.x - 20 * k) <= 1 && Math.abs(p.y - 14 * k) <= 1, p == null ? "none" : '${p.x}, ${p.y}');
		// (a press: the hit view at a point of the window, AppKit's coordinates from its bottom left)
		var h = Msg.rect(ns, ObjC.sel("frame")).size.height;
		function press(x:Float, yTop:Float):Ptr {
			var r:Ptr<CGRect> = LibC.malloc(32);
			r.value.origin.x = x;
			r.value.origin.y = h - yTop;
			var content = Msg.id(ns, ObjC.sel("contentView"));
			var hit = Msg.idPoint(Msg.id(content, ObjC.sel("superview")), ObjC.sel("hitTest:"), r.value.origin);
			LibC.free(r);
			return hit;
		}
		var bar = press(200, 8), button = press(20 + 6, 14 + 8);
		check("macOS: a press on the bar is the app's", !bar.isNull() && !Msg.bPtr(bar, ObjC.sel("isKindOfClass:"), ObjC.cls("NSButton")));
		check("macOS: a press on a button is AppKit's", !button.isNull() && Msg.bPtr(button, ObjC.sel("isKindOfClass:"), ObjC.cls("NSButton")));
		check("macOS: the app's answer at the bar", window.titlebarAt(Math.round(200 * k), Math.round(8 * k)) == Drag);
	}

	static function windows(window:Window) {
		var w:helder.os.win32.Win32Window = cast @:privateAccess window.native;
		var hwnd:Ptr = @:privateAccess w.hwnd;
		Arena.scoped(a -> {
			var r = a.make(helder.os.win32.User32.RECT), c = a.make(helder.os.win32.User32.POINT);
			helder.os.win32.User32.GetWindowRect(hwnd, r);
			helder.os.win32.User32.ClientToScreen(hwnd, c);
			check("Windows: no caption (the client area at the window's top)", c.value.y == r.value.top, '${c.value.y} against ${r.value.top}');
			function hit(x:Int, y:Int):Int {
				var lp:Int64 = ((c.value.y + y) & 0xFFFF) << 16 | ((c.value.x + x) & 0xFFFF);
				return helder.os.win32.User32.SendMessageW(hwnd, 0x0084, 0, lp).toInt();
			}
			var k = window.scale;
			check("Windows: a drag region is HTCAPTION", hit(Math.round(100 * k), Math.round(20 * k)) == 2);
			check("Windows: the maximise button HTMAXBUTTON", hit(window.width - Math.round(20 * k), Math.round(20 * k)) == 9);
			check("Windows: the content HTCLIENT", hit(Math.round(100 * k), Math.round(100 * k)) == 1);
			check("Windows: the top edge HTTOP", hit(Math.round(100 * k), 1) == 12);
		});
	}

	static function x11(window:Window) {
		var w:helder.os.x11.X11Window = cast @:privateAccess window.native;
		var hints = @:privateAccess w.takeProperty(helder.os.x11.Xlib.XInternAtom(@:privateAccess helder.os.x11.X11Window.display, Mem.cstr("_MOTIF_WM_HINTS"), 0), false);
		check("X11: undecorated (Motif's hints)", hints != null && hints.format == 32 && hints.bytes.getInt32(0) == 2 && hints.bytes.getInt32(16) == 0,
			hints == null ? "none" : '${hints.bytes.getInt32(0)} ${hints.bytes.getInt32(16)}');
	}
}
