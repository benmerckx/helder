package hxmc.os.x11;

import hxmc.unsafe.*;

// Xlib (libX11.so.6, the dynamic glibc mode: -D hxmc.libc=glibc): the calls
// a window needs. A Display* is a Ptr; XIDs (Window, Atom, KeySym) and
// pixels are C's unsigned long: Int64. Calls run in a safe region
// (XNextEvent blocks). Strings are Ptr: a CString or a Mem.cstr literal.
@:hxmc.c @:hxmc.lib("libX11.so.6") extern class Xlib {
	static function XOpenDisplay(name:Ptr):Ptr;
	static function XCloseDisplay(d:Ptr):Int;
	static function XDefaultScreen(d:Ptr):Int;
	static function XRootWindow(d:Ptr, screen:Int):Int64;
	static function XBlackPixel(d:Ptr, screen:Int):Int64;
	static function XCreateSimpleWindow(d:Ptr, parent:Int64, x:Int, y:Int, width:Int, height:Int, borderWidth:Int, border:Int64,
		background:Int64):Int64;
	static function XDestroyWindow(d:Ptr, w:Int64):Int;
	static function XStoreName(d:Ptr, w:Int64, name:Ptr):Int;
	static function XSelectInput(d:Ptr, w:Int64, mask:Int64):Int;
	static function XMapWindow(d:Ptr, w:Int64):Int;
	static function XInternAtom(d:Ptr, name:Ptr, onlyIfExists:Int):Int64;
	static function XSetWMProtocols(d:Ptr, w:Int64, protocols:Ptr<Int64>, count:Int):Int;
	static function XPending(d:Ptr):Int;
	static function XNextEvent(d:Ptr, event:Ptr<XAnyEvent>):Int;
	static function XLookupKeysym(event:Ptr<XKeyEvent>, index:Int):Int64;
	// the key's text (Latin-1, up to size bytes: the count) and KeySym
	static function XLookupString(event:Ptr<XKeyEvent>, buffer:Ptr, size:Int, keysym:Ptr<Int64>, status:Ptr):Int;
	static function XKeysymToKeycode(d:Ptr, keysym:Int64):Int;
	static function XFlush(d:Ptr):Int;
	static function XSendEvent(d:Ptr, w:Int64, propagate:Int, mask:Int64, event:Ptr<XAnyEvent>):Int;
	// an XImage* of the window's pixels (ZPixmap: 32 bits per pixel on a 24-bit visual)
	static function XGetImage(d:Ptr, drawable:Int64, x:Int, y:Int, width:Int, height:Int, planes:Int64, format:Int):Ptr<XImage>;
	static function XDestroyImage(image:Ptr<XImage>):Int;
}

// XEvent is a union of 192 bytes (24 longs): an XEvent buffer is read
// through the struct of its type
class X {
	public static inline var EVENT_SIZE = 192;
	// event types
	public static inline var KeyPress = 2;
	public static inline var KeyRelease = 3;
	public static inline var ButtonPress = 4;
	public static inline var ButtonRelease = 5;
	public static inline var MotionNotify = 6;
	public static inline var ConfigureNotify = 22;
	public static inline var ClientMessage = 33;
	// input masks
	public static inline var KeyPressMask = 1 << 0;
	public static inline var KeyReleaseMask = 1 << 1;
	public static inline var ButtonPressMask = 1 << 2;
	public static inline var ButtonReleaseMask = 1 << 3;
	public static inline var PointerMotionMask = 1 << 6;
	public static inline var ExposureMask = 1 << 15;
	public static inline var StructureNotifyMask = 1 << 17;
	public static inline var ZPixmap = 2;
}

@:hxmc.struct @:publicFields class XAnyEvent {
	var type:Int32;
	var serial:Int64;
	var send_event:Int32;
	var display:Ptr;
	var window:Int64;
}

// KeyPress, KeyRelease; ButtonPress and ButtonRelease (XButtonEvent: `button`
// where `keycode` is) and MotionNotify share its prefix
@:hxmc.struct @:publicFields class XKeyEvent {
	var type:Int32;
	var serial:Int64;
	var send_event:Int32;
	var display:Ptr;
	var window:Int64;
	var root:Int64;
	var subwindow:Int64;
	var time:Int64;
	var x:Int32;
	var y:Int32;
	var x_root:Int32;
	var y_root:Int32;
	var state:UInt32;
	var keycode:UInt32;
	var same_screen:Int32;
}

@:hxmc.struct @:publicFields class XConfigureEvent {
	var type:Int32;
	var serial:Int64;
	var send_event:Int32;
	var display:Ptr;
	var event:Int64;
	var window:Int64;
	var x:Int32;
	var y:Int32;
	var width:Int32;
	var height:Int32;
	var border_width:Int32;
	var above:Int64;
	var override_redirect:Int32;
}

@:hxmc.struct @:publicFields class XClientMessageEvent {
	var type:Int32;
	var serial:Int64;
	var send_event:Int32;
	var display:Ptr;
	var window:Int64;
	var message_type:Int64;
	var format:Int32;
	var l0:Int64; // data.l[0]
}

// the fields of XImage up to its function table
@:hxmc.struct @:publicFields class XImage {
	var width:Int32;
	var height:Int32;
	var xoffset:Int32;
	var format:Int32;
	var data:Ptr<UInt8>;
	var byte_order:Int32;
	var bitmap_unit:Int32;
	var bitmap_bit_order:Int32;
	var bitmap_pad:Int32;
	var depth:Int32;
	var bytes_per_line:Int32;
	var bits_per_pixel:Int32;
}
