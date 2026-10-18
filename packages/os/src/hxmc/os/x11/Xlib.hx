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
	static function XResizeWindow(d:Ptr, w:Int64, width:Int, height:Int):Int;
	static function XSetWMNormalHints(d:Ptr, w:Int64, hints:Ptr):Void;
	static function XSelectInput(d:Ptr, w:Int64, mask:Int64):Int;
	static function XMapWindow(d:Ptr, w:Int64):Int;
	#if hxmc.dev_host
	static function XCloseIM(im:Ptr):Int;
	#end
	static function XInternAtom(d:Ptr, name:Ptr, onlyIfExists:Int):Int64;
	static function XSetWMProtocols(d:Ptr, w:Int64, protocols:Ptr<Int64>, count:Int):Int;
	static function XPending(d:Ptr):Int;
	static function XNextEvent(d:Ptr, event:Ptr<XAnyEvent>):Int;
	static function XLookupKeysym(event:Ptr<XKeyEvent>, index:Int):Int64;
	// the key's characters (Latin-1) and KeySym with the modifiers applied
	static function XLookupString(event:Ptr<XKeyEvent>, buffer:Ptr, bytes:Int, keysym:Ptr<Int64>, status:Ptr):Int;
	static function XKeysymToKeycode(d:Ptr, keysym:Int64):Int;
	static function XFlush(d:Ptr):Int;
	// the connection's socket (to wait on with select)
	static function XConnectionNumber(d:Ptr):Int;
	static function XSendEvent(d:Ptr, w:Int64, propagate:Int, mask:Int64, event:Ptr<XAnyEvent>):Int;
	// an XImage* of the window's pixels (ZPixmap: 32 bits per pixel on a 24-bit visual)
	static function XGetImage(d:Ptr, drawable:Int64, x:Int, y:Int, width:Int, height:Int, planes:Int64, format:Int):Ptr<XImage>;
	static function XDestroyImage(image:Ptr<XImage>):Int;
	// selections (the clipboard): owning one, asking its owner for it, the
	// properties its text travels in
	static function XSetSelectionOwner(d:Ptr, selection:Int64, owner:Int64, time:Int64):Int;
	static function XGetSelectionOwner(d:Ptr, selection:Int64):Int64;
	static function XConvertSelection(d:Ptr, selection:Int64, target:Int64, property:Int64, requestor:Int64, time:Int64):Int;
	static function XChangeProperty(d:Ptr, w:Int64, property:Int64, type:Int64, format:Int, mode:Int, data:Ptr, count:Int):Int;
	static function XGetWindowProperty(d:Ptr, w:Int64, property:Int64, offset:Int64, length:Int64, delete:Int, type:Int64, actualType:Ptr<Int64>,
		actualFormat:Ptr<Int32>, count:Ptr<Int64>, after:Ptr<Int64>, data:Ptr<Ptr>):Int;
	static function XDeleteProperty(d:Ptr, w:Int64, property:Int64):Int;
	static function XFree(data:Ptr):Int;
	// the input method (any keyboard layout, dead keys, compose sequences):
	// opened once, a context per window; events it takes are filtered out
	static function XSetLocaleModifiers(modifiers:Ptr):Ptr;
	static function XOpenIM(d:Ptr, db:Ptr, resName:Ptr, resClass:Ptr):Ptr;
	@:hxmc.varargs(1) static function XCreateIC(im:Ptr, n1:Ptr, v1:Int64, n2:Ptr, v2:Int64, n3:Ptr, v3:Int64, end:Ptr):Ptr;
	static function XDestroyIC(ic:Ptr):Void;
	static function XSetICFocus(ic:Ptr):Void;
	static function XFilterEvent(event:Ptr<XAnyEvent>, w:Int64):Int;
	static function Xutf8LookupString(ic:Ptr, event:Ptr<XKeyEvent>, buffer:Ptr, bytes:Int, keysym:Ptr<Int64>, status:Ptr<Int32>):Int;
	// the keyboard's mapping (tests: a key given another symbol)
	static function XDisplayKeycodes(d:Ptr, min:Ptr<Int32>, max:Ptr<Int32>):Int;
	static function XChangeKeyboardMapping(d:Ptr, first:Int, perKeycode:Int, keysyms:Ptr<Int64>, count:Int):Int;
	static function XSync(d:Ptr, discard:Int):Int;
	// a MappingNotify: the keyboard mapping Xlib keeps read again
	static function XRefreshKeyboardMapping(event:Ptr<XAnyEvent>):Int;
	// where a window is on the screen (its origin in the root window's coordinates)
	static function XDefaultRootWindow(d:Ptr):Int64;
	static function XTranslateCoordinates(d:Ptr, src:Int64, dest:Int64, x:Int, y:Int, outX:Ptr<Int32>, outY:Ptr<Int32>, child:Ptr<Int64>):Int;
	// a cursor of the cursor font (X11/cursorfont.h's shapes)
	static function XCreateFontCursor(d:Ptr, shape:Int):Int64;
	static function XDefineCursor(d:Ptr, w:Int64, cursor:Int64):Int;
}

