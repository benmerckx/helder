package helder.os.win32;

import helder.os.Event;
import helder.os.TitleBar;
import helder.os.win32.User32;
import hxmc.unsafe.*;

// helder.os.Window on Windows: one window class for the process, registered
// with the first window, whose window procedure (a @:hxmc.callback) turns
// the close button into a Close event (the window stays open: no
// DefWindowProc), WM_SIZE into Resize, keys and the mouse into their
// events. The process is per-monitor DPI aware, so that sizes are pixels
// (a window's size in points times the system's scale, as on macOS). The
// loop stays App.run's: each frame drains the thread's queue without
// waiting (PeekMessage); the pace comes from the swap chain's Present.
// Characters come from WM_CHAR (TranslateMessage: UTF-16, surrogate pairs
// joined: TextInput), the wheels from WM_MOUSEWHEEL and WM_MOUSEHWHEEL; WM_DPICHANGED
// moves the window to the size Windows suggests and is a ScaleChange.
// While the user drags the window's edge or title bar, DispatchMessage runs
// Windows' own loop until the drag ends: a timer then draws the frames
// (onFrame from WM_TIMER), so that the content follows the size.
// An inset title bar (Window.titlebar Inset): WM_NCCALCSIZE takes the
// caption off (the frame's sides and bottom kept: their resize borders and
// shadow; maximised, the frame the monitor hides taken off too),
// WM_NCHITTEST answers the top edge, the app's drag regions (HTCAPTION:
// Windows moves, snaps and maximises on a double click) and its maximise
// button (HTMAXBUTTON: Windows 11's snap layouts over it, its presses
// taken here); the app draws the buttons (helder.ui's WindowControls).
@:allow(helder.os)
class Win32Window {
	static var instance = Ptr.nil(); // the HINSTANCE
	static var className = Ptr.nil(); // UTF-16, kept for the process
	static var msg:Ptr<MSG> = Ptr.nil();
	static final event = new Event();
	static final open:Array<Win32Window> = [];
	// the App.run callbacks, for the window procedure's events and frames
	static var onEvent:Null<Event->Void>;
	// WM_GETOBJECT's answer (an accessibility provider: helder.ui's UI
	// Automation adapter), given the window and the message's parameters;
	// 0: DefWindowProc's
	public static var getObject:Null<(hwnd:Ptr, wParam:Int64, lParam:Int64) -> Int64> = null;
	// WM_CTLCOLOREDIT's answer for a child edit control (helder.ui's native
	// text editors over the window: their colours), given its DC and its
	// window: a brush; 0: DefWindowProc's
	public static var editColors:Null<(dc:Ptr, child:Ptr) -> Int64> = null;
	// WM_COMMAND of a menu (helder.ui's native menu bar), given the window and
	// the command: true when handled
	public static var command:Null<(hwnd:Ptr, id:Int) -> Bool> = null;
	static var onFrame:Null<Void->Void>;
	static inline var SIZING_TIMER = 1;

	// (the child windows clipped out of its painting: native editors over it)
	static inline var STYLE = WM.WS_OVERLAPPEDWINDOW | 0x02000000;

	final owner:Window;
	final hwnd:Ptr;
	final surface:Surface;
	var scale = 1.0;
	// the cursor over the client area (WM_SETCURSOR sets it)
	var cursor = Ptr.nil();

