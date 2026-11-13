package helder.os;

import helder.os.android.AndroidWindow;
import helder.os.cocoa.CocoaWindow;
import helder.os.uikit.UIKitWindow;
import helder.os.web.CanvasWindow;
import helder.os.win32.Win32Window;
import helder.os.x11.X11Window;
import helder.os.wayland.WaylandWindow;
import helder.os.TitleBar;
import hxmc.Platform;

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
	@:typescript public final surface:Surface;
	// its title bar's text (the browser: the page's title)
	@:typescript public var title(default, set):String;
	@:typescript public var closed(default, null) = false;

	// the native window, the target's (Platform.os() is known when compiling: the
	// other's code is never reached, as long as no field or method has its type)
	final native:Any;

	// (a build for a headless run, -D helder.headless: every window a
	// helder.os.headless.HeadlessWindow, the others' code not linked)
	static inline final HEADLESS = #if helder.headless true #else false #end;

	inline function headless():helder.os.headless.HeadlessWindow
		return cast native;

	// the system's title bar, or the content under it (TitleBar: "inset",
	// the window's buttons in the app's layout); given when it is made
	public final titlebar:TitleBar;

	@:typescript public function new(title:String, width:Int, height:Int, titlebar:TitleBar = Standard) {
		this.title = title;
		this.titlebar = titlebar;
		if (HEADLESS) {
			native = new helder.os.headless.HeadlessWindow(this, width, height);
			surface = headless().surface;
			App.windows.push(this);
			return;
		}
		native = Platform.apple() >= 1 ? new UIKitWindow(this, title, width, height) : Platform.os() == 1 ? new CocoaWindow(this, title, width, height) : Platform.os() == 2 ? new Win32Window(this, title, width,
			height) : Platform.os() == 3 ? new CanvasWindow(this, title, width, height) : Platform.target() >= 9 ? new AndroidWindow(this, title, width,
				height) : WaylandWindow.active() ? new WaylandWindow(this, title, width, height) : new X11Window(this, title, width, height);
		surface = Platform.apple() >= 1 ? (cast native : UIKitWindow).surface : Platform.os() == 1 ? (cast native : CocoaWindow).surface : Platform.os() == 2 ? (cast native : Win32Window).surface :
			Platform.os() == 3 ? (cast native : CanvasWindow).surface : Platform.target() >= 9 ? (cast native : AndroidWindow).surface : (Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).surface : (cast native : X11Window).surface);
		App.windows.push(this);
	}

	// the surface's size in pixels
	@:typescript public var width(get, never):Int;
	@:typescript public var height(get, never):Int;

	inline function get_width()
		return surface.width;

	inline function get_height()
		return surface.height;

	// pixels per point (2 on a Retina display, the monitor's DPI / 96 on Windows,
	// the browser's devicePixelRatio; 1 on X11; iOS: the screen's native scale)
	@:typescript public var scale(get, never):Float;

	function get_scale():Float
		return HEADLESS ? headless().scale : Platform.apple() >= 1 ? (cast native : UIKitWindow).scale : Platform.os() == 1 ? (cast native : CocoaWindow).scale : Platform.os() == 2 ? (cast native : Win32Window).scale : Platform.os() == 3 ? (cast native : CanvasWindow).scale : Platform.target() >= 9 ? (cast native : AndroidWindow).scale : Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).scale() : 1;

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
		return HEADLESS ? 0 : Platform.apple() >= 1 ? (cast native : UIKitWindow).safeTop : Platform.target() >= 9 ? (cast native : AndroidWindow).safeTop : 0;

	function get_safeLeft():Int
		return HEADLESS ? 0 : Platform.apple() >= 1 ? (cast native : UIKitWindow).safeLeft : Platform.target() >= 9 ? (cast native : AndroidWindow).safeLeft : 0;

	function get_safeBottom():Int
		return HEADLESS ? 0 : Platform.apple() >= 1 ? (cast native : UIKitWindow).safeBottom : Platform.target() >= 9 ? (cast native : AndroidWindow).safeBottom : 0;

	function get_safeRight():Int
		return HEADLESS ? 0 : Platform.apple() >= 1 ? (cast native : UIKitWindow).safeRight : Platform.target() >= 9 ? (cast native : AndroidWindow).safeRight : 0;

	// the system's bars hidden, the app on the whole screen (a game's): on
	// Android immersive (the status and navigation bars hidden, a swipe
	// shows them for a while; the window into a cutout's edges), on iOS the
	// status bar and the home indicator hidden (the indicator dims, a swipe
	// shows it); nothing elsewhere. The safe area follows (a Resize).
	// package.json's "helder": {"fullscreen": true} sets it from the start
	// (-D helder.fullscreen)
	public var immersive(get, set):Bool;

	function get_immersive():Bool
		return HEADLESS ? false : Platform.apple() >= 1 ? (cast native : UIKitWindow).immersive : Platform.target() >= 9 ? (cast native : AndroidWindow).immersive : false;

	function set_immersive(on:Bool):Bool {
		if (closed || on == immersive || HEADLESS) return on;
		if (Platform.apple() >= 1) (cast native : UIKitWindow).setImmersive(on) else if (Platform.target() >= 9) AndroidWindow.setImmersive(cast native, on);
		return on;
	}

	// whether a scroll at x, y (pixels) by dx, dy (as Scroll's deltas: a
	// drag's start and its direction, the content following the finger)
	// moves something of the program's: asked once per touch drag, at its
	// start, where the system would otherwise take the drag. In the
	// browser, a canvas whose touchAction pans (the page scrolls along
	// pan-y): true, the drag is the program's (its pointer's moves, the page
	// held still); false, or null (not asked), the page pans (the pointer
	// cancelled: PointerCancel). Elsewhere every drag is the program's
	public var scrollsAt:Null<(x:Int, y:Int, dx:Float, dy:Float) -> Bool> = null;

	// an inset title bar's answer for a press at x, y (pixels): a drag
	// region, one of the app's window buttons, or the content's (null: the
	// content's everywhere). Asked by the system's code at the press
	// (macOS: a drag then performWindowDragWithEvent:, a double click the
	// zoom; Wayland's and X11's moves), and on Windows for each
	// WM_NCHITTEST (HTCAPTION, HTMAXBUTTON for its snap layouts)
	public var titlebarAt:Null<(x:Int, y:Int) -> TitleHit> = null;

	// an inset title bar's area free of the window's buttons, in pixels (the
	// Window Controls Overlay's titlebar-area-*): macOS's right of its
	// buttons, elsewhere the top bar but the drawn buttons' width at the
	// right (TitleBars); null when not inset, or full screen
	public function titlebarArea():Null<{x:Int, y:Int, width:Int, height:Int}> {
		if (titlebar != Inset || closed || fullscreen) return null;
		var c = systemControls();
		if (c != null) {
			var h = Std.int(Math.max(c.y * 2 + c.height, Math.round(28 * scale)));
			return {x: c.x + c.width, y: 0, width: width - c.x - c.width, height: h};
		}
		if (Platform.apple() >= 1 || Platform.os() == 3 || Platform.target() >= 9) return null;
		var k = scale, linux = Platform.os() == 0;
		var b = Math.round(3 * TitleBars.button(linux) * k);
		return {x: 0, y: 0, width: width - b, height: Math.round(TitleBars.HEIGHT * k)};
	}

	// the system's own window buttons over an inset window's content, in
	// pixels (macOS's three, where they are now); null where the app draws
	// its own (TitleBars' sizes), or not inset. A headless run of a macOS
	// build has them where macOS puts them
	public function systemControls():Null<{x:Int, y:Int, width:Int, height:Int}> {
		if (titlebar != Inset || closed) return null;
		// (nested: only a constant condition drops the other targets' code)
		if (Platform.os() == 1) {
			if (Platform.apple() >= 1) return null;
			if (HEADLESS) {
				var k = headless().scale;
				return {x: Math.round(headless().controlsX * k), y: Math.round(headless().controlsY * k), width: Math.round(54 * k), height: Math.round(16 * k)};
			}
			return (cast native : CocoaWindow).controls();
		}
		return null;
	}

	// the system's buttons' top left moved to x, y (pixels: macOS's, again
	// after each resize; nothing elsewhere)
	public function placeControls(x:Int, y:Int) {
		if (titlebar != Inset || closed) return;
		if (Platform.os() == 1) {
			if (Platform.apple() >= 1) {} else if (HEADLESS) {
				headless().controlsX = x / headless().scale;
				headless().controlsY = y / headless().scale;
			} else (cast native : CocoaWindow).placeControls(x, y);
		}
	}

	// minimised to the Dock or the task bar (Wayland: asked of the compositor)
	public function minimize() {
		if (closed || HEADLESS) return;
		if (Platform.apple() >= 1) {} else if (Platform.os() == 1) (cast native : CocoaWindow).minimize() else if (Platform.os() == 2) (cast native : Win32Window).minimize() else if (Platform.os() == 3) {} else if (Platform.target() >= 9) {} else
			(Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).minimize() : (cast native : X11Window).minimize());
	}

	// maximised (macOS: zoomed), or back
	public var maximized(get, set):Bool;

	function get_maximized():Bool
		return closed || HEADLESS ? false : Platform.apple() >= 1 ? false : Platform.os() == 1 ? (cast native : CocoaWindow).zoomed() : Platform.os() == 2 ? (cast native : Win32Window).maximized() : Platform.os() == 3 ? false : Platform.target() >= 9 ? false : (Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).maximized : (cast native : X11Window).maximized);

	function set_maximized(on:Bool):Bool {
		if (closed || HEADLESS || on == maximized) return on;
		if (Platform.apple() >= 1) {} else if (Platform.os() == 1) (cast native : CocoaWindow).zoom() else if (Platform.os() == 2) (cast native : Win32Window).maximize(on) else if (Platform.os() == 3) {} else if (Platform.target() >= 9) {} else
			(Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).maximize(on) : (cast native : X11Window).maximize(on));
		return on;
	}

	// the pointer's shape over the window (Auto: Default)
	public var cursor(default, set):Cursor = Default;

	function set_cursor(c:Cursor):Cursor {
		if (c == Auto) c = Default;
		if (c == cursor || closed) return c;
		cursor = c;
		if (HEADLESS) {} else if (Platform.apple() >= 1) {} else if (Platform.os() == 1) (cast native : CocoaWindow).setCursor(c) else if (Platform.os() == 2) (cast native : Win32Window).setCursor(c) else if (Platform.os() == 3)
			(cast native : CanvasWindow).setCursor(c) else if (Platform.target() >= 9) {} else (Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).setCursor(c) : (cast native : X11Window).setCursor(c));
		return c;
	}

	// whether text is typed into it now (startTextInput until stopTextInput:
	// a text field focused, ui's UiWindow), when Escape is the field's, not App.onBack's
	public var typing(default, null) = false;

	// where text is typed now (a text field's caret: x, y, width, height in
	// pixels from the top left), until stopTextInput: an input method shows
	// its composition and candidates there. In the browser keys then reach an
	// input element of the page, on macOS through a text view (NSTextInputClient)
	// at the caret: their compositions as TextEditing events; on Windows
	// through TSF (helder.os.win32.Tsf: its document the field's,
	// textContext), the composition as TextEditing, the candidates below the
	// caret (where TSF is not there, the IME's own windows placed: imm32);
	// on Wayland through text-input-unstable-v3 (WaylandTextInput: the
	// caret's rectangle, the field's text, its compositions as TextEditing);
	// X11's input method keeps its own place;
	// Android shows the soft keyboard, its input method through a hidden
	// EditText (helder.os.android.TextInput, once enabled), compositions as
	// TextEditing
	public function startTextInput(x:Int, y:Int, width:Int, height:Int) {
		if (closed) return;
		typing = true;
		if (HEADLESS) helder.headless.Headless.run.textInputAt(x, y, width, height) else if (Platform.os() == 3) (cast native : CanvasWindow).textInput(true, x, y, width, height) else if (Platform.os() == 2)
			(cast native : Win32Window).textInputArea(x, y, width, height) else if (Platform.apple() >= 1) {} else if (Platform.os() == 1) (cast native : CocoaWindow).textInput(true, x, y,
				width, height) else if (Platform.target() >= 9) (cast native : AndroidWindow).textInput(true, x, y, width, height) else if (Std.isOfType(native, WaylandWindow))
			(cast native : WaylandWindow).textInputOn(x, y, width, height);
	}

	// the text around where text is typed (a text field's text and its
	// selection, UTF-16 indices), what an input method reads and edits:
	// Windows' TSF document, Wayland's surrounding text (text-input-v3);
	// multiline (a text area) and secret (a password: no text given, input
	// methods told) its kind. Given after startTextInput, again whenever it
	// changes; the input method's edits of it come as TextReplace (and
	// TextInput, TextEditing). Nothing elsewhere
	public function textContext(text:String, start:Int, end:Int, multiline = false, secret = false) {
		if (closed || !typing || HEADLESS) return;
		if (Platform.os() == 2) (cast native : Win32Window).textContext(secret ? "" : text, secret ? 0 : start, secret ? 0 : end) else if (Platform.os() == 0 && Platform.target() < 9 && Std.isOfType(native, WaylandWindow))
			(cast native : WaylandWindow).textContext(text, start, end, multiline, secret);
	}

	public function stopTextInput() {
		typing = false;
		if (closed || HEADLESS) return;
		if (Platform.os() == 3) (cast native : CanvasWindow).textInput(false, 0, 0, 0, 0) else if (Platform.os() == 2) (cast native : Win32Window).stopTextInput() else if (Platform.apple() >= 1) {} else if (Platform.os() == 1)
			(cast native : CocoaWindow).textInput(false, 0, 0, 0, 0) else if (Platform.target() >= 9) (cast native : AndroidWindow).textInput(false, 0, 0, 0, 0) else if (Std.isOfType(native, WaylandWindow))
			(cast native : WaylandWindow).textInputOff();
	}

	function set_title(v:String):String {
		if (v == title) return v;
		title = v;
		if (native == null || closed || HEADLESS) return v;
		if (Platform.apple() >= 1) {} else if (Platform.os() == 1) (cast native : CocoaWindow).setTitle(v) else if (Platform.os() == 2) (cast native : Win32Window).setTitle(v) else if (Platform.os() == 3)
			(cast native : CanvasWindow).setTitle(v) else if (Platform.target() >= 9) {} else (Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).setTitle(v) : (cast native : X11Window).setTitle(v));
		return v;
	}

	// its content made width x height points (pixels on X11; the browser: the
	// canvas's CSS size); a Resize event follows
	public function resize(width:Int, height:Int) {
		if (closed) return;
		if (HEADLESS) headless().resize(width, height) else if (Platform.apple() >= 1) {} else if (Platform.os() == 1) (cast native : CocoaWindow).resize(width, height) else if (Platform.os() == 2) (cast native : Win32Window).resize(width,
			height) else if (Platform.os() == 3) (cast native : CanvasWindow).resize(width, height) else if (Platform.target() >= 9) {} else
			(Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).resize(width, height) : (cast native : X11Window).resize(width, height));
	}

	// the smallest content the user may resize it to, in points (the browser: the canvas's CSS minimum)
	public function setMinSize(width:Int, height:Int) {
		if (closed || HEADLESS) return;
		if (Platform.apple() >= 1) {} else if (Platform.os() == 1) (cast native : CocoaWindow).setMinSize(width, height) else if (Platform.os() == 2) (cast native : Win32Window).setMinSize(width,
			height) else if (Platform.os() == 3) (cast native : CanvasWindow).setMinSize(width, height) else if (Platform.target() >= 9) {} else
			(Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).setMinSize(width, height) : (cast native : X11Window).setMinSize(width, height));
	}

	// the window on the whole screen, without its frame: X11's
	// _NET_WM_STATE_FULLSCREEN (asked of the window manager: a Resize when
	// it does), Windows' a borderless window over the monitor (its frame and
	// place given back after), macOS's full-screen space (toggleFullScreen:);
	// in the browser, on Android and iOS nothing (see immersive)
	public var fullscreen(get, set):Bool;

	function get_fullscreen():Bool
		return closed ? false : HEADLESS ? headless().fullscreen : Platform.apple() >= 1 ? false : Platform.os() == 1 ? (cast native : CocoaWindow).isFullscreen() : Platform.os() == 2 ? (cast native : Win32Window).fullscreen : Platform.os() == 3 ? false : Platform.target() >= 9 ? false : (Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).fullscreen : (cast native : X11Window).fullscreen);

	function set_fullscreen(on:Bool):Bool {
		if (closed || on == fullscreen) return on;
		if (HEADLESS) headless().fullscreen = on else if (Platform.apple() >= 1) {} else if (Platform.os() == 1) (cast native : CocoaWindow).setFullscreen(on) else if (Platform.os() == 2) (cast native : Win32Window).setFullscreen(on) else if (Platform.os() == 3) {} else if (Platform.target() >= 9) {} else
			(Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).setFullscreen(on) : (cast native : X11Window).setFullscreen(on));
		return on;
	}

	// where its content's top left is on the screen, in points from the
	// screen's top left (pixels on X11; macOS: the main screen's); null where
	// a window has no place of its own (the browser, phones)
	public function position():Null<{x:Int, y:Int}>
		return closed ? null : HEADLESS ? {x: headless().x, y: headless().y} : Platform.apple() >= 1 ? null : Platform.os() == 1 ? (cast native : CocoaWindow).position() : Platform.os() == 2 ? (cast native : Win32Window).position() : Platform.os() == 3 ? null : Platform.target() >= 9 ? null : (Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).position() : (cast native : X11Window).position());

	// its content's top left moved to x, y (as position: a place it had, kept
	// across runs)
	public function moveTo(x:Int, y:Int) {
		if (closed) return;
		if (HEADLESS) {
			headless().x = x;
			headless().y = y;
		} else if (Platform.apple() >= 1) {} else if (Platform.os() == 1) (cast native : CocoaWindow).moveTo(x, y) else if (Platform.os() == 2) (cast native : Win32Window).moveTo(x, y) else if (Platform.os() == 3) {} else if (Platform.target() >= 9) {} else
			(Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).moveTo(x, y) : (cast native : X11Window).moveTo(x, y));
	}

	// brought to the front and given the focus (a second launch handing its
	// file to this one): X11's _NET_ACTIVE_WINDOW, Windows'
	// SetForegroundWindow, macOS's makeKeyAndOrderFront: and the app activated
	public function raise() {
		if (closed || HEADLESS) return;
		if (Platform.apple() >= 1) {} else if (Platform.os() == 1) (cast native : CocoaWindow).raise() else if (Platform.os() == 2) (cast native : Win32Window).raise() else if (Platform.os() == 3) {} else if (Platform.target() >= 9) {} else
			(Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).raise() : (cast native : X11Window).raise());
	}

	@:typescript public function close() {
		if (closed) return;
		closed = true;
		if (HEADLESS) {} else if (Platform.apple() >= 1) (cast native : UIKitWindow).destroy() else if (Platform.os() == 1) (cast native : CocoaWindow).destroy() else if (Platform.os() == 2) (cast native : Win32Window).destroy() else if (Platform.os() == 3)
			(cast native : CanvasWindow).destroy() else if (Platform.target() >= 9) (cast native : AndroidWindow).destroy() else (Std.isOfType(native, WaylandWindow) ? (cast native : WaylandWindow).destroy() : (cast native : X11Window).destroy());
		App.windows.remove(this);
	}
}
