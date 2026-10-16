import haxe.io.Bytes;
import hxmc.os.Window;
import hxmc.os.win32.User32;
import hxmc.unsafe.*;

// GfxTest's window mode on Windows: the close button pressed (WM_CLOSE,
// posted to the window's queue), and the window's pixels after the present:
// PrintWindow with PW_RENDERFULLCONTENT (which composes a flip-model swap
// chain's content), else the screen's pixels where the client area is (a
// BitBlt from the screen's DC: Wine's PrintWindow paints no swap chain).
class WinTest {
	public static function close(w:Window)
		User32.PostMessageW(w.surface.handle, WM.CLOSE, 0, 0);

	// the client area's pixels as RGBA, rows top to bottom; null: no capture
	public static function capture(w:Window, width:Int, height:Int):Null<Bytes> {
		var hwnd = w.surface.handle;
		var rgba:Null<Bytes> = null;
		Arena.scoped(a -> {
			var screen = User32.GetDC(Ptr.nil());
			var dc = Gdi32.CreateCompatibleDC(screen);
			var info = a.make(BITMAPINFOHEADER);
			info.value.biSize = 40;
			info.value.biWidth = width;
			info.value.biHeight = -height; // (top down)
			info.value.biPlanes = 1;
			info.value.biBitCount = 32;
			var bits:Ptr<Ptr> = a.alloc(8);
			var bmp = Gdi32.CreateDIBSection(dc, info, 0, bits, Ptr.nil(), 0);
			if (!bmp.isNull()) {
				var old = Gdi32.SelectObject(dc, bmp);
				var px:Ptr<UInt8> = bits.value;
				var ok = User32.PrintWindow(hwnd, dc, WM.PW_CLIENTONLY | WM.PW_RENDERFULLCONTENT) != 0;
				Gdi32.GdiFlush();
				if (!ok || !lit(px, width, height)) {
					var p = a.make(POINT);
					User32.ClientToScreen(hwnd, p);
					ok = Gdi32.BitBlt(dc, 0, 0, width, height, screen, p.value.x, p.value.y, WM.SRCCOPY) != 0;
					Gdi32.GdiFlush();
				}
				if (ok) {
					// (32 bits: B, G, R, X)
					var out = Bytes.alloc(width * height * 4);
					for (i in 0...width * height) {
						out.set(4 * i, px[4 * i + 2]);
						out.set(4 * i + 1, px[4 * i + 1]);
						out.set(4 * i + 2, px[4 * i]);
						out.set(4 * i + 3, 255);
					}
					rgba = out;
				}
				Gdi32.SelectObject(dc, old);
				Gdi32.DeleteObject(bmp);
			}
			Gdi32.DeleteDC(dc);
			User32.ReleaseDC(Ptr.nil(), screen);
		});
		return rgba;
	}

	// the centre is not black
	static function lit(px:Ptr<UInt8>, width:Int, height:Int):Bool {
		var c = 4 * ((height >> 1) * width + (width >> 1));
		return px[c] + px[c + 1] + px[c + 2] > 0;
	}
}
