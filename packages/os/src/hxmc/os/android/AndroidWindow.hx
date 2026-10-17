package hxmc.os.android;

import hxmc.os.Event;
import hxmc.os.android.Native;
import hxmc.unsafe.*;

// hxmc.os.Window on Android: the activity's one window (NativeActivity's
// ANativeWindow), full screen; its title and size are the system's. The
// program's thread (Activity: hxmc's runtime runs there) waits for the
// native window when the Window is made, then App.run polls the looper:
// the commands of the activity's callbacks (Activity) and the input queue.
// A touch is the left button (MouseDown, MouseMove, MouseUp at the
// finger), and its drag scrolls too (Scroll by the finger's motion, as a
// touch screen scrolls); keys come as X11 KeySyms like the other systems'
// (Back is Escape: the system still finishes the activity), with
// TextInput for the printable ones. When the system takes the window (the
// app goes to the background) the Surface is lost (Surface.lost: the GPU
// back end lets go of it before the callback returns) and a Suspend event
// comes; with a new window, Resume (and Resize when its size changed).
// While paused or without a window App.run sleeps in the looper.
@:hxmc.android @:allow(hxmc.os)
class AndroidWindow {
	static var current:Null<AndroidWindow> = null;
	static var queue = Ptr.nil();
	static var window = Ptr.nil();
	static var paused = false;
	static final event = new Event();
	// the finger's last position (a drag's Scroll), -1: none down
	static var lastX = -1.0;
	static var lastY = -1.0;

	final owner:Window;
	final surface:Surface;
	var suspended = false;

	function new(owner:Window, title:String, width:Int, height:Int) {
		if (current != null) throw "hxmc.os: Android has one window, the activity's";
		this.owner = owner;
		current = this;
		// (the activity's window: the program waits for it)
		while (window.isNull() && Activity.destroyed == 0)
			pump(-1, null);
		surface = new Surface(Android, Ptr.nil(), window, window.isNull() ? 0 : Android.ANativeWindow_getWidth(window),
			window.isNull() ? 0 : Android.ANativeWindow_getHeight(window));
	}

	// pixels per point: the screen's density over 160 dpi (the system's dp)
	var scale(get, never):Float;

	function get_scale():Float {
		var a = Activity.activity;
		if (a.isNull()) return 1;
		var c = Android.AConfiguration_new();
		Android.AConfiguration_fromAssetManager(c, Mem.getPtr(a, 64)); // ANativeActivity.assetManager
		var d = Android.AConfiguration_getDensity(c);
		Android.AConfiguration_delete(c);
		return d <= 0 || d == 0xffff ? 1 : d / 160;
	}

	// the system's night mode (Configuration.uiMode's night bits: 2 yes)
	static function night():Bool {
		var a = Activity.activity;
		if (a.isNull()) return false;
		var c = Android.AConfiguration_new();
		Android.AConfiguration_fromAssetManager(c, Mem.getPtr(a, 64));
		var n = Android.AConfiguration_getUiModeNight(c);
		Android.AConfiguration_delete(c);
		return n == 2;
	}

	function destroy() {
		current = null;
		if (Activity.destroyed == 0) Android.ANativeActivity_finish(Activity.activity);
	}

	// whether a frame can be drawn now
	static function drawable():Bool
		return current != null && !current.suspended && !window.isNull() && !paused;

	// the pending commands and input, without waiting
	static function poll(onEvent:Event->Void)
		pump(0, onEvent);

	// waits until the looper has something, at most seconds (< 0: no limit)
	static function wait(seconds:Float)
		Looper.ALooper_pollOnce(seconds < 0 ? -1 : Std.int(seconds * 1000), Ptr.nil(), Ptr.nil(), Ptr.nil());

