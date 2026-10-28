package helder.os.android;

import helder.os.Event;
import helder.os.android.Native;
import hxmc.unsafe.*;

// helder.os.Window on Android: the activity's one window (NativeActivity's
// ANativeWindow), full screen; its title and size are the system's. The
// program's thread (Activity: hxmc's runtime runs there) waits for the
// native window when the Window is made (one with a size), then App.run
// polls the looper: the commands of the activity's callbacks (Activity)
// and the input queue.
// Every finger and pen is a pointer (Pointers: Pointer* events, their
// history as samples, a cancel when the system takes them); the first
// finger's compatibility gesture (Pointers.emulate) is as in the browser
// (TouchDrag): a tap clicks (the left button where it came down, once it
// lifts), a drag scrolls what is under where it started (Scrolls with
// Mods.TOUCH, ending with one of nothing without it, then a glide's when
// let go moving); keys come as X11 KeySyms like the
// other systems' (Back is Escape: the system still finishes the activity), with
// TextInput for the printable ones; with text input on and enabled
// (TextInput.enable: helder.ui's UiWindow does), the soft keyboard and the
// input method's commits and compositions. When the system takes the window (the
// app goes to the background) the Surface is lost (Surface.lost: the GPU
// back end lets go of it before the callback returns) and a Suspend event
// comes; with a new window, once it has a size, Resume at that size. (At
// a launch a window can come without a size yet, or be replaced as soon
// as it came: nothing is made on one until it has a size. The activity
// itself can be destroyed and made again then (a relaunch: Activity), its
// window with it: only a finishing activity ends the wait.)
// While paused or without a window App.run sleeps in the looper.
// (hxmc dev's host: the window, the input queue and the pause are the
// host's, kept for the next build: helder.dev.HostedMacro)
#if hxmc.dev_host
@:build(helder.dev.HostedMacro.shared(40, 8))
#end
@:hxmc.android @:allow(helder.os)
class AndroidWindow {
	static var current:Null<AndroidWindow> = null;
	static var queue:Ptr = Ptr.nil();
	static var window:Ptr = Ptr.nil();
	static var paused:Bool = false;
	static final event = new Event();
	// the first finger's gesture (TouchDrag), its events' times from this one's (ns)
	static final drag = new TouchDrag();
	static var since:Int64 = 0;
	static var timed:Bool = false;
	// text input (TextInput, in the programs that enable it): on or off, its
	// events waiting for this thread
	@:allow(helder.os.android) static var textInputHook:Null<(on:Bool, x:Int, y:Int, width:Int, height:Int) -> Void> = null;
	@:allow(helder.os.android) static var textEvents:Null<((kind:EventKind, text:String, caret:Int) -> Void)->Void> = null;
	// a new activity in the running process (Glue: the content moves to it)
	@:allow(helder.os.android) static var recreated:Null<Void->Void> = null;

	final owner:Window;
	final surface:Surface;
	var suspended = false;

	function new(owner:Window, title:String, width:Int, height:Int) {
		if (current != null) throw "helder.os: Android has one window, the activity's";
		this.owner = owner;
		// (the activity's window: the program waits for it, through the
		// activity's commands, until it has a size; current once there is a surface)
		log("Window: waiting for the activity's window", window);
		while (!ready() && Activity.destroyed == 0)
			pump(-1, null);
		if (!ready()) throw "helder.os: the activity finished before its window came";
		var w = Android.ANativeWindow_getWidth(window), h = Android.ANativeWindow_getHeight(window);
		log("Window: the activity's window, ready", window);
		surface = new Surface(Android, Ptr.nil(), window, w, h);
		current = this;
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
		#if hxmc.dev_host
		// (handing over to the next build: the activity goes on)
		if (helder.dev.Hosted.handingOver) return;
		#end
		if (Activity.destroyed == 0 && !Activity.activity.isNull()) Android.ANativeActivity_finish(Activity.activity);
	}

	// the native window is there and has a size (the system's resize
	// callback comes when a 0x0 one gets one)
	static function ready():Bool
		return !window.isNull() && Android.ANativeWindow_getWidth(window) > 0 && Android.ANativeWindow_getHeight(window) > 0;

	// whether a frame can be drawn now
	static function drawable():Bool
		return current != null && !current.suspended && !window.isNull() && !paused;

	// the pending commands and input, without waiting
	static function poll(onEvent:Event->Void)
		pump(0, onEvent);

	// waits until the looper has something, at most seconds (< 0: no limit;
	// a frame while a drag glides)
	static function wait(seconds:Float) {
		seconds = drag.wait(seconds);
		Looper.ALooper_pollOnce(seconds < 0 ? -1 : Std.int(seconds * 1000), Ptr.nil(), Ptr.nil(), Ptr.nil());
	}

