package hxmc.os;

import hxmc.os.cocoa.CocoaWindow;
import hxmc.os.x11.X11Window;
import hxmc.unsafe.Mem;

// A top-level window, its size in points (pixels on X11). Its Surface
// carries the native handles for hxmc.gfx, its size in pixels. Cocoa on
// macOS (hxmc.os.cocoa.CocoaWindow), X11 elsewhere (hxmc.os.x11.X11Window);
// Win32, Wayland and the browser's canvas come in behind the same class.
class Window {
	public final surface:Surface;
	public var title(default, null):String;
	public var closed(default, null) = false;

	// the native window, the target's (Mem.os() is known when compiling: the
	// other's code is never reached, as long as no field or method has its type)
	final native:Any;

	public function new(title:String, width:Int, height:Int) {
		this.title = title;
		native = Mem.os() == 1 ? new CocoaWindow(this, title, width, height) : new X11Window(this, title, width, height);
		surface = Mem.os() == 1 ? (cast native : CocoaWindow).surface : (cast native : X11Window).surface;
		App.windows.push(this);
	}

	// the surface's size in pixels
	public var width(get, never):Int;
	public var height(get, never):Int;

	inline function get_width()
		return surface.width;

	inline function get_height()
		return surface.height;

	// pixels per point (2 on a Retina display; 1 on X11)
	public var scale(get, never):Float;

	function get_scale():Float
		return Mem.os() == 1 ? (cast native : CocoaWindow).scale : 1;

	public function close() {
		if (closed) return;
		closed = true;
		if (Mem.os() == 1) (cast native : CocoaWindow).destroy() else (cast native : X11Window).destroy();
		App.windows.remove(this);
	}
}