	// handles what the looper has: once it waited timeout ms (-1: until
	// something comes), then whatever else is ready
	static function pump(timeout:Int, onEvent:Null<Event->Void>) {
		var t = timeout;
		while (true) {
			var id = Looper.ALooper_pollOnce(t, Ptr.nil(), Ptr.nil(), Ptr.nil());
			t = 0;
			if (id == Activity.LOOPER_COMMANDS) {
				var cmd = Activity.next();
				if (cmd >= 0) command(cmd, onEvent);
			} else if (id == Activity.LOOPER_INPUT) input(onEvent);
			else if (id < 0 && id != -1) break; // (ALOOPER_POLL_TIMEOUT, _ERROR; -1: woken)
			if (timeout < 0 && (!window.isNull() || Activity.destroyed != 0)) break;
		}
		// (a size the system changed)
		var w = current;
		if (w != null && !w.suspended && !window.isNull()) {
			var nw = Android.ANativeWindow_getWidth(window), nh = Android.ANativeWindow_getHeight(window);
			if (nw > 0 && nh > 0 && (nw != w.surface.width || nh != w.surface.height)) {
				w.surface.resized(nw, nh);
				dispatch(onEvent, Resize, nw, nh);
			}
		}
	}

	static function dispatch(onEvent:Null<Event->Void>, kind:EventKind, x = 0, y = 0) {
		if (onEvent == null || current == null) return;
		var e = event;
		e.kind = kind;
		e.window = current.owner;
		e.x = x;
		e.y = y;
		e.button = 0;
		e.mods = 0;
		e.text = "";
		onEvent(e);
	}

	// one command of the activity's callbacks (Activity), acknowledged once
	// its state is taken
	static function command(cmd:Int, onEvent:Null<Event->Void>) {
		var w = current;
		switch cmd {
			case Activity.WINDOW_CREATED:
				window = Activity.take(true);
				var resumed = w != null && w.suspended;
				if (resumed) {
					w.suspended = false;
					w.surface.reattach(window, Android.ANativeWindow_getWidth(window), Android.ANativeWindow_getHeight(window));
				}
				Activity.acknowledge();
				if (resumed) dispatch(onEvent, Resume, w.surface.width, w.surface.height);
			case Activity.WINDOW_DESTROYED:
				// (the GPU lets go of the window before the callback returns)
				if (w != null && !w.suspended) {
					w.suspended = true;
					var lost = w.surface.lost;
					if (lost != null) lost();
				}
				window = Ptr.nil();
				Activity.acknowledge();
				dispatch(onEvent, Suspend);
			case Activity.INPUT_CREATED:
				if (!queue.isNull()) Android.AInputQueue_detachLooper(queue);
				queue = Activity.take(false);
				Android.AInputQueue_attachLooper(queue, Activity.looper, Activity.LOOPER_INPUT, Ptr.nil(), Ptr.nil());
				Activity.acknowledge();
			case Activity.INPUT_DESTROYED:
				if (!queue.isNull()) Android.AInputQueue_detachLooper(queue);
				queue = Ptr.nil();
				Activity.acknowledge();
			case Activity.PAUSE:
				paused = true;
				Activity.acknowledge();
			case Activity.RESUME:
				paused = false;
				Activity.acknowledge();
			case Activity.DESTROY:
				Activity.acknowledge();
				// (the window's close: the program decides, App ends without windows)
				dispatch(onEvent, Close);
				if (w != null) {
					w.owner.close();
					App.quit();
				}
			case Activity.REDRAW | Activity.CONTENT_RECT | Activity.CONFIG | Activity.RESIZED:
				Activity.acknowledge();
				dispatch(onEvent, Redraw);
			case _:
				Activity.acknowledge();
		}
	}

	// the input queue's events
	static function input(onEvent:Null<Event->Void>) {
		if (queue.isNull()) return;
		var out = Mem.stack(8);
		while (Android.AInputQueue_getEvent(queue, out) >= 0) {
			var ev = Mem.getPtr(out, 0);
			if (Android.AInputQueue_preDispatchEvent(queue, ev) != 0) continue;
			var handled = 0;
			switch Android.AInputEvent_getType(ev) {
				case 2: handled = motion(ev, onEvent); // AINPUT_EVENT_TYPE_MOTION
				case 1: handled = key(ev, onEvent); // AINPUT_EVENT_TYPE_KEY
				case _:
			}
			Android.AInputQueue_finishEvent(queue, ev, handled);
		}
	}