	// handles what the looper has: once it waited timeout ms (-1: until
	// something comes), then whatever else is ready (a window's destroy
	// right after its create among it)
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
		}
		if (textEvents != null) textEvents((kind, text, caret) -> dispatch(onEvent, kind, caret, 0, text));
		// (a drag let go moving: its glide's scroll since the last)
		if (drag.gliding && onEvent != null && current != null && drag.glide(haxe.Timer.stamp() * 1000)) {
			drag.scroll(event, 0);
			event.window = current.owner;
			onEvent(event);
		}
		// (a new window with a size: Resume; a size the system changed: Resize)
		var w = current;
		if (w == null || !ready()) return;
		var nw = Android.ANativeWindow_getWidth(window), nh = Android.ANativeWindow_getHeight(window);
		if (w.suspended) {
			w.suspended = false;
			log("Window: Resume", window);
			w.surface.reattach(window, nw, nh);
			dispatch(onEvent, Resume, nw, nh);
		} else if (nw != w.surface.width || nh != w.surface.height) {
			log("Window: Resize", window);
			w.surface.resized(nw, nh);
			dispatch(onEvent, Resize, nw, nh);
		}
	}

	static function dispatch(onEvent:Null<Event->Void>, kind:EventKind, x = 0, y = 0, text = "") {
		if (onEvent == null || current == null) return;
		var e = event;
		e.kind = kind;
		e.window = current.owner;
		e.x = x;
		e.y = y;
		e.button = 0;
		e.mods = 0;
		e.text = text;
		onEvent(e);
	}

	// Window.startTextInput, stopTextInput: the keyboard and the input method
	// (TextInput, once enabled: otherwise only the input queue's keys)
	function textInput(on:Bool, x:Int, y:Int, width:Int, height:Int)
		if (textInputHook != null) textInputHook(on, x, y, width, height);

	// one command of the activity's callbacks (Activity), acknowledged once
	// its state is taken
	static function command(cmd:Int, onEvent:Null<Event->Void>) {
		var w = current;
		switch cmd {
			case Activity.WINDOW_CREATED:
				// (used once it has a size: pump)
				window = Activity.take(true);
				log("window created", window);
				Activity.acknowledge();
			case Activity.WINDOW_DESTROYED:
				// (the GPU lets go of the window before the callback returns;
				// the Surface keeps no handle to it)
				log("window destroyed", window);
				var suspend = w != null && !w.suspended;
				drag.stop();
				// (the window's pointers let go: their cancels)
				if (w != null) Pointers.cancelAll(w.owner, event, onEvent);
				if (suspend) {
					w.suspended = true;
					var lost = w.surface.lost;
					if (lost != null) lost();
					w.surface.reattach(Ptr.nil(), w.surface.width, w.surface.height);
				}
				window = Ptr.nil();
				Activity.acknowledge();
				if (suspend) dispatch(onEvent, Suspend);
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
				log("command: pause", window);
				paused = true;
				Activity.acknowledge();
			case Activity.RESUME:
				log("command: resume", window);
				paused = false;
				Activity.acknowledge();
			case Activity.GONE:
				// (its window and input queue went before: commands of their own)
				log("command: activity gone, not finishing", window);
				Activity.acknowledge();
			case Activity.CREATED:
				log("command: a new activity", window);
				Activity.acknowledge();
				if (recreated != null) recreated();
			case Activity.DESTROY:
				log("command: destroy (finishing)", window);
				Activity.acknowledge();
				// (the window's close: the program decides, App ends without windows)
				dispatch(onEvent, Close);
				if (w != null) {
					w.owner.close();
					App.quit();
				}
			case Activity.REDRAW | Activity.CONTENT_RECT | Activity.CONFIG | Activity.RESIZED:
				if (cmd == Activity.RESIZED) log("command: window resized", window);
				Activity.acknowledge();
				dispatch(onEvent, Redraw);
			case _:
				Activity.acknowledge();
		}
	}

	// the window's lifecycle in logcat (debug level, tag helder.os: not the program's output)
	static function log(what:String, w:Ptr)
		Arena.scoped(a -> Log.__android_log_write(3, Mem.cstr("helder.os"),
			a.cstring(w.isNull() ? what : what + " " + Android.ANativeWindow_getWidth(w) + "x" + Android.ANativeWindow_getHeight(w))));

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

	// a MotionEvent: every pointer in it (Pointers: their slots, their
	// events; the history's samples), then the first finger's
	// compatibility gesture (TouchDrag, while Pointers.emulate)
	static function motion(ev:Ptr, onEvent:Null<Event->Void>):Int {
		var raw = Android.AMotionEvent_getAction(ev);
		var action = raw & 0xff, index:Int64 = (raw >> 8) & 0xff;
		var time = ms(Android.AMotionEvent_getEventTime(ev));
		var w = current, e = event;
		if (w == null) return 1;
		var count = Android.AMotionEvent_getPointerCount(ev);
		switch action {
			case 0 | 5: // AMOTION_EVENT_ACTION_DOWN, _POINTER_DOWN: the pointer at index
				var p = Pointers.press(w.owner, Android.AMotionEvent_getPointerId(ev, index), tool(ev, index), Android.AMotionEvent_getX(ev, index),
					Android.AMotionEvent_getY(ev, index), pressure(ev, index), time);
				if (p != null) send(onEvent, PointerDown, p, 1);
			case 2: // AMOTION_EVENT_ACTION_MOVE: every pointer, its history first
				var history = Android.AMotionEvent_getHistorySize(ev);
				var i:Int64 = 0;
				while (i < count) {
					var p = Pointers.find(Android.AMotionEvent_getPointerId(ev, i), tool(ev, i));
					if (p != null) {
						var x:Float = Android.AMotionEvent_getX(ev, i), y:Float = Android.AMotionEvent_getY(ev, i);
						if (x != p.x || y != p.y) {
							var h:Int64 = 0;
							while (h < history) {
								@:privateAccess p.sample(Android.AMotionEvent_getHistoricalX(ev, i, h), Android.AMotionEvent_getHistoricalY(ev, i, h),
									ms(Android.AMotionEvent_getHistoricalEventTime(ev, h)));
								h++;
							}
							@:privateAccess p.moveTo(x, y, pressure(ev, i), time);
							send(onEvent, PointerMove, p, 0);
						}
					}
					i++;
				}
			case 1 | 6: // AMOTION_EVENT_ACTION_UP, _POINTER_UP (FLAG_CANCELED: a palm, API 33)
				var p = Pointers.find(Android.AMotionEvent_getPointerId(ev, index), tool(ev, index));
				if (p != null) {
					var cancelled = Android.AMotionEvent_getFlags(ev) & 0x20 != 0;
					@:privateAccess p.moveTo(Android.AMotionEvent_getX(ev, index), Android.AMotionEvent_getY(ev, index), p.pressure, time);
					Pointers.lift(p, cancelled, time);
					send(onEvent, cancelled ? PointerCancel : PointerUp, p, cancelled ? 0 : 1);
				}
			case 3: // AMOTION_EVENT_ACTION_CANCEL: every one
				Pointers.cancelAll(w.owner, e, onEvent);
			case _:
		}
		if (Pointers.emulate) emulated(action, index, ev, time, onEvent);
		return 1;
	}

	// (the first finger's tap a click, its drag Scrolls: TouchDrag)
	static function emulated(action:Int, index:Int64, ev:Ptr, time:Float, onEvent:Null<Event->Void>) {
		var w = current, e = event;
		var x:Float = Android.AMotionEvent_getX(ev, 0), y:Float = Android.AMotionEvent_getY(ev, 0);
		switch action {
			case 0: // AMOTION_EVENT_ACTION_DOWN
				drag.press(x, y, time, w.scale);
			case 2: // AMOTION_EVENT_ACTION_MOVE
				if (drag.move(x, y, time) && onEvent != null) {
					drag.scroll(e, Mods.TOUCH);
					e.window = w.owner;
					onEvent(e);
				}
			case 1 | 3: // AMOTION_EVENT_ACTION_UP, _CANCEL
				var end = drag.lift(time, action == 3);
				if (onEvent == null) return;
				e.window = w.owner;
				if (end == TouchDrag.END) {
					drag.scroll(e, 0);
					onEvent(e);
				} else if (end == TouchDrag.TAP) {
					drag.click(e, MouseMove);
					onEvent(e);
					drag.click(e, MouseDown);
					onEvent(e);
					drag.click(e, MouseUp);
					onEvent(e);
				}
			case _:
		}
	}

	// a pointer's event (Pointers)
	static function send(onEvent:Null<Event->Void>, kind:EventKind, p:Pointer, button:Int) {
		if (onEvent == null) return;
		Pointers.fill(event, kind, p, button);
		onEvent(event);
	}

	// AMOTION_EVENT_TOOL_TYPE_STYLUS, _ERASER: a pen; _MOUSE the mouse; else a finger
	static function tool(ev:Ptr, i:Int64):PointerType
		return switch Android.AMotionEvent_getToolType(ev, i) {
			case 2 | 4: Pen;
			case 3: Mouse;
			case _: Touch;
		}

	// (a finger's force, 0 to 1: the screen's estimate where it has none)
	static inline function pressure(ev:Ptr, i:Int64):Float
		return Math.min(1, Android.AMotionEvent_getPressure(ev, i));

	// an event's time in ms since the first one's (the drag's speed, even when a frame read several)
	static function ms(ns:Int64):Float {
		if (!timed) {
			since = ns;
			timed = true;
		}
		var d = ns - since;
		return ((d >> 20).toInt() * 1048576.0 + (d & 0xFFFFF).toInt()) / 1e6;
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
