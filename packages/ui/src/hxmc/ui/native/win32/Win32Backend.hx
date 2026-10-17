package hxmc.ui.native.win32;

import hxmc.os.win32.User32;
import hxmc.ui.*;
import hxmc.ui.native.*;
import hxmc.ui.native.win32.Win32;
import hxmc.unsafe.*;

// NativeBackend on Windows: a top-level window whose children are the
// standard controls (BUTTON push and auto-check, EDIT, STATIC for labels,
// comctl32's trackbar and progress bar), placed with SetWindowPos at the
// layout's positions; each control's id is its handle, so WM_COMMAND
// (BN_CLICKED, EN_CHANGE) and WM_HSCROLL find it. Controls take Segoe UI
// at the window's DPI, labels their node's font and colour (WM_CTLCOLORSTATIC).
// Measured from their text (GDI's DrawText) with the controls' frames
// around it: comctl32 5's classic look (no visual styles manifest yet).
class Win32Backend implements NativeBackend implements NativeDriver {
	static var classRegistered = false;
	static var className = Ptr.nil();
	static var instance = Ptr.nil();
	static final windows = new Map<Int, Win32Backend>();
	static var nextHandle = 1;
	static var msg:Ptr<MSG> = Ptr.nil();

	final hwnds = new Map<Int, Ptr>();
	final nodes = new Map<Int, Node>();
	final kinds = new Map<Int, Int>();
	// fonts by key, the labels' colours (COLORREF) by handle
	final fonts = new Map<String, Ptr>();
	final labelFonts = new Map<Int, Ptr>();
	final colors = new Map<Int, Int>();
	var host:Null<NativeHost>;
	var hwnd = Ptr.nil();
	var windowId = 0;
	var width = 0;
	var height = 0;
	var open = false;
	var updating = false;
	var uiFont = Ptr.nil();
	var scale = 1.0;

	public function new() {
		if (!classRegistered) register();
	}

	static function register() {
		instance = Kernel32.GetModuleHandleW(Ptr.nil());
		msg = LibC.malloc(48);
		var name = "HxmcNative", p:Ptr<UInt16> = LibC.malloc(2 * name.length + 2);
		for (i in 0...name.length)
			p[i] = name.charCodeAt(i);
		p[name.length] = 0;
		className = p;
		Arena.scoped(a -> {
			var icc:Ptr<Int32> = a.alloc(8);
			icc[0] = 8;
			icc[1] = 0x4 | 0x20;
			ComCtl.InitCommonControlsEx(icc);
			var wc = a.make(WNDCLASSEXW);
			wc.value.cbSize = 80;
			wc.value.style = 3; // CS_HREDRAW | CS_VREDRAW
			wc.value.lpfnWndProc = Callback.addr(wndProc);
			wc.value.hInstance = instance;
			wc.value.hCursor = User32.LoadCursorW(Ptr.nil(), Ptr.ofI64(32512));
			wc.value.hbrBackground = Ptr.ofI64(15 + 1); // COLOR_BTNFACE + 1
			wc.value.lpszClassName = className;
			if (User32.RegisterClassExW(wc) == 0) throw "hxmc.ui.native: RegisterClassExW failed (error " + Kernel32.GetLastError() + ")";
		});
		classRegistered = true;
	}

	public function openWindow(title:String, w:Int, h:Int, host:NativeHost) {
		this.host = host;
		windowId = nextHandle++;
		windows.set(windowId, this);
		scale = User32.GetDpiForSystem() / 96;
		var pw = Math.round(w * scale), ph = Math.round(h * scale);
		hwnd = Arena.scopedValue(a -> {
			var r = a.make(RECT);
			r.value.right = pw;
			r.value.bottom = ph;
			User32.AdjustWindowRectEx(r, 0x00CF0000 | 0x02000000, 0, 0);
			// (the window's id travels as its creation parameter: WM_CREATE has it before CreateWindowExW returns)
			W32.CreateWindowExW(0, className, a.wstring(title), 0x00CF0000 | 0x02000000, 0x80000000, 0x80000000, r.value.right - r.value.left,
				r.value.bottom - r.value.top, Ptr.nil(), Ptr.nil(), instance, Ptr.ofI64(windowId));
		});
		if (hwnd.isNull()) throw "hxmc.ui.native: CreateWindowExW failed (error " + Kernel32.GetLastError() + ")";
		measureClient();
		uiFont = font("Segoe UI", 12 * scale, 400, false);
		User32.ShowWindow(hwnd, 5);
		open = true;
	}

