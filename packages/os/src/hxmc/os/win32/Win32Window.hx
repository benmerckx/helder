package hxmc.os.win32;

import hxmc.os.Event;
import hxmc.os.win32.User32;
import hxmc.unsafe.*;

// hxmc.os.Window on Windows: one window class for the process, registered
// with the first window, whose window procedure (a @:hxmc.callback) turns
// the close button into a Close event (the window stays open: no
// DefWindowProc), WM_SIZE into Resize, keys and the mouse into their
// events. The process is per-monitor DPI aware, so that sizes are pixels
// (a window's size in points times the system's scale, as on macOS). The
// loop stays App.run's: each frame drains the thread's queue without
// waiting (PeekMessage); the pace comes from the swap chain's Present.
@:allow(hxmc.os)
class Win32Window {
	static var instance = Ptr.nil(); // the HINSTANCE
	static var className = Ptr.nil(); // UTF-16, kept for the process
	static var msg:Ptr<MSG> = Ptr.nil();
	static final event = new Event();
	static final open:Array<Win32Window> = [];
	// the App.run callback, for the window procedure's events
	static var onEvent:Null<Event->Void>;

	static inline var STYLE = WM.WS_OVERLAPPEDWINDOW;

	final owner:Window;
	final hwnd:Ptr;
	final surface:Surface;
	var scale = 1.0;

	function new(owner:Window, title:String, width:Int, height:Int) {
		this.owner = owner;
		if (instance.isNull()) start();
		scale = User32.GetDpiForSystem() / 96;
		var w = Math.round(width * scale), h = Math.round(height * scale);
		hwnd = Arena.scopedValue(a -> {
			// (the outer size of a client area of w x h)
			var r = a.make(RECT);
			r.value.right = w;
			r.value.bottom = h;
			User32.AdjustWindowRectEx(r, STYLE, 0, 0);
			User32.CreateWindowExW(0, className, a.wstring(title), STYLE, WM.CW_USEDEFAULT, WM.CW_USEDEFAULT, r.value.right - r.value.left,
				r.value.bottom - r.value.top, Ptr.nil(), Ptr.nil(), instance, Ptr.nil());
		});
		if (hwnd.isNull()) throw "hxmc.os: CreateWindowExW failed (error " + Kernel32.GetLastError() + ")";
		surface = new Surface(Win32, instance, hwnd, w, h);
		open.push(this);
		User32.ShowWindow(hwnd, WM.SW_SHOW);
		measure();
	}

	static function start() {
		User32.SetProcessDpiAwarenessContext(Ptr.ofI64(WM.DPI_PER_MONITOR_AWARE_V2));
		instance = Kernel32.GetModuleHandleW(Ptr.nil());
		msg = LibC.malloc(48);
		var name = "HxmcWindow", p:Ptr<UInt16> = LibC.malloc(2 * name.length + 2);
		for (i in 0...name.length)
			p[i] = name.charCodeAt(i);
		p[name.length] = 0;
		className = p;
		Arena.scoped(a -> {
			var wc = a.make(WNDCLASSEXW);
			wc.value.cbSize = 80;
			wc.value.style = WM.CS_HREDRAW | WM.CS_VREDRAW | WM.CS_OWNDC;
			wc.value.lpfnWndProc = Callback.addr(wndProc);
			wc.value.hInstance = instance;
			wc.value.hCursor = User32.LoadCursorW(Ptr.nil(), Ptr.ofI64(WM.IDC_ARROW));
			wc.value.lpszClassName = className;
			if (User32.RegisterClassExW(wc) == 0) throw "hxmc.os: RegisterClassExW failed (error " + Kernel32.GetLastError() + ")";
		});
	}

	// the client area's size in pixels; true when it changed
	function measure():Bool {
		var changed = Arena.scopedValue(a -> {
			var r = a.make(RECT);
			User32.GetClientRect(hwnd, r);
			var w = r.value.right - r.value.left, h = r.value.bottom - r.value.top;
			// (minimized: a size of 0, kept as it was)
			if (w == 0 || h == 0 || (w == surface.width && h == surface.height)) false else {
				surface.resized(w, h);
				true;
			}
		});
		scale = User32.GetDpiForWindow(hwnd) / 96;
		return changed;
	}

	function destroy() {
		open.remove(this);
		User32.DestroyWindow(hwnd);
	}

	static function find(hwnd:Ptr):Null<Win32Window> {
		for (w in open)
			if (w.hwnd == hwnd) return w;
		return null;
	}

	// dispatches the pending events (through the window procedure)
	static function poll(onEvent:Event->Void) {
		Win32Window.onEvent = onEvent;
		while (User32.PeekMessageW(msg, Ptr.nil(), 0, 0, WM.PM_REMOVE) != 0) {
			User32.TranslateMessage(msg);
			User32.DispatchMessageW(msg);
		}
	}

	static var highSurrogate = 0;

