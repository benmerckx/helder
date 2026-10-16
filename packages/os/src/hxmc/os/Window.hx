package hxmc.os;

import hxmc.os.cocoa.CocoaWindow;
import hxmc.os.web.CanvasWindow;
import hxmc.os.win32.Win32Window;
import hxmc.os.x11.X11Window;
import hxmc.unsafe.Mem;

// A top-level window, its size in points (pixels on X11). Its Surface
// carries the native handles for hxmc.gfx, its size in pixels. Cocoa on
// macOS (hxmc.os.cocoa.CocoaWindow), Win32 on Windows
// (hxmc.os.win32.Win32Window), a canvas in the browser (WebAssembly:
// hxmc.os.web.CanvasWindow, its size in CSS pixels), X11 elsewhere
// (hxmc.os.x11.X11Window); Wayland comes in behind the same class.
class Window {
	public final surface:Surface;
	public var title(default, null):String;
	public var closed(default, null) = false;

	// the native window, the target's (Mem.os() is known when compiling: the
	// other's code is never reached, as long as no field or method has its type)
	final native:Any;

	public function new(title:String, width:Int, height:Int) {
		this.title = title;
		native = Mem.os() == 1 ? new CocoaWindow(this, title, width, height) : Mem.os() == 2 ? new Win32Window(this, title, width,
			height) : Mem.os() == 3 ? new CanvasWindow(this, title, width, height) : new X11Window(this, title, width, height);
		surface = Mem.os() == 1 ? (cast native : CocoaWindow).surface : Mem.os() == 2 ? (cast native : Win32Window).surface :
			Mem.os() == 3 ? (cast native : CanvasWindow).surface : (cast native : X11Window).surface;
		App.windows.push(this);
	}

	// the surface's size in pixels
	public var width(get, never):Int;
	public var height(get, never):Int;

	inline function get_width()
		return surface.width;

	inline function get_height()
		return surface.height;

	// pixels per point (2 on a Retina display, the monitor's DPI / 96 on Windows,
	// the browser's devicePixelRatio; 1 on X11)
	public var scale(get, never):Float;

	function get_scale():Float
		return Mem.os() == 1 ? (cast native : CocoaWindow).scale : Mem.os() == 2 ? (cast native : Win32Window).scale : Mem.os() == 3 ? (cast native : CanvasWindow).scale : 1;

	// the pointer's shape over the window
	public var cursor(default, set):Cursor = Default;

	function set_cursor(c:Cursor):Cursor {
		if (c == cursor || closed) return c;
		cursor = c;
		if (Mem.os() == 1) (cast native : CocoaWindow).setCursor(c) else if (Mem.os() == 2) (cast native : Win32Window).setCursor(c) else if (Mem.os() == 3)
			(cast native : CanvasWindow).setCursor(c) else (cast native : X11Window).setCursor(c);
		return c;
	}

	public function close() {
		if (closed) return;
		closed = true;
		if (Mem.os() == 1) (cast native : CocoaWindow).destroy() else if (Mem.os() == 2) (cast native : Win32Window).destroy() else if (Mem.os() == 3)
			(cast native : CanvasWindow).destroy() else (cast native : X11Window).destroy();
		App.windows.remove(this);
	}
}