	function measureClient()
		Arena.scoped(a -> {
			var r = a.make(RECT);
			User32.GetClientRect(hwnd, r);
			width = r.value.right - r.value.left;
			height = r.value.bottom - r.value.top;
		});

	public function closeWindow() {
		if (!open) return;
		open = false;
		User32.DestroyWindow(hwnd);
		for (f in fonts)
			Gdi.DeleteObject(f);
		fonts.clear();
	}

	// (sizes in the layout's units: pixels over the scale)
	public function windowWidth():Int
		return Math.round(width / scale);

	public function windowHeight():Int
		return Math.round(height / scale);

	function font(family:String, px:Float, weight:Int, italic:Bool):Ptr {
		var face = family == "sans-serif" || family == "" ? "Segoe UI" : family;
		var key = face + "/" + Math.round(px) + "/" + weight + "/" + italic;
		var f = fonts.get(key);
		if (f == null) {
			f = Arena.scopedValue(a -> Gdi.CreateFontW(-Math.round(px), 0, 0, 0, weight, italic ? 1 : 0, 0, 0, 1, 0, 0, 5, 0, a.wstring(face)));
			fonts.set(key, f);
		}
		return f;
	}

	static inline var WS_CHILD = 0x40000000;
	static inline var WS_VISIBLE = 0x10000000;
	static inline var WS_TABSTOP = 0x00010000;

	public function create(n:Node):Int {
		var h = nextHandle++;
		var kind:Int = Std.isOfType(n, Control) ? (cast n : Control).kind : (ControlKind.Label : Int);
		var cls = "STATIC", style = WS_CHILD | WS_VISIBLE, ex = 0;
		switch (cast kind : ControlKind) {
			case Button:
				cls = "BUTTON";
				style |= WS_TABSTOP;
			case CheckBox:
				cls = "BUTTON";
				style |= WS_TABSTOP | 3; // BS_AUTOCHECKBOX
			case TextField:
				cls = "EDIT";
				style |= WS_TABSTOP | 0x80; // ES_AUTOHSCROLL
				ex = 0x200; // WS_EX_CLIENTEDGE
			case Slider:
				cls = "msctls_trackbar32";
				style |= WS_TABSTOP;
			case Progress:
				cls = "msctls_progress32";
			case Label:
				style |= 0x80; // SS_NOPREFIX
		}
		var w = Arena.scopedValue(a -> W32.CreateWindowExW(ex, a.wstring(cls), Ptr.nil(), style, 0, 0, 10, 10, hwnd, Ptr.ofI64(h), instance, Ptr.nil()));
		if (w.isNull()) throw "hxmc.ui.native: CreateWindowExW(" + cls + ") failed (error " + Kernel32.GetLastError() + ")";
		hwnds.set(h, w);
		nodes.set(h, n);
		kinds.set(h, kind);
		if (kind == (ControlKind.Slider : Int)) {
			W32.SendMessageW(w, 0x407, 0, 0); // TBM_SETRANGEMIN
			W32.SendMessageW(w, 0x408, 1, 1000); // TBM_SETRANGEMAX
		}
		if (kind == (ControlKind.Progress : Int)) W32.SendMessageW(w, 0x406, 0, 1000); // PBM_SETRANGE32
		if (kind != (ControlKind.Label : Int)) W32.SendMessageW(w, 0x30, uiFont.toI64(), 1); // WM_SETFONT
		return h;
	}

	public function update(h:Int, n:Node) {
		var w = hwnds.get(h);
		if (w == null) return;
		updating = true;
		Arena.scoped(a -> {
			if (Std.isOfType(n, Control)) {
				var c:Control = cast n;
				switch c.kind {
					case Button | Label:
						W32.SetWindowTextW(w, a.wstring(c.text));
					case CheckBox:
						W32.SetWindowTextW(w, a.wstring(c.text));
						W32.SendMessageW(w, 0xF1, c.checked ? 1 : 0, 0); // BM_SETCHECK
					case TextField:
						if (getText(w) != c.text) W32.SetWindowTextW(w, a.wstring(c.text));
						// (EM_SETCUEBANNER needs comctl32 6: no placeholder in the classic look)
					case Slider:
						W32.SendMessageW(w, 0x405, 1, toTicks(c, c.value)); // TBM_SETPOS
					case Progress:
						W32.SendMessageW(w, 0x402, Math.round((c.value < 0 ? 0 : c.value > 1 ? 1 : c.value) * 1000), 0); // PBM_SETPOS
				}
				W32.EnableWindow(w, c.enabled ? 1 : 0);
			} else if (Std.isOfType(n, TextNode)) {
				var t:TextNode = cast n;
				W32.SetWindowTextW(w, a.wstring(t.text));
				var f = t.font(), col = t.textColor();
				var lf = font(f.family, f.size * scale, f.weight, f.italic);
				labelFonts.set(h, lf);
				W32.SendMessageW(w, 0x30, lf.toI64(), 1);
				colors.set(h, col.r | (col.g << 8) | (col.b << 16));
			}
		});
		updating = false;
	}

