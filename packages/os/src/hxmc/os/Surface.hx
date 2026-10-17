package hxmc.os;

import hxmc.unsafe.*;

// What a GPU API renders to (hxmc.gfx's Device.create): the native handles
// of a window, or of a child of one, or nothing (headless: offscreen
// rendering at a fixed size). Later kinds: Wayland (wl_display,
// wl_surface).
enum abstract SurfaceKind(Int) {
	var Headless;
	var X11;
	// an NSView hosting a CAMetalLayer (iOS: a UIView backed by one)
	var Cocoa;
	// a window (HWND)
	var Win32;
	// a canvas element in the browser (WebAssembly)
	var Canvas;
	// an ANativeWindow (Android: the activity's window)
	var Android;
}

class Surface {
	public final kind:SurfaceKind;
	// X11: the Display*; Cocoa: the CAMetalLayer*; Win32: the HINSTANCE (or nil)
	public final display:Ptr;
	// X11: the Window (an XID); Cocoa: the NSView*; Win32: the HWND; Canvas:
	// the canvas's handle in the JavaScript side's table (packages/os/browser.mjs);
	// Android: the ANativeWindow* (nil while suspended, another after a Resume: reattach)
	public var handle(default, null):Ptr;
	// Android: what the GPU back end does when the system takes the window
	// (the app goes to the background): let go of everything made on it,
	// before the window goes (a Suspend event follows; the next frame after
	// Resume renders to the new handle)
	public var lost:Null<Void->Void> = null;
	// the size in pixels
	public var width(default, null):Int;
	public var height(default, null):Int;

	public function new(kind:SurfaceKind, display:Ptr, handle:Ptr, width:Int, height:Int) {
		this.kind = kind;
		this.display = display;
		this.handle = handle;
		this.width = width;
		this.height = height;
	}

	public static function headless(width:Int, height:Int):Surface
		return new Surface(Headless, Ptr.nil(), Ptr.nil(), width, height);

	// a canvas of the page, by its element id (WebAssembly; a GPU view in
	// a page: not a Window, so no events, and its size is the one it has now)
	public static function canvas(id:String):Surface {
		var c = Arena.scopedValue(a -> hxmc.os.web.Dom.canvas(a.cstring(id)));
		if (c == 0) throw "hxmc.os: no canvas #" + id;
		return new Surface(Canvas, Ptr.nil(), Ptr.ofI64(c), hxmc.os.web.Dom.width(c), hxmc.os.web.Dom.height(c));
	}

	@:allow(hxmc.os) function resized(w:Int, h:Int) {
		width = w;
		height = h;
	}

	@:allow(hxmc.os) function reattach(h:Ptr, w:Int, ht:Int) {
		handle = h;
		width = w;
		height = ht;
	}
}
