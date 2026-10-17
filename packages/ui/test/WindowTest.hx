import hxmc.os.*;
import hxmc.os.objc.*;
import hxmc.os.x11.Xlib;
import hxmc.os.win32.User32;
import hxmc.unsafe.*;

// hxmc.os's windows given a title, a size and a minimum size, each read
// back through the platform's own calls (make ui-draw-check under Xvfb: X11's
// _NET_WM_NAME, WM_NAME, the window's geometry, WM_NORMAL_HINTS; CI:
// Win32's window text, client rectangle and WM_GETMINMAXINFO's answer,
// Cocoa's title and content sizes).
//   WindowTest
class WindowTest {
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('WindowTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var w = new Window("hxmc", 200, 100);
		var title = "Fenêtre ✓";
		w.title = title;
		w.resize(300, 150);
		w.setMinSize(120, 80);
		var frames = 0, resized = false;
		App.run(() -> {
			if (++frames > 20 && resized || frames > 400) {
				if (Mem.os() == 0) x11(w, title) else if (Mem.os() == 2) win32(w, title) else if (Mem.os() == 1) cocoa(w, title);
				w.close();
			}
			App.wait(0.01);
		}, e -> if (e.kind == Resize) resized = true);
		check("a Resize event", resized);
		Sys.println('WindowTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function x11(w:Window, title:String) {
		var d = w.surface.display, id = w.surface.handle.toI64();
		function property(name:String, type:Int64):Null<haxe.io.Bytes>
			return Arena.scopedValue(a -> {
				var actual:Ptr<Int64> = a.alloc(8), format:Ptr<Int32> = a.alloc(4), count:Ptr<Int64> = a.alloc(8), after:Ptr<Int64> = a.alloc(8);
				var data:Ptr<Ptr> = a.alloc(8);
				var atom = Xlib.XInternAtom(d, a.cstring(name), 0);
				if (Xlib.XGetWindowProperty(d, id, atom, 0, 1024, 0, type, actual, format, count, after, data) != 0 || data.value.isNull()) null else {
					// (format 32: C longs)
					var unit = format.value == 32 ? 8 : format.value == 16 ? 2 : 1, n = count.value.toInt() * unit;
					var b = haxe.io.Bytes.alloc(n);
					for (i in 0...n)
						b.set(i, (data.value : Ptr<UInt8>)[i]);
					Xlib.XFree(data.value);
					b;
				}
			});
		var utf8 = Arena.scopedValue(a -> Xlib.XInternAtom(d, a.cstring("UTF8_STRING"), 0));
		var net = property("_NET_WM_NAME", utf8);
		check("x11: _NET_WM_NAME in UTF-8", net != null && net.toString() == title, net == null ? "none" : net.toString());
		var name = property("WM_NAME", 31);
		check("x11: WM_NAME", name != null && name.length > 0);
		check("x11: resized", w.width == 300 && w.height == 150, '${w.width}x${w.height}');
		var hints = property("WM_NORMAL_HINTS", 41);
		// (flags, then x, y, width, height, min_width, min_height: longs)
		check("x11: the minimum size", hints != null && hints.getInt32(0) & (1 << 4) != 0 && hints.getInt32(5 * 8) == 120 && hints.getInt32(6 * 8) == 80,
			hints == null ? "none" : hints.getInt32(5 * 8) + "x" + hints.getInt32(6 * 8));
	}

	static function win32(w:Window, title:String) {
		var hwnd = w.surface.handle;
		Arena.scoped(a -> {
			var buf:Ptr<UInt16> = a.alloc(256);
			var n = User32.GetWindowTextW(hwnd, buf, 128);
			var b = new StringBuf();
			for (i in 0...n)
				b.addChar(buf[i]);
			check("win32: the window text", b.toString() == title, b.toString());
			var r = a.make(RECT);
			User32.GetClientRect(hwnd, r);
			check("win32: resized", r.value.right == Math.round(300 * w.scale) && r.value.bottom == Math.round(150 * w.scale), '${r.value.right}x${r.value.bottom}');
			// (MINMAXINFO: ptMinTrackSize at 24, the outer size of 120 x 80)
			var mmi:Ptr<Int32> = a.alloc(40);
			for (i in 0...10)
				mmi[i] = 0;
			User32.SendMessageW(hwnd, 0x0024, 0, mmi.toI64());
			check("win32: the minimum size", mmi[6] >= Math.round(120 * w.scale) && mmi[7] >= Math.round(80 * w.scale), '${mmi[6]}x${mmi[7]}');
		});
	}

	static function cocoa(w:Window, title:String) {
		var view = w.surface.handle, window = Msg.id(view, ObjC.sel("window"));
		var t = ObjC.string(Msg.id(window, ObjC.sel("title")));
		check("cocoa: the title", t == title, t);
		var f = Msg.rect(Msg.id(window, ObjC.sel("contentView")), ObjC.sel("frame"));
		check("cocoa: resized", f.size.width == 300 && f.size.height == 150, '${f.size.width}x${f.size.height}');
		var m = Msg.point(window, ObjC.sel("contentMinSize"));
		check("cocoa: the minimum size", m.x == 120 && m.y == 80, '${m.x}x${m.y}');
	}
}