// select(2), to wait on the connection's socket: in a safe region (it
// blocks), where hxmc.unsafe.Posix's calls are fast ones; setlocale for the
// input method (its character set: UTF-8)
@:hxmc.c @:hxmc.lib("libc.so.6") extern class Select {
	static function select(n:Int, r:Ptr, w:Ptr, e:Ptr, timeout:Ptr):Int;
	static function setlocale(category:Int, locale:Ptr):Ptr;
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
	public static inline var Expose = 12;
	public static inline var SelectionClear = 29;
	public static inline var SelectionRequest = 30;
	public static inline var SelectionNotify = 31;
	public static inline var PropertyNotify = 28;
	public static inline var PropertyNewValue = 0;
	public static inline var PropertyDelete = 1;
	public static inline var PropModeReplace = 0;
	public static inline var AnyPropertyType = 0;
	public static inline var XA_ATOM = 4;
	public static inline var XA_STRING = 31;
	public static inline var ConfigureNotify = 22;
	public static inline var ClientMessage = 33;
	public static inline var MappingNotify = 34;
	// input masks
	public static inline var KeyPressMask = 1 << 0;
	public static inline var KeyReleaseMask = 1 << 1;
	public static inline var ButtonPressMask = 1 << 2;
	public static inline var ButtonReleaseMask = 1 << 3;
	public static inline var PointerMotionMask = 1 << 6;
	public static inline var ExposureMask = 1 << 15;
	public static inline var StructureNotifyMask = 1 << 17;
	public static inline var PropertyChangeMask = 1 << 22;
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

@:hxmc.struct @:publicFields class XExposeEvent {
	var type:Int32;
	var serial:Int64;
	var send_event:Int32;
	var display:Ptr;
	var window:Int64;
	var x:Int32;
	var y:Int32;
	var width:Int32;
	var height:Int32;
	var count:Int32; // the Expose events that follow this one
}

// SelectionRequest: another client asks the owner for the selection
@:hxmc.struct @:publicFields class XSelectionRequestEvent {
	var type:Int32;
	var serial:Int64;
	var send_event:Int32;
	var display:Ptr;
	var owner:Int64;
	var requestor:Int64;
	var selection:Int64;
	var target:Int64;
	var property:Int64;
	var time:Int64;
}

// SelectionNotify: the selection converted (property 0: refused)
// PropertyNotify: a property of a window changed (state: NewValue) or was deleted
@:hxmc.struct @:publicFields class XPropertyEvent {
	var type:Int32;
	var serial:Int64;
	var send_event:Int32;
	var display:Ptr;
	var window:Int64;
	var atom:Int64;
	var time:Int64;
	var state:Int32;
}

@:hxmc.struct @:publicFields class XSelectionEvent {
	var type:Int32;
	var serial:Int64;
	var send_event:Int32;
	var display:Ptr;
	var requestor:Int64;
	var selection:Int64;
	var target:Int64;
	var property:Int64;
	var time:Int64;
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