	static function toTicks(c:Control, v:Float):Int64
		return Math.round(c.max > c.min ? (v - c.min) / (c.max - c.min) * 1000 : 0);

	static function getText(w:Ptr):String {
		var n = W32.GetWindowTextLengthW(w);
		return Arena.scopedValue(a -> {
			var p:Ptr<UInt16> = a.alloc(2 * n + 2);
			W32.GetWindowTextW(w, p, n + 1);
			var b = new StringBuf();
			for (i in 0...n)
				b.addChar(p[i]);
			b.toString();
		});
	}

	public function place(h:Int, x:Float, y:Float, w:Float, ht:Float) {
		var c = hwnds.get(h);
		if (c == null) return;
		W32.SetWindowPos(c, Ptr.nil(), Math.round(x * scale), Math.round(y * scale), Math.round(Math.max(1, w) * scale), Math.round(Math.max(1, ht) * scale),
			0x4 | 0x10);
	}

	public function destroy(h:Int) {
		var w = hwnds.get(h);
		if (w == null) return;
		User32.DestroyWindow(w);
		hwnds.remove(h);
		nodes.remove(h);
		kinds.remove(h);
		colors.remove(h);
		labelFonts.remove(h);
	}

	// text's extent in a font (DrawText's DT_CALCRECT; within a width: wrapped), in pixels
	function extent(s:String, f:Ptr, maxWidth:Float):Size {
		return Arena.scopedValue(a -> {
			var dc = User32.GetDC(hwnd);
			var old = Gdi.SelectObject(dc, f);
			var r = a.make(RECT);
			r.value.right = Math.isNaN(maxWidth) ? 100000 : Math.round(maxWidth);
			var flags = 0x400 | 0x800 | (Math.isNaN(maxWidth) ? 0 : 0x10); // DT_CALCRECT | DT_NOPREFIX | DT_WORDBREAK
			W32.DrawTextW(dc, a.wstring(s == "" ? " " : s), -1, r, flags);
			Gdi.SelectObject(dc, old);
			User32.ReleaseDC(hwnd, dc);
			new Size(s == "" ? 0 : r.value.right - r.value.left, r.value.bottom - r.value.top);
		});
	}

	// (the frames around the text: a push button's edges and margins, a check box's box)
	public function measure(c:Control, width:Float):Size {
		var t = extent(c.text, uiFont, Math.NaN);
		var s = switch c.kind {
			case Button: new Size(t.width + 24 * scale, Math.max(t.height + 10 * scale, 25 * scale));
			case CheckBox: new Size(t.width + 22 * scale, Math.max(t.height + 4 * scale, 17 * scale));
			case TextField: new Size(150 * scale, extent("Hg", uiFont, Math.NaN).height + 10 * scale);
			case Slider: new Size(150 * scale, 30 * scale);
			case Progress: new Size(150 * scale, 16 * scale);
			case Label: t;
		}
		return new Size(Math.ceil(s.width / scale), Math.ceil(s.height / scale));
	}

	public function measureText(s:String, f:Font, maxWidth:Float):Size {
		var e = extent(s, font(f.family, f.size * scale, f.weight, f.italic), Math.isNaN(maxWidth) ? maxWidth : maxWidth * scale);
		return new Size(Math.ceil(e.width / scale), Math.ceil(e.height / scale));
	}

	public function pump(block:Bool):Bool {
		if (!open) return false;
		if (block && User32.PeekMessageW(msg, Ptr.nil(), 0, 0, 0) == 0) dispatch(W32.GetMessageW(msg, Ptr.nil(), 0, 0) > 0);
		while (open && User32.PeekMessageW(msg, Ptr.nil(), 0, 0, 1) != 0)
			dispatch(true);
		return open;
	}

	function dispatch(got:Bool) {
		if (!got) return;
		// (Tab between the controls, as a dialog's)
		if (W32.IsDialogMessageW(hwnd, msg) != 0) return;
		User32.TranslateMessage(msg);
		User32.DispatchMessageW(msg);
	}