	function new(owner:Window, title:String, width:Int, height:Int) {
		this.owner = owner;
		if (instance.isNull()) start();
		scale = User32.GetDpiForSystem() / 96;
		var w = Math.round(width * scale), h = Math.round(height * scale);
		#if hxmc.dev_host
		// (hxmc dev's host: the first window as the last build left it, its procedure and its class's this build's)
		var kept = helder.dev.Hosted.hosted() && open.length == 0 ? helder.dev.Hosted.get(helder.dev.Hosted.UI_WINDOW) : Ptr.nil();
		if (!kept.isNull()) {
			hwnd = kept;
			User32.SetWindowLongPtrW(hwnd, -4, Callback.addr(wndProc)); // GWLP_WNDPROC
			User32.SetClassLongPtrW(hwnd, -24, Callback.addr(wndProc)); // GCLP_WNDPROC
			Arena.scoped(a -> User32.SetWindowTextW(hwnd, a.wstring(title)));
			surface = new Surface(Win32, instance, hwnd, w, h);
			open.push(this);
			Shell32.DragAcceptFiles(hwnd, 1);
			hostWindow();
			measure();
			return;
		}
		#end
		hwnd = Arena.scopedValue(a -> {
			// (the outer size of a client area of w x h)
			var r = a.make(RECT);
			r.value.right = w;
			r.value.bottom = h;
			User32.AdjustWindowRectEx(r, STYLE, 0, 0);
			User32.CreateWindowExW(0, className, a.wstring(title), STYLE, WM.CW_USEDEFAULT, WM.CW_USEDEFAULT, r.value.right - r.value.left,
				r.value.bottom - r.value.top, Ptr.nil(), Ptr.nil(), instance, Ptr.nil());
		});
		if (hwnd.isNull()) throw "helder.os: CreateWindowExW failed (error " + Kernel32.GetLastError() + ")";
		// (the frame computed again, without the caption: SWP_FRAMECHANGED, NOMOVE, NOSIZE, NOZORDER, NOACTIVATE)
		if (owner.titlebar == Inset) User32.SetWindowPos(hwnd, Ptr.nil(), 0, 0, 0, 0, 0x20 | 0x1 | 0x2 | 0x4 | 0x10);
		Shell32.DragAcceptFiles(hwnd, 1);
		surface = new Surface(Win32, instance, hwnd, w, h);
		open.push(this);
		#if hxmc.dev_host
		if (helder.dev.Hosted.hosted() && open.length == 1) {
			helder.dev.Hosted.set(helder.dev.Hosted.UI_WINDOW, hwnd);
			hostWindow();
		} else if (helder.dev.Hosted.hosted()) helder.dev.Hot.onDispose(() -> if (open.indexOf(this) >= 0) destroy());
		#end
		User32.ShowWindow(hwnd, WM.SW_SHOW);
		measure();
	}

	#if hxmc.dev_host
	// (the host's window, this build's: told, as X11Window tells its; at the
	// hand-over its procedure and its class's DefWindowProcW's, so that no
	// message reaches this build's code once the host has unloaded it, until
	// the next build takes the window; the program's other windows closed)
	function hostWindow() {
		Sys.stderr().writeString("helder.dev: the host's window 0x" + StringTools.hex(haxe.Int64.toInt(hwnd.toI64())) + " (process " + helder.dev.Hosted.pid() + ")\n");
		helder.dev.Hot.onDispose(() -> if (open.indexOf(this) >= 0) {
			open.remove(this);
			User32.KillTimer(hwnd, SIZING_TIMER);
			var def = Arena.scopedValue(a -> Kernel32.GetProcAddress(Kernel32.GetModuleHandleW(a.wstring("user32.dll")), a.cstring("DefWindowProcW")));
			if (!def.isNull()) {
				User32.SetWindowLongPtrW(hwnd, -4, def); // GWLP_WNDPROC
				User32.SetClassLongPtrW(hwnd, -24, def); // GCLP_WNDPROC
			}
		});
	}
	#end

