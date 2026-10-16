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
// Characters come from WM_CHAR (TranslateMessage: UTF-16, surrogate pairs
// joined), the wheels from WM_MOUSEWHEEL and WM_MOUSEHWHEEL; WM_DPICHANGED
// moves the window to the size Windows suggests and is a ScaleChange.
// While the user drags the window's edge or title bar, DispatchMessage runs
// Windows' own loop until the drag ends: a timer then draws the frames
// (onFrame from WM_TIMER), so that the content follows the size.
@:allow(hxmc.os)
class Win32Window {
	static var instance = Ptr.nil(); // the HINSTANCE
	static var className = Ptr.nil(); // UTF-16, kept for the process
	static var msg:Ptr<MSG> = Ptr.nil();
	static final event = new Event();
	static final open:Array<Win32Window> = [];
	// the App.run callbacks, for the window procedure's events and frames
	static var onEvent:Null<Event->Void>;
	static var onFrame:Null<Void->Void>;
	static var surrogate = 0; // the high surrogate of the next WM_CHAR
	static inline var SIZING_TIMER = 1;

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
	static function poll(onFrame:Void->Void, onEvent:Event->Void) {
		Win32Window.onFrame = onFrame;
		Win32Window.onEvent = onEvent;
		while (User32.PeekMessageW(msg, Ptr.nil(), 0, 0, WM.PM_REMOVE) != 0) {
			User32.TranslateMessage(msg);
			User32.DispatchMessageW(msg);
		}
	}

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
				// (signed 16-bit client coordinates)
				e.x = lParam.toInt() << 16 >> 16;
				e.y = lParam.toInt() >> 16;
			case WM.MOUSEWHEEL | WM.MOUSEHWHEEL:
				// (120 a notch; the position in screen coordinates)
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
					e.kind = Wheel;
					e.dx = message == WM.MOUSEHWHEEL ? delta / 120 : 0;
					e.dy = message == WM.MOUSEWHEEL ? delta / 120 : 0;
					dispatch(e);
					return 0;
				}
			case WM.CHAR:
				var c = wParam.toInt() & 0xFFFF;
				if (c >= 0xD800 && c < 0xDC00) {
					surrogate = c;
					return 0;
				}
				if (c >= 0xDC00 && c < 0xE000) {
					c = surrogate == 0 ? 0 : 0x10000 + ((surrogate - 0xD800) << 10) + (c - 0xDC00);
					surrogate = 0;
				}
				if (c >= 0x20 && c != 0x7F) {
					e.kind = Text;
					e.char = c;
					dispatch(e);
				}
				return 0;
			case WM.DPICHANGED:
				// (the new DPI, then the size Windows suggests for it: a Resize from WM_SIZE)
				w.scale = (wParam.toInt() & 0xFFFF) / 96;
				e.kind = ScaleChange;
				dispatch(e);
				var r:Ptr<RECT> = Ptr.ofI64(lParam);
				User32.SetWindowPos(hwnd, Ptr.nil(), r.value.left, r.value.top, r.value.right - r.value.left, r.value.bottom - r.value.top,
					WM.SWP_NOZORDER | WM.SWP_NOACTIVATE);
				return 0;
			case WM.ENTERSIZEMOVE:
				User32.SetTimer(hwnd, SIZING_TIMER, 10, Ptr.nil());
			case WM.EXITSIZEMOVE:
				User32.KillTimer(hwnd, SIZING_TIMER);
			case WM.TIMER if (wParam == SIZING_TIMER):
				// (a frame inside Windows' loop of a drag)
				if (onFrame != null && App.windows.length > 0) onFrame();
				return 0;
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
