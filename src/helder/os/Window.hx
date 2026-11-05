package helder.os;

import helder.os.android.AndroidWindow;
import helder.os.cocoa.CocoaWindow;
import helder.os.uikit.UIKitWindow;
import helder.os.web.CanvasWindow;
import helder.os.win32.Win32Window;
import helder.os.x11.X11Window;
import helder.os.wayland.WaylandWindow;
import hxmc.unsafe.Mem;

// A top-level window, its size in points (pixels on X11). Its Surface
// carries the native handles for helder.gfx, its size in pixels. Cocoa on
// macOS (helder.os.cocoa.CocoaWindow), Win32 on Windows
// (helder.os.win32.Win32Window), a canvas in the browser (WebAssembly:
// helder.os.web.CanvasWindow, its size in CSS pixels), X11 elsewhere
// (helder.os.x11.X11Window); on Android the activity's window
// (helder.os.android.AndroidWindow: full screen, one per app, the size and
// title the system's), on iOS a UIWindow (helder.os.uikit.UIKitWindow: the
// same); on Linux with WAYLAND_DISPLAY set, Wayland's
// (helder.os.wayland.WaylandWindow; X11 where it cannot connect, or HELDER_X11=1).
class Window {
	public final surface:Surface;
	// its title bar's text (the browser: the page's title)
	public var title(default, set):String;
	public var closed(default, null) = false;

	// the native window, the target's (Mem.os() is known when compiling: the
	// other's code is never reached, as long as no field or method has its type)
	final native:Any;

	public function new(title:String, width:Int, height:Int) {
		this.title = title;
		native = Mem.platform() >= 1 ? new UIKitWindow(this, title, width, height) : Mem.os() == 1 ? new CocoaWindow(this, title, width, height) : Mem.os() == 2 ? new Win32Window(this, title, width,
			height) : Mem.os() == 3 ? new CanvasWindow(this, title, width, height) : Mem.target() >= 9 ? new AndroidWindow(this, title, width,
				height) : WaylandWindow.active() ? new WaylandWindow(this, title, width, height) : new X11Window(this, title, width, height);
		surface = Mem.platform() >= 1 ? (cast native : UIKitWindow).surface : Mem.os() == 1 ? (cast native : CocoaWindow).surface : Mem.os() == 2 ? (cast native : Win32Window).surface :
			Mem.os() == 3 ? (cast native : CanvasWindow).surface : Mem.target() >= 9 ? (cast native : AndroidWindow).surface : (Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).surface : (cast native : X11Window).surface);
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
	// the browser's devicePixelRatio; 1 on X11; iOS: the screen's native scale)
	public var scale(get, never):Float;

