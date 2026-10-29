package helder.os;

import helder.async.Driven;
import helder.os.android.AndroidWindow;
import helder.os.cocoa.CocoaWindow;
import helder.os.objc.Runtime;
import helder.os.uikit.UIKitWindow;
import helder.os.web.CanvasWindow;
import helder.os.win32.Win32Window;
import helder.os.x11.X11Window;
import hxmc.unsafe.*;

// The app loop, callback driven (Cocoa, GTK and the browser own their
// loops): run calls onEvent for each pending event, then onFrame, until
// quit() or the last window closes. The loop is hxmc's own, polling the
// system's events without waiting (CocoaWindow on macOS, Win32Window on
// Windows, X11Window elsewhere); a frame's pace comes from the GPU's
// present (vsync), its time (App.frame) when it began. In the browser
// (WebAssembly) run returns at once, and main after it: each turn of the
// loop is then a frame of
// requestAnimationFrame (CanvasWindow). A frame with nothing to draw calls
// wait, so that an idle app sleeps until the system has an event for it.
// On Android the loop runs on the program's own thread (helder.os.android:
// NativeActivity's callbacks reach it through the thread's looper), and a
// frame is drawn only while the activity has its window and is not paused
// (otherwise the loop sleeps in the looper). On iOS the program runs inside
// UIKit's loop (helder.os.uikit.UIKitApp): each turn runs the main run loop
// without waiting, and draws only while the app is active (not in the
// background, nor inactive: otherwise it sleeps in the run loop). On both
// the frames are the display's: a turn that may draw asks for the next
// vsync (Android's Choreographer, helder.os.android.Vsync; iOS's
// CADisplayLink) and sleeps until it comes (or an event does), then the
// next turn draws the frame, App.frame its vsync's time. A frame that
// waits (App.wait: nothing to draw) asks for none until it has slept, so
// an idle app sleeps as elsewhere; the background, a window lost, pause
// them (App.frame.pause: the next delta a period). Each turn begins a
// frame of Pointers' (Pointers.step) before its events.
//
// helder.async's loop (the main thread's, once something made it: a task
// launched, a job run) runs on the app's: a turn of it in each turn of the
// app's, after the events and before the frame, and wait bounded by its next
// timer and woken by its I/O and by other threads' posts (a job's reply):
// X11's wait polls the loop's descriptors with the connection's, the others
// wait at most 10 ms while I/O or a post may come. While there are no frames
// (Android and iOS in the background) the loop still turns; in the browser
// the page turns it between frames too, and while a hidden tab has none.
class App {
	public static var windows(default, null):Array<Window> = [];
	static var running = false;
	// the frame onFrame draws: its time (the display's vsync on Android and
	// iOS: App.frame.vsync), the time since the last, the display's period
	public static final frame = new FrameClock();

	public static function run(onFrame:Void->Void, onEvent:Event->Void) {
		running = true;
		// (helder.view.graph's writes land at the end of each event and frame)
		var frame = onFrame, event = onEvent;
		onFrame = () -> {
			frame();
			helder.view.graph.Graph.flush();
		};
		onEvent = e -> {
			event(e);
			helder.view.graph.Graph.flush();
		};
		// (the mouse's pointer events after its own: Pointers)
		onEvent = Pointers.relay(onEvent);
		if (Mem.os() == 3) {
			CanvasWindow.start(onFrame, onEvent);
			return;
		}
		while (turn(onFrame, onEvent)) {}
	}

	// one turn of the loop: false once it has ended
	@:allow(helder.os) static function turn(onFrame:Void->Void, onEvent:Event->Void):Bool {
		#if hxmc.dev
		// (hxmc dev: the dev server's messages; a build that handed over ends here)
		if (!helder.dev.Hot.poll()) running = false;
		#end
		if (!running || windows.length == 0) {
			running = false;
			// (Android: the vsync asked for comes first, its callback this build's code)
			if (Mem.target() >= 9) helder.os.android.Vsync.drain();
			return false;
		}
		// (the pointers' motion and presses from this turn's events on)
		Pointers.step();
		// (macOS: what Cocoa autoreleases during a frame is freed after it)
		var pool = Mem.os() == 1 ? Runtime.objc_autoreleasePoolPush() : Ptr.nil();
		// (Android: a frame only with the window, otherwise a sleep in the looper)
		if (Mem.target() >= 9) {
			AndroidWindow.poll(onEvent);
			loopTurn();
			if (running && windows.length > 0) {
				// (a frame at the display's vsync; until it comes, a sleep in the looper, woken by it)
				if (!AndroidWindow.drawable()) {
					frame.pause();
					AndroidWindow.wait(bounded(-1));
				} else if (helder.os.android.Vsync.ready()) {
					frame.tick(helder.os.android.Vsync.take(), true);
					onFrame();
				} else {
					helder.os.android.Vsync.request();
					AndroidWindow.wait(bounded(-1));
				}
			}
		} else if (Mem.platform() >= 1) {
			UIKitWindow.poll(onEvent);
			loopTurn();
			if (running && windows.length > 0) {
				// (a frame at the display link's; until it comes, the run loop, which it stops)
				if (!UIKitWindow.drawable()) {
					frame.pause();
					UIKitWindow.wait(bounded(-1));
				} else if (UIKitWindow.vsynced()) {
					frame.tick(UIKitWindow.takeVsync(), true);
					onFrame();
				} else {
					UIKitWindow.requestVsync();
					UIKitWindow.wait(bounded(-1));
				}
			}
		} else {
			if (Mem.os() == 1) CocoaWindow.poll(onFrame, onEvent) else if (Mem.os() == 2) Win32Window.poll(onFrame, onEvent) else if (Mem.os() == 3) CanvasWindow.poll(onEvent) else
				X11Window.poll(onEvent);
			loopTurn();
			if (running && windows.length > 0) {
				frame.tick(haxe.Timer.stamp(), false);
				onFrame();
			}
		}
		if (Mem.os() == 1) Runtime.objc_autoreleasePoolPop(pool);
		#if hxmc.dev
		helder.dev.Hot.framed();
		#end
		return true;
	}