	// the modifiers held (VK_SHIFT, VK_CONTROL, VK_MENU: Alt, VK_LWIN, VK_RWIN)
	static function mods():Int
		return (User32.GetKeyState(0x10) < 0 ? Mods.SHIFT : 0) | (User32.GetKeyState(0x11) < 0 ? Mods.CONTROL : 0) | (User32.GetKeyState(0x12) < 0 ? Mods.ALT : 0)
			| (User32.GetKeyState(0x5B) < 0 || User32.GetKeyState(0x5C) < 0 ? Mods.META : 0);

	@:hxmc.callback static function wndProc(hwnd:Ptr, message:Int, wParam:Int64, lParam:Int64):Int64 {
		var w = find(hwnd);
		if (w == null) return User32.DefWindowProcW(hwnd, message, wParam, lParam);
		var e = event;
		e.kind = None;
		e.window = w.owner;
		switch message {
			case WM.CLOSE:
				e.kind = Close;
				dispatch(e);
				return 0;
			case WM.SIZE:
				if (w.measure()) {
					e.kind = Resize;
					e.x = w.surface.width;
					e.y = w.surface.height;
				}
			case WM.KEYDOWN | WM.KEYUP | WM.SYSKEYDOWN | WM.SYSKEYUP:
				e.kind = message == WM.KEYDOWN || message == WM.SYSKEYDOWN ? KeyDown : KeyUp;
				e.key = keySym(wParam.toInt());
				e.mods = mods();
			case WM.CHAR:
				// (UTF-16: a surrogate pair comes as two messages)
				var c = wParam.toInt() & 0xFFFF;
				if (c >= 0xD800 && c < 0xDC00) {
					highSurrogate = c;
					return 0;
				}
				if (c >= 0xDC00 && c < 0xE000 && highSurrogate != 0) c = 0x10000 + ((highSurrogate - 0xD800) << 10) + (c - 0xDC00);
				highSurrogate = 0;
				if (c >= 0x20 && c != 0x7F) {
					e.kind = TextInput;
					e.text = String.fromCharCode(c);
					e.mods = mods();
					dispatch(e);
				}
				return 0;
			case WM.MOUSEMOVE | WM.LBUTTONDOWN | WM.LBUTTONUP | WM.RBUTTONDOWN | WM.RBUTTONUP | WM.MBUTTONDOWN | WM.MBUTTONUP:
				e.kind = switch message {
					case WM.MOUSEMOVE: MouseMove;
					case WM.LBUTTONDOWN | WM.RBUTTONDOWN | WM.MBUTTONDOWN: MouseDown;
					case _: MouseUp;
				}
				e.button = switch message {
					case WM.LBUTTONDOWN | WM.LBUTTONUP: 1;
					case WM.MBUTTONDOWN | WM.MBUTTONUP: 2;
					case WM.RBUTTONDOWN | WM.RBUTTONUP: 3;
					case _: 0;
				}
				e.mods = mods();
				// (signed 16-bit client coordinates)
				e.x = lParam.toInt() << 16 >> 16;
				e.y = lParam.toInt() >> 16;
			case WM.MOUSEWHEEL:
				// (the wheel as X11 has it: a press and a release of button 4 or 5;
				// the position in screen coordinates)
				var delta = wParam.toInt() >> 16;
				if (delta != 0) {
					Arena.scoped(a -> {
						var p = a.make(POINT);
						p.value.x = lParam.toInt() << 16 >> 16;
						p.value.y = lParam.toInt() >> 16;
						User32.ScreenToClient(hwnd, p);
						e.x = p.value.x;
						e.y = p.value.y;
					});
					e.kind = MouseDown;
					e.button = delta > 0 ? 4 : 5;
					dispatch(e);
					e.kind = MouseUp;
					dispatch(e);
					return 0;
				}
			case _:
		}
		if (e.kind != None) dispatch(e);
		return User32.DefWindowProcW(hwnd, message, wParam, lParam);
	}

	static function dispatch(e:Event)
		if (onEvent != null) onEvent(e);

	// a virtual-key code as an X11 KeySym (Event.key): letters lower case,
	// digits and space as they are, the others by table
	static function keySym(vk:Int):Int {
		if (vk >= "A".code && vk <= "Z".code) return vk + 32;
		if ((vk >= "0".code && vk <= "9".code) || vk == " ".code) return vk;
		return switch vk {
			case 0x1B: 0xFF1B; // Escape
			case 0x0D: 0xFF0D; // Return
			case 0x09: 0xFF09; // Tab
			case 0x08: 0xFF08; // BackSpace
			case 0x2E: 0xFFFF; // Delete
			case 0x25: 0xFF51; // Left
			case 0x26: 0xFF52; // Up
			case 0x27: 0xFF53; // Right
			case 0x28: 0xFF54; // Down
			case 0x10: 0xFFE1; // Shift_L
			case 0x11: 0xFFE3; // Control_L
			case 0x12: 0xFFE9; // Alt_L
			case _: 0;
		}
	}
}