	static function start() {
		User32.SetProcessDpiAwarenessContext(Ptr.ofI64(WM.DPI_PER_MONITOR_AWARE_V2));
		instance = Kernel32.GetModuleHandleW(Ptr.nil());
		msg = LibC.malloc(48);
		var name = "HxmcWindow", p:Ptr<UInt16> = LibC.malloc(2 * name.length + 2);
		for (i in 0...name.length)
			p[i] = name.charCodeAt(i);
		p[name.length] = 0;
		className = p;
		#if hxmc.dev_host
		// (the class an earlier build registered: kept, its procedure set when its window is taken)
		if (helder.dev.Hosted.hosted() && !helder.dev.Hosted.get(helder.dev.Hosted.UI_WINDOW).isNull()) return;
		#end
		Arena.scoped(a -> {
			var wc = a.make(WNDCLASSEXW);
			wc.value.cbSize = 80;
			wc.value.style = WM.CS_HREDRAW | WM.CS_VREDRAW | WM.CS_OWNDC;
			wc.value.lpfnWndProc = Callback.addr(wndProc);
			wc.value.hInstance = instance;
			wc.value.hCursor = User32.LoadCursorW(Ptr.nil(), Ptr.ofI64(WM.IDC_ARROW));
			wc.value.lpszClassName = className;
			if (User32.RegisterClassExW(wc) == 0) throw "helder.os: RegisterClassExW failed (error " + Kernel32.GetLastError() + ")";
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
		if (Mem.os() == 2 && tsf != null) {
			(cast tsf : Tsf).dispose();
			tsf = null;
		}
		#if hxmc.dev_host
		// (handing over: the window left to the next build)
		if (helder.dev.Hosted.handingOver && helder.dev.Hosted.get(helder.dev.Hosted.UI_WINDOW) == hwnd) return;
		#end
		User32.DestroyWindow(hwnd);
	}

	function setTitle(t:String)
		Arena.scoped(a -> User32.SetWindowTextW(hwnd, a.wstring(t)));

	// (the outer size of a client area of w x h points)
	function outer(w:Int, h:Int):{w:Int, h:Int}
		return Arena.scopedValue(a -> {
			var r = a.make(RECT);
			r.value.right = Math.round(w * scale);
			r.value.bottom = Math.round(h * scale);
			User32.AdjustWindowRectEx(r, STYLE, 0, 0);
			// (inset: no caption above the client area)
			if (owner.titlebar == Inset) r.value.top = 0;
			{w: r.value.right - r.value.left, h: r.value.bottom - r.value.top};
		});

	// (SWP_NOMOVE, SWP_NOZORDER, SWP_NOACTIVATE)
	function resize(w:Int, h:Int) {
		var o = outer(w, h);
		User32.SetWindowPos(hwnd, Ptr.nil(), 0, 0, o.w, o.h, 0x2 | 0x4 | 0x10);
	}

	// on the whole monitor: borderless over it, its style and frame before kept
	var fullscreen = false;
	var savedStyle = Ptr.nil();
	final saved = [0, 0, 0, 0];

	// (GWL_STYLE -16; MONITOR_DEFAULTTONEAREST 2; SWP_FRAMECHANGED 0x20,
	// SWP_NOOWNERZORDER 0x200, SWP_NOZORDER 4, SWP_NOACTIVATE 0x10)
	function setFullscreen(on:Bool) {
		if (on == fullscreen) return;
		fullscreen = on;
		Arena.scoped(a -> {
			if (on) {
				savedStyle = User32.GetWindowLongPtrW(hwnd, -16);
				var r = a.make(RECT);
				User32.GetWindowRect(hwnd, r);
				saved[0] = r.value.left;
				saved[1] = r.value.top;
				saved[2] = r.value.right;
				saved[3] = r.value.bottom;
				var info:Ptr<Int32> = a.alloc(40);
				info[0] = 40;
				User32.GetMonitorInfoW(User32.MonitorFromWindow(hwnd, 2), info);
				// (WS_POPUP, WS_VISIBLE and WS_CLIPCHILDREN: no frame)
				User32.SetWindowLongPtrW(hwnd, -16, Ptr.ofI64((0x80000000 : Int64) | 0x10000000 | 0x02000000));
				User32.SetWindowPos(hwnd, Ptr.nil(), info[1], info[2], info[3] - info[1], info[4] - info[2], 0x20 | 0x200);
			} else {
				User32.SetWindowLongPtrW(hwnd, -16, savedStyle);
				User32.SetWindowPos(hwnd, Ptr.nil(), saved[0], saved[1], saved[2] - saved[0], saved[3] - saved[1], 0x20 | 0x200 | 0x4 | 0x10);
			}
		});
	}

	// (SW_MINIMIZE 6, SW_MAXIMIZE 3, SW_RESTORE 9)
	function minimize()
		User32.ShowWindow(hwnd, 6);

	function maximized():Bool
		return User32.IsZoomed(hwnd) != 0;

	function maximize(on:Bool)
		User32.ShowWindow(hwnd, on ? 3 : 9);

	// the frame's thickness at the window's DPI (SM_CXFRAME 32, SM_CYFRAME 33, SM_CXPADDEDBORDER 92)
	function frame(y:Bool):Int {
		var dpi = User32.GetDpiForWindow(hwnd);
		return User32.GetSystemMetricsForDpi(y ? 33 : 32, dpi) + User32.GetSystemMetricsForDpi(92, dpi);
	}

	// an inset title bar's answer at a point of the screen: the window's edges, the app's regions and buttons
	function titleHit(lParam:Int64):TitleHit
		return Arena.scopedValue(a -> {
			var p = a.make(POINT);
			p.value.x = lParam.toInt() << 16 >> 16;
			p.value.y = lParam.toInt() >> 16;
			User32.ScreenToClient(hwnd, p);
			var app = owner.titlebarAt == null ? Content : owner.titlebarAt(p.value.x, p.value.y);
			TitleBars.hit(p.value.x, p.value.y, surface.width, surface.height, frame(true), !maximized() && !fullscreen, app);
		});

	function raise() {
		User32.ShowWindow(hwnd, 9); // (SW_RESTORE)
		User32.SetForegroundWindow(hwnd);
	}

	// the client area's top left on the screen, in points
	function position():{x:Int, y:Int}
		return Arena.scopedValue(a -> {
			var p = a.make(POINT);
			User32.ClientToScreen(hwnd, p);
			{x: Math.round(p.value.x / scale), y: Math.round(p.value.y / scale)};
		});

	// (the frame's offset from the client area: AdjustWindowRectEx's; SWP_NOSIZE 1)
	function moveTo(x:Int, y:Int)
		Arena.scoped(a -> {
			var r = a.make(RECT);
			User32.AdjustWindowRectEx(r, STYLE, 0, 0);
			if (owner.titlebar == Inset) r.value.top = 0;
			User32.SetWindowPos(hwnd, Ptr.nil(), Math.round(x * scale) + r.value.left, Math.round(y * scale) + r.value.top, 0, 0, 0x1 | 0x4 | 0x10);
		});

	// a Resize not told yet (before the loop)
	var pending = false;

	// (answered at WM_GETMINMAXINFO)
	var minW = 0;
	var minH = 0;

	function setMinSize(w:Int, h:Int) {
		minW = w;
		minH = h;
	}

	// (IDC_ARROW, IDC_HAND, IDC_IBEAM, IDC_CROSS, IDC_SIZEALL, IDC_NO, IDC_SIZEWE, IDC_SIZENS;
	// no open or closed hand: IDC_HAND and IDC_SIZEALL)
	function setCursor(c:Cursor) {
		cursor = User32.LoadCursorW(Ptr.nil(), Ptr.ofI64([32512, 32649, 32513, 32515, 32646, 32648, 32644, 32645, 32649, 32646][(c : Int)]));
		User32.SetCursor(cursor);
	}

	// text input through TSF (null: not made yet, or TSF not there)
	// (a Tsf; Any, and each use under Mem.os() == 2: the other targets never
	// reach its type, nor link its libraries)
	var tsf:Any = null;

	function textInputTsf(x:Int, y:Int, width:Int, height:Int):Bool {
		if (Mem.os() == 2) {
			if (tsf == null && Tsf.available()) tsf = new Tsf(hwnd, tsfEvent);
			if (tsf != null) {
				(cast tsf : Tsf).area(x, y, width, height);
				return true;
			}
		}
		return false;
	}

	// (TSF's edits as the window's events)
	function tsfEvent(kind:EventKind, text:String, x:Int, y:Int) {
		var e = event;
		e.kind = kind;
		e.window = owner;
		e.text = text;
		e.x = x;
		e.y = y;
		e.mods = 0;
		dispatch(e);
	}

	// text input on at the caret: TSF's document manager the window's focus,
	// else (no TSF) the IME's composition at the caret, its candidates below
	// it (CFS_POINT; CFS_EXCLUDE: not over the caret's area)
	function textInputArea(x:Int, y:Int, width:Int, height:Int) {
		if (textInputTsf(x, y, width, height)) return;
		var imc = Imm32.ImmGetContext(hwnd);
		if (imc.isNull()) return;
		Arena.scoped(a -> {
			var f:Ptr<Int32> = a.alloc(32);
			f[0] = 2;
			f[1] = x;
			f[2] = y;
			f[3] = x;
			f[4] = y;
			f[5] = x + width;
			f[6] = y + height;
			Imm32.ImmSetCompositionWindow(imc, f);
			f[0] = 0;
			f[1] = 0x80;
			f[2] = x;
			f[3] = y + height;
			f[4] = x;
			f[5] = y;
			f[6] = x + width;
			f[7] = y + height;
			Imm32.ImmSetCandidateWindow(imc, f);
		});
		Imm32.ImmReleaseContext(hwnd, imc);
	}

	function stopTextInput()
		if (Mem.os() == 2 && tsf != null) (cast tsf : Tsf).focus(false);

	function textContext(text:String, start:Int, end:Int)
		if (Mem.os() == 2 && tsf != null) (cast tsf : Tsf).textContext(text, start, end);

	// the clipboard's text: UTF-16 in movable global memory (CF_UNICODETEXT),
	// which the clipboard owns once set
	function writeClipboard(text:String) {
		if (User32.OpenClipboard(hwnd) == 0) throw "helder.os: OpenClipboard failed (error " + Kernel32.GetLastError() + ")";
		User32.EmptyClipboard();
		var n = text.length;
		var mem = Kernel32.GlobalAlloc(2, (2 * n + 2 : Int64)); // GMEM_MOVEABLE
		if (mem.isNull()) {
			User32.CloseClipboard();
			throw "helder.os: GlobalAlloc failed";
		}
		var p:Ptr<UInt16> = Kernel32.GlobalLock(mem);
		for (i in 0...n)
			p[i] = StringTools.fastCodeAt(text, i);
		p[n] = 0;
		Kernel32.GlobalUnlock(mem);
		if (User32.SetClipboardData(13, mem).isNull()) Kernel32.GlobalFree(mem);
		User32.CloseClipboard();
	}

	function readClipboard():Null<String> {
		if (User32.OpenClipboard(hwnd) == 0) return null;
		var mem = User32.GetClipboardData(13);
		var text:Null<String> = null;
		if (!mem.isNull()) {
			var p:Ptr<UInt16> = Kernel32.GlobalLock(mem);
			if (!p.isNull()) {
				var max = Kernel32.GlobalSize(mem).toInt() >> 1, b = new StringBuf(), i = 0;
				while (i < max && p[i] != 0) {
					b.addChar(p[i]);
					i++;
				}
				text = b.toString();
				Kernel32.GlobalUnlock(mem);
			}
		}
		User32.CloseClipboard();
		return text;
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
		for (w in open.copy())
			if (w.pending) {
				w.pending = false;
				var e = event;
				e.kind = Resize;
				e.window = w.owner;
				e.x = w.surface.width;
				e.y = w.surface.height;
				dispatch(e);
			}
		while (User32.PeekMessageW(msg, Ptr.nil(), 0, 0, WM.PM_REMOVE) != 0) {
			User32.TranslateMessage(msg);
			User32.DispatchMessageW(msg);
		}
	}

	// waits for a message in the thread's queue, or seconds
	static function wait(seconds:Float)
		User32.MsgWaitForMultipleObjects(0, Ptr.nil(), 0, Std.int(seconds * 1000), WM.QS_ALLINPUT);

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
			case WM.GETOBJECT if (getObject != null):
				var r = getObject(hwnd, wParam, lParam);
				var none:Int64 = 0;
				if (r != none) return r;
			case 0x0111 if (command != null && lParam.toInt() == 0 && (wParam.toInt() >>> 16) == 0): // WM_COMMAND, a menu's
				if (command(hwnd, wParam.toInt() & 0xFFFF)) return 0;
			case 0x0133 if (editColors != null): // WM_CTLCOLOREDIT
				var r = editColors(Ptr.ofI64(wParam), Ptr.ofI64(lParam));
				var none:Int64 = 0;
				if (r != none) return r;
			case 0x0083 if (w.owner.titlebar == Inset && wParam.toInt() != 0 && !w.fullscreen): // WM_NCCALCSIZE
				// (NCCALCSIZE_PARAMS' first RECT: the window's, made the client area's)
				var r:Ptr<RECT> = Ptr.ofI64(lParam), fx = w.frame(false), fy = w.frame(true);
				r.value.left += fx;
				r.value.right -= fx;
				r.value.bottom -= fy;
				if (User32.IsZoomed(hwnd) != 0) r.value.top += fy;
				return 0;
			case 0x0084 if (w.owner.titlebar == Inset && !w.fullscreen): // WM_NCHITTEST
				var d = User32.DefWindowProcW(hwnd, message, wParam, lParam);
				if (d.toInt() != WM.HTCLIENT) return d;
				return TitleBars.win32(w.titleHit(lParam));
			case 0x00A0 if (w.owner.titlebar == Inset && wParam.toInt() == 9): // WM_NCMOUSEMOVE over HTMAXBUTTON: the app's button hovered
				Arena.scoped(a -> {
					var p = a.make(POINT);
					p.value.x = lParam.toInt() << 16 >> 16;
					p.value.y = lParam.toInt() >> 16;
					User32.ScreenToClient(hwnd, p);
					e.kind = MouseMove;
					e.x = p.value.x;
					e.y = p.value.y;
				});
				dispatch(e);
				return 0;
			case 0x00A1 if (w.owner.titlebar == Inset && wParam.toInt() == 9): // WM_NCLBUTTONDOWN: not Windows' own button
				return 0;
			case 0x00A2 if (w.owner.titlebar == Inset && wParam.toInt() == 9): // WM_NCLBUTTONUP: maximised or back
				w.maximize(!w.maximized());
				return 0;
			case WM.GETMINMAXINFO if (w.minW > 0 || w.minH > 0):
				// (MINMAXINFO's ptMinTrackSize, at 24: the outer size)
				var o = w.outer(w.minW, w.minH), p:Ptr = Ptr.ofI64(lParam);
				(p.add(24) : Ptr<Int32>).value = o.w;
				(p.add(28) : Ptr<Int32>).value = o.h;
				return 0;
			case WM.SETCURSOR if (lParam.toInt() & 0xFFFF == WM.HTCLIENT && !w.cursor.isNull()):
				User32.SetCursor(w.cursor);
				return 1;
			case WM.CLOSE:
				e.kind = Close;
				dispatch(e);
				return 0;
			case WM.PAINT:
				// (DefWindowProc validates the window)
				e.kind = Redraw;
			case WM.SIZE:
				// (no loop yet, a size set before App.run: told at its first poll)
				if (w.measure()) {
					if (onEvent == null) w.pending = true else {
						e.kind = Resize;
						e.x = w.surface.width;
						e.y = w.surface.height;
					}
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
			case WM.MOUSEWHEEL | WM.MOUSEHWHEEL:
				// (WHEEL_DELTA, 120, a notch: 40 pixels, a precision touchpad's
				// part of one in proportion; the position in screen coordinates)
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
					e.kind = Scroll;
					e.mods = mods();
					var px = delta / 120 * 40 * w.scale;
					// (the vertical wheel up is positive, the horizontal one right)
					e.deltaX = message == WM.MOUSEHWHEEL ? px : 0;
					e.deltaY = message == WM.MOUSEWHEEL ? -px : 0;
					dispatch(e);
					return 0;
				}
			case WM.DPICHANGED:
				// (the new DPI, then the size Windows suggests for it: a Resize from WM_SIZE)
				w.scale = (wParam.toInt() & 0xFFFF) / 96;
				e.kind = ScaleChange;
				dispatch(e);
				var r:Ptr<RECT> = Ptr.ofI64(lParam);
				User32.SetWindowPos(hwnd, Ptr.nil(), r.value.left, r.value.top, r.value.right - r.value.left, r.value.bottom - r.value.top,
					WM.SWP_NOZORDER | WM.SWP_NOACTIVATE);
				return 0;
			case 0x0233: // WM_DROPFILES: the paths (UTF-16), where they were dropped
				var drop = Ptr.ofI64(wParam), files = [];
				var n = Shell32.DragQueryFileW(drop, -1, Ptr.nil(), 0);
				for (i in 0...n) {
					var len = Shell32.DragQueryFileW(drop, i, Ptr.nil(), 0);
					var buf:Ptr<UInt16> = LibC.malloc((2 * len + 2 : Int64));
					Shell32.DragQueryFileW(drop, i, buf, len + 1);
					var b = new StringBuf(), k = 0;
					while (k < len && buf[k] != 0) {
						var c:Int = buf[k++];
						// (a surrogate pair: one code point)
						if (c >= 0xD800 && c < 0xDC00 && k < len) c = 0x10000 + ((c - 0xD800) << 10) + ((buf[k++] : Int) - 0xDC00);
						b.addChar(c);
					}
					LibC.free(buf);
					files.push(b.toString());
				}
				Arena.scoped(a -> {
					var p = a.make(POINT);
					Shell32.DragQueryPoint(drop, p);
					e.x = p.value.x;
					e.y = p.value.y;
				});
				Shell32.DragFinish(drop);
				if (files.length > 0) {
					e.kind = Drop;
					e.files = files;
					dispatch(e);
				}
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
			case 0x24: 0xFF50; // Home
			case 0x23: 0xFF57; // End
			case 0x21: 0xFF55; // Prior (Page Up)
			case 0x22: 0xFF56; // Next (Page Down)
			case 0x2D: 0xFF63; // Insert
			case 0x5D: 0xFF67; // Menu (VK_APPS)
			case v if (v >= 0x70 && v <= 0x7B): 0xFFBE + v - 0x70; // F1 to F12
			case _: 0;
		}
	}
}