	// (helder.async's loop, if made: what is ready, due timers)
	static inline function loopTurn() {
		var l = MainLoop.main;
		if (l != null) l.turn(0);
	}

	// (seconds bounded by the loop's timers and what it waits for)
	static inline function bounded(seconds:Float):Float {
		var l = MainLoop.main;
		return l != null ? l.bound(seconds) : seconds;
	}

	// blocks until an event is pending or seconds pass, or helder.async's
	// loop has something to run (the browser: returns at once,
	// requestAnimationFrame paces the loop)
	public static function wait(seconds:Float) {
		#if hxmc.dev
		// (hxmc dev: awake for the dev server's messages, which turn reads)
		if (seconds < 0 || seconds > 0.01) seconds = 0.01;
		#end
		// (iOS: the display link held while the app sleeps: no vsync wakes it; Android asks for none)
		if (Mem.platform() >= 1) UIKitWindow.pauseVsync();
		if (Mem.platform() >= 1) UIKitWindow.wait(bounded(seconds)) else if (Mem.os() == 1) CocoaWindow.wait(bounded(seconds)) else if (Mem.os() == 2)
			Win32Window.wait(bounded(seconds)) else if (Mem.os() == 3) {} else if (Mem.target() >= 9) AndroidWindow.wait(bounded(seconds)) else
			X11Window.waitFor(seconds);
	}

	public static function quit()
		running = false;

	// whether the system's appearance is dark: the browser's
	// prefers-color-scheme, macOS's AppleInterfaceStyle, iOS's trait collection, Windows'
	// AppsUseLightTheme (0), GTK's settings on Linux (GTK_THEME ending in
	// :dark, gtk-application-prefer-dark-theme or a dark theme's name in
	// settings.ini); cheap enough to ask now and then
	public static function prefersDark():Bool {
		if (Mem.os() == 3) return helder.os.web.Dom.prefers_dark() == 1;
		if (Mem.platform() >= 1) return UIKitWindow.dark();
		if (Mem.os() == 1) {
			var key = helder.os.objc.ObjC.str("AppleInterfaceStyle");
			var v = helder.os.objc.Msg.idPtr(helder.os.objc.Msg.id(helder.os.objc.ObjC.cls("NSUserDefaults"), helder.os.objc.ObjC.sel("standardUserDefaults")),
				helder.os.objc.ObjC.sel("stringForKey:"), key);
			helder.os.objc.ObjC.release(key);
			var s = v.isNull() ? null : helder.os.objc.ObjC.string(v);
			return s != null && s.toLowerCase() == "dark";
		}
		if (Mem.os() == 2) return Arena.scopedValue(a -> {
			var data:Ptr<Int32> = a.alloc(4), size:Ptr<Int32> = a.alloc(4);
			size.value = 4;
			// (HKEY_CURRENT_USER, RRF_RT_REG_DWORD)
			var hkcu = Ptr.ofI64(haxe.Int64.make(0xFFFFFFFF, 0x80000001));
			var r = helder.os.win32.User32.Advapi32.RegGetValueW(hkcu, a.wstring("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
				a.wstring("AppsUseLightTheme"), 0x10, Ptr.nil(), data, size);
			r == 0 && data.value == 0;
		});
		if (Mem.target() >= 9) return AndroidWindow.night();
		var gtk = Sys.getEnv("GTK_THEME");
		if (gtk != null) return StringTools.endsWith(gtk.toLowerCase(), ":dark") || gtk.toLowerCase().indexOf("dark") >= 0;
		var home = Sys.getEnv("HOME");
		var ini = try sys.io.File.getContent((Sys.getEnv("XDG_CONFIG_HOME") ?? home + "/.config") + "/gtk-3.0/settings.ini") catch (e:Dynamic) "";
		for (line in ini.split("\n")) {
			var l = StringTools.replace(StringTools.trim(line), " ", "").toLowerCase();
			if (l == "gtk-application-prefer-dark-theme=1" || l == "gtk-application-prefer-dark-theme=true") return true;
			if (StringTools.startsWith(l, "gtk-theme-name=") && l.indexOf("dark") >= 0) return true;
		}
		return false;
	}
}