	static function motion(ev:Ptr, onEvent:Null<Event->Void>):Int {
		var action = Android.AMotionEvent_getAction(ev) & 0xff;
		var x:Float = Android.AMotionEvent_getX(ev, 0), y:Float = Android.AMotionEvent_getY(ev, 0);
		var e = event;
		function send(kind:EventKind, button:Int) {
			if (onEvent == null || current == null) return;
			e.kind = kind;
			e.window = current.owner;
			e.x = Std.int(x);
			e.y = Std.int(y);
			e.button = button;
			e.mods = 0;
			e.text = "";
			onEvent(e);
		}
		switch action {
			case 0: // AMOTION_EVENT_ACTION_DOWN
				lastX = x;
				lastY = y;
				send(MouseMove, 0);
				send(MouseDown, 1);
			case 2: // AMOTION_EVENT_ACTION_MOVE
				send(MouseMove, 0);
				if (lastX >= 0 && onEvent != null && current != null) {
					e.kind = Scroll;
					e.deltaX = lastX - x;
					e.deltaY = lastY - y;
					onEvent(e);
				}
				lastX = x;
				lastY = y;
			case 1 | 3: // AMOTION_EVENT_ACTION_UP, _CANCEL
				lastX = lastY = -1;
				send(MouseUp, 1);
			case _:
		}
		return 1;
	}

	static function key(ev:Ptr, onEvent:Null<Event->Void>):Int {
		var down = Android.AKeyEvent_getAction(ev) == 0; // AKEY_EVENT_ACTION_DOWN (1: up, 2: multiple)
		var code = Android.AKeyEvent_getKeyCode(ev);
		var meta = Android.AKeyEvent_getMetaState(ev);
		var sym = keySym(code);
		if (sym == 0 || onEvent == null || current == null) return 0;
		var e = event;
		e.kind = down ? KeyDown : KeyUp;
		e.window = current.owner;
		e.key = sym;
		e.mods = ((meta & 0x1) != 0 ? Mods.SHIFT : 0) | ((meta & 0x1000) != 0 ? Mods.CONTROL : 0) | ((meta & 0x2) != 0 ? Mods.ALT : 0)
			| ((meta & 0x10000) != 0 ? Mods.META : 0);
		e.text = "";
		onEvent(e);
		if (down && sym < 0x100 && e.mods & (Mods.CONTROL | Mods.ALT | Mods.META) == 0) {
			var c = (e.mods & Mods.SHIFT) != 0 && sym >= "a".code && sym <= "z".code ? sym - 32 : sym;
			e.kind = TextInput;
			e.text = String.fromCharCode(c);
			onEvent(e);
		}
		// (Back: also the system's, which finishes the activity)
		return code == 4 ? 0 : 1;
	}

	// an Android key code as the X11 KeySym the other systems report (0: none)
	static function keySym(code:Int):Int {
		if (code >= 29 && code <= 54) return "a".code + code - 29; // AKEYCODE_A..Z
		if (code >= 7 && code <= 16) return "0".code + code - 7; // AKEYCODE_0..9
		return switch code {
			case 4 | 111: 0xFF1B; // BACK, ESCAPE
			case 66 | 160: 0xFF0D; // ENTER, NUMPAD_ENTER
			case 67: 0xFF08; // DEL (backspace)
			case 112: 0xFFFF; // FORWARD_DEL
			case 61: 0xFF09; // TAB
			case 62: " ".code;
			case 21: 0xFF51; // DPAD_LEFT
			case 19: 0xFF52; // DPAD_UP
			case 22: 0xFF53; // DPAD_RIGHT
			case 20: 0xFF54; // DPAD_DOWN
			case 122: 0xFF50; // MOVE_HOME
			case 123: 0xFF57; // MOVE_END
			case 92: 0xFF55; // PAGE_UP
			case 93: 0xFF56; // PAGE_DOWN
			case 55: ",".code;
			case 56: ".".code;
			case 69: "-".code;
			case 70: "=".code;
			case 71: "[".code;
			case 72: "]".code;
			case 73: "\\".code;
			case 74: ";".code;
			case 75: "'".code;
			case 76: "/".code;
			case 68: "`".code;
			case 59: 0xFFE1; // SHIFT_LEFT
			case 60: 0xFFE2;
			case 113: 0xFFE3; // CTRL_LEFT
			case 114: 0xFFE4;
			case 57: 0xFFE9; // ALT_LEFT
			case 58: 0xFFEA;
			case _: 0;
		}
	}
}