	// --- the window procedure ---

	static function owner(hwnd:Ptr):Null<Win32Backend> {
		for (b in windows)
			if (b.hwnd == hwnd) return b;
		return null;
	}

	@:hxmc.callback static function wndProc(hwnd:Ptr, message:Int, wParam:Int64, lParam:Int64):Int64 {
		var b = owner(hwnd);
		if (b == null) return User32.DefWindowProcW(hwnd, message, wParam, lParam);
		switch message {
			case 0x111: // WM_COMMAND: the control's id, the notification
				var id = wParam.toInt() & 0xFFFF, code = (wParam.toInt() >> 16) & 0xFFFF;
				var n = b.nodes.get(id);
				if (Std.isOfType(n, Control) && !b.updating) {
					var c:Control = cast n;
					switch c.kind {
						case Button if (code == 0): c.platformClick();
						case CheckBox if (code == 0): c.platformChecked(W32.SendMessageW(b.hwnds.get(id), 0xF0, 0, 0).toInt() == 1);
						case TextField if (code == 0x300): c.platformText(getText(b.hwnds.get(id)));
						case _:
					}
				}
				return 0;
			case 0x114: // WM_HSCROLL from a trackbar
				var id = W32.GetDlgCtrlID(Ptr.ofI64(lParam));
				var n = b.nodes.get(id);
				if (Std.isOfType(n, Control) && !b.updating) {
					var c:Control = cast n;
					var pos = W32.SendMessageW(b.hwnds.get(id), 0x400, 0, 0).toInt(); // TBM_GETPOS
					c.platformValue(c.min + pos / 1000 * (c.max - c.min));
				}
				return 0;
			case 0x138: // WM_CTLCOLORSTATIC: a label's colour on the window's background
				var id = W32.GetDlgCtrlID(Ptr.ofI64(lParam));
				var col = b.colors.get(id);
				if (col != null) {
					var dc = Ptr.ofI64(wParam);
					Gdi.SetTextColor(dc, col);
					Gdi.SetBkMode(dc, 1); // TRANSPARENT
					return W32.GetSysColorBrush(15).toI64();
				}
			case 0x0005: // WM_SIZE
				b.measureClient();
				if (b.host != null) @:privateAccess b.host.windowResized();
				return 0;
			case 0x0010: // WM_CLOSE
				b.open = false;
				if (b.host != null) @:privateAccess b.host.windowClosed();
				User32.DestroyWindow(hwnd);
				return 0;
			case _:
		}
		return User32.DefWindowProcW(hwnd, message, wParam, lParam);
	}

	// --- NativeDriver: the controls' own messages, their notifications following ---

	public function click(h:Int)
		W32.SendMessageW(hwnds.get(h), 0xF5, 0, 0); // BM_CLICK

	public function type(h:Int, s:String)
		Arena.scoped(a -> W32.SetWindowTextW(hwnds.get(h), a.wstring(s)));

	public function toggle(h:Int, on:Bool)
		if ((W32.SendMessageW(hwnds.get(h), 0xF0, 0, 0).toInt() == 1) != on) click(h);

	public function slide(h:Int, v:Float) {
		var c:Control = cast nodes.get(h);
		W32.SendMessageW(hwnds.get(h), 0x405, 1, toTicks(c, v));
		// (as the trackbar reports a drag's end to its parent)
		W32.SendMessageW(hwnd, 0x114, 8, hwnds.get(h).toI64());
	}

	public function fieldText(h:Int):String
		return getText(hwnds.get(h));

	public function sliderValue(h:Int):Float {
		var c:Control = cast nodes.get(h);
		return c.min + W32.SendMessageW(hwnds.get(h), 0x400, 0, 0).toInt() / 1000 * (c.max - c.min);
	}

	// (in the layout's units)
	public function allocation(h:Int):Array<Int> {
		var w = hwnds.get(h);
		if (w == null) return [];
		return Arena.scopedValue(a -> {
			var r = a.make(RECT);
			W32.GetWindowRect(w, r);
			W32.MapWindowPoints(Ptr.nil(), hwnd, r, 2);
			[
				Math.round(r.value.left / scale),
				Math.round(r.value.top / scale),
				Math.round((r.value.right - r.value.left) / scale),
				Math.round((r.value.bottom - r.value.top) / scale)
			];
		});
	}

	public function screenshot(path:String):Bool
		return false;
}