	function get_scale():Float
		return Mem.platform() >= 1 ? (cast native : UIKitWindow).scale : Mem.os() == 1 ? (cast native : CocoaWindow).scale : Mem.os() == 2 ? (cast native : Win32Window).scale : Mem.os() == 3 ? (cast native : CanvasWindow).scale : Mem.target() >= 9 ? (cast native : AndroidWindow).scale : Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).scale() : 1;

	// the safe area: the insets from each edge, in pixels, that the system's
	// bars, a notch, a display cutout or rounded corners leave clear, as
	// CSS's env(safe-area-inset-*) (iOS: the view's safeAreaInsets; Android:
	// the window's insets, its bars and cutout; 0 elsewhere); a Resize event
	// follows a change (a rotation, the bars hidden)
	public var safeTop(get, never):Int;
	public var safeLeft(get, never):Int;
	public var safeBottom(get, never):Int;
	public var safeRight(get, never):Int;

	function get_safeTop():Int
		return Mem.platform() >= 1 ? (cast native : UIKitWindow).safeTop : Mem.target() >= 9 ? (cast native : AndroidWindow).safeTop : 0;

	function get_safeLeft():Int
		return Mem.platform() >= 1 ? (cast native : UIKitWindow).safeLeft : Mem.target() >= 9 ? (cast native : AndroidWindow).safeLeft : 0;

	function get_safeBottom():Int
		return Mem.platform() >= 1 ? (cast native : UIKitWindow).safeBottom : Mem.target() >= 9 ? (cast native : AndroidWindow).safeBottom : 0;

	function get_safeRight():Int
		return Mem.platform() >= 1 ? (cast native : UIKitWindow).safeRight : Mem.target() >= 9 ? (cast native : AndroidWindow).safeRight : 0;

	// the system's bars hidden, the app on the whole screen (a game's): on
	// Android immersive (the status and navigation bars hidden, a swipe
	// shows them for a while; the window into a cutout's edges), on iOS the
	// status bar and the home indicator hidden (the indicator dims, a swipe
	// shows it); nothing elsewhere. The safe area follows (a Resize).
	// package.json's "helder": {"fullscreen": true} sets it from the start
	// (-D helder.fullscreen)
	public var immersive(get, set):Bool;

	function get_immersive():Bool
		return Mem.platform() >= 1 ? (cast native : UIKitWindow).immersive : Mem.target() >= 9 ? (cast native : AndroidWindow).immersive : false;

	function set_immersive(on:Bool):Bool {
		if (closed || on == immersive) return on;
		if (Mem.platform() >= 1) (cast native : UIKitWindow).setImmersive(on) else if (Mem.target() >= 9) AndroidWindow.setImmersive(cast native, on);
		return on;
	}

	// whether a Scroll at x, y (pixels) by dx, dy (as Scroll's deltas: a
	// drag's start and its direction) moves something of the program's:
	// asked once per touch drag, at its start, where the system would
	// otherwise take the drag. In the browser, a canvas whose touchAction
	// pans (the page scrolls along pan-y): true, the drag is the program's
	// (its Scrolls, the page held still); false, or null (not asked), the
	// page pans. Elsewhere every drag is the program's
	public var scrollsAt:Null<(x:Int, y:Int, dx:Float, dy:Float) -> Bool> = null;

	// the pointer's shape over the window (Auto: Default)
	public var cursor(default, set):Cursor = Default;

	function set_cursor(c:Cursor):Cursor {
		if (c == Auto) c = Default;
		if (c == cursor || closed) return c;
		cursor = c;
		if (Mem.platform() >= 1) {} else if (Mem.os() == 1) (cast native : CocoaWindow).setCursor(c) else if (Mem.os() == 2) (cast native : Win32Window).setCursor(c) else if (Mem.os() == 3)
			(cast native : CanvasWindow).setCursor(c) else if (Mem.target() >= 9) {} else (Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).setCursor(c) : (cast native : X11Window).setCursor(c));
		return c;
	}

	// whether text is typed into it now (startTextInput until stopTextInput:
	// a text field focused, ui's UiWindow), when Escape is the field's, not App.onBack's
	public var typing(default, null) = false;

	// where text is typed now (a text field's caret: x, y, width, height in
	// pixels from the top left), until stopTextInput: an input method shows
	// its composition and candidates there. In the browser keys then reach an
	// input element of the page, on macOS through a text view (NSTextInputClient)
	// at the caret: their compositions as TextEditing events; Windows places
	// the IME's windows (imm32); X11's input method keeps its own place;
	// Android shows the soft keyboard, its input method through a hidden
	// EditText (helder.os.android.TextInput, once enabled), compositions as
	// TextEditing
	public function startTextInput(x:Int, y:Int, width:Int, height:Int) {
		if (closed) return;
		typing = true;
		if (Mem.os() == 3) (cast native : CanvasWindow).textInput(true, x, y, width, height) else if (Mem.os() == 2)
			(cast native : Win32Window).textInputArea(x, y, width, height) else if (Mem.platform() >= 1) {} else if (Mem.os() == 1) (cast native : CocoaWindow).textInput(true, x, y,
				width, height) else if (Mem.target() >= 9) (cast native : AndroidWindow).textInput(true, x, y, width, height);
	}

	public function stopTextInput() {
		typing = false;
		if (closed) return;
		if (Mem.os() == 3) (cast native : CanvasWindow).textInput(false, 0, 0, 0, 0) else if (Mem.platform() >= 1) {} else if (Mem.os() == 1)
			(cast native : CocoaWindow).textInput(false, 0, 0, 0, 0) else if (Mem.target() >= 9) (cast native : AndroidWindow).textInput(false, 0, 0, 0, 0);
	}

	function set_title(v:String):String {
		if (v == title) return v;
		title = v;
		if (native == null || closed) return v;
		if (Mem.platform() >= 1) {} else if (Mem.os() == 1) (cast native : CocoaWindow).setTitle(v) else if (Mem.os() == 2) (cast native : Win32Window).setTitle(v) else if (Mem.os() == 3)
			(cast native : CanvasWindow).setTitle(v) else if (Mem.target() >= 9) {} else (Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).setTitle(v) : (cast native : X11Window).setTitle(v));
		return v;
	}

	// its content made width x height points (pixels on X11; the browser: the
	// canvas's CSS size); a Resize event follows
	public function resize(width:Int, height:Int) {
		if (closed) return;
		if (Mem.platform() >= 1) {} else if (Mem.os() == 1) (cast native : CocoaWindow).resize(width, height) else if (Mem.os() == 2) (cast native : Win32Window).resize(width,
			height) else if (Mem.os() == 3) (cast native : CanvasWindow).resize(width, height) else if (Mem.target() >= 9) {} else
			(Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).resize(width, height) : (cast native : X11Window).resize(width, height));
	}

	// the smallest content the user may resize it to, in points (the browser: the canvas's CSS minimum)
	public function setMinSize(width:Int, height:Int) {
		if (closed) return;
		if (Mem.platform() >= 1) {} else if (Mem.os() == 1) (cast native : CocoaWindow).setMinSize(width, height) else if (Mem.os() == 2) (cast native : Win32Window).setMinSize(width,
			height) else if (Mem.os() == 3) (cast native : CanvasWindow).setMinSize(width, height) else if (Mem.target() >= 9) {} else
			(Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).setMinSize(width, height) : (cast native : X11Window).setMinSize(width, height));
	}

	// the window on the whole screen, without its frame: X11's
	// _NET_WM_STATE_FULLSCREEN (asked of the window manager: a Resize when
	// it does), Windows' a borderless window over the monitor (its frame and
	// place given back after), macOS's full-screen space (toggleFullScreen:);
	// in the browser, on Android and iOS nothing (see immersive)
	public var fullscreen(get, set):Bool;

	function get_fullscreen():Bool
		return closed ? false : Mem.platform() >= 1 ? false : Mem.os() == 1 ? (cast native : CocoaWindow).isFullscreen() : Mem.os() == 2 ? (cast native : Win32Window).fullscreen : Mem.os() == 3 ? false : Mem.target() >= 9 ? false : (Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).fullscreen : (cast native : X11Window).fullscreen);

	function set_fullscreen(on:Bool):Bool {
		if (closed || on == fullscreen) return on;
		if (Mem.platform() >= 1) {} else if (Mem.os() == 1) (cast native : CocoaWindow).setFullscreen(on) else if (Mem.os() == 2) (cast native : Win32Window).setFullscreen(on) else if (Mem.os() == 3) {} else if (Mem.target() >= 9) {} else
			(Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).setFullscreen(on) : (cast native : X11Window).setFullscreen(on));
		return on;
	}

	// where its content's top left is on the screen, in points from the
	// screen's top left (pixels on X11; macOS: the main screen's); null where
	// a window has no place of its own (the browser, phones)
	public function position():Null<{x:Int, y:Int}>
		return closed ? null : Mem.platform() >= 1 ? null : Mem.os() == 1 ? (cast native : CocoaWindow).position() : Mem.os() == 2 ? (cast native : Win32Window).position() : Mem.os() == 3 ? null : Mem.target() >= 9 ? null : (Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).position() : (cast native : X11Window).position());

	// its content's top left moved to x, y (as position: a place it had, kept
	// across runs)
	public function moveTo(x:Int, y:Int) {
		if (closed) return;
		if (Mem.platform() >= 1) {} else if (Mem.os() == 1) (cast native : CocoaWindow).moveTo(x, y) else if (Mem.os() == 2) (cast native : Win32Window).moveTo(x, y) else if (Mem.os() == 3) {} else if (Mem.target() >= 9) {} else
			(Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).moveTo(x, y) : (cast native : X11Window).moveTo(x, y));
	}

	// brought to the front and given the focus (a second launch handing its
	// file to this one): X11's _NET_ACTIVE_WINDOW, Windows'
	// SetForegroundWindow, macOS's makeKeyAndOrderFront: and the app activated
	public function raise() {
		if (closed) return;
		if (Mem.platform() >= 1) {} else if (Mem.os() == 1) (cast native : CocoaWindow).raise() else if (Mem.os() == 2) (cast native : Win32Window).raise() else if (Mem.os() == 3) {} else if (Mem.target() >= 9) {} else
			(Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).raise() : (cast native : X11Window).raise());
	}

	public function close() {
		if (closed) return;
		closed = true;
		if (Mem.platform() >= 1) (cast native : UIKitWindow).destroy() else if (Mem.os() == 1) (cast native : CocoaWindow).destroy() else if (Mem.os() == 2) (cast native : Win32Window).destroy() else if (Mem.os() == 3)
			(cast native : CanvasWindow).destroy() else if (Mem.target() >= 9) (cast native : AndroidWindow).destroy() else (Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).destroy() : (cast native : X11Window).destroy());
		App.windows.remove(this);
	}
}
