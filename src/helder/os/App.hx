package helder.os;

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
// present (vsync). In the browser (WebAssembly) run returns at once, and
// main after it: each turn of the loop is then a frame of
// requestAnimationFrame (CanvasWindow). A frame with nothing to draw calls
// wait, so that an idle app sleeps until the system has an event for it.
// On Android the loop runs on the program's own thread (helder.os.android:
// NativeActivity's callbacks reach it through the thread's looper), and a
// frame is drawn only while the activity has its window and is not paused
// (otherwise the loop sleeps in the looper). On iOS the program runs inside
// UIKit's loop (helder.os.uikit.UIKitApp): each turn runs the main run loop
// without waiting, and draws only while the app is not in the background
// (otherwise it sleeps in the run loop).
class App {
	public static var windows(default, null):Array<Window> = [];
	static var running = false;

	public static function run(onFrame:Void->Void, onEvent:Event->Void) {
		running = true;
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
			return false;
		}
		// (macOS: what Cocoa autoreleases during a frame is freed after it)
		var pool = Mem.os() == 1 ? Runtime.objc_autoreleasePoolPush() : Ptr.nil();
		// (Android: a frame only with the window, otherwise a sleep in the looper)
		if (Mem.target() >= 9) {
			AndroidWindow.poll(onEvent);
			if (running && windows.length > 0) {
				if (AndroidWindow.drawable()) onFrame() else AndroidWindow.wait(-1);
			}
		} else if (Mem.platform() >= 1) {
			UIKitWindow.poll(onEvent);
			if (running && windows.length > 0) {
				if (UIKitWindow.drawable()) onFrame() else UIKitWindow.wait(-1);
			}
		} else {
			if (Mem.os() == 1) CocoaWindow.poll(onEvent) else if (Mem.os() == 2) Win32Window.poll(onFrame, onEvent) else if (Mem.os() == 3) CanvasWindow.poll(onEvent) else
				X11Window.poll(onEvent);
			if (running && windows.length > 0) onFrame();
		}
		if (Mem.os() == 1) Runtime.objc_autoreleasePoolPop(pool);
		#if hxmc.dev
		helder.dev.Hot.framed();
		#end
		return true;
	}

	// blocks until an event is pending or seconds pass (the browser: returns
	// at once, requestAnimationFrame paces the loop)
	public static function wait(seconds:Float) {
		#if hxmc.dev
		// (hxmc dev: awake for the dev server's messages, which turn reads)
		if (seconds < 0 || seconds > 0.01) seconds = 0.01;
		#end
		if (Mem.platform() >= 1) UIKitWindow.wait(seconds) else if (Mem.os() == 1) CocoaWindow.wait(seconds) else if (Mem.os() == 2) Win32Window.wait(seconds) else if (Mem.os() == 3) {} else if (Mem.target() >= 9)
			AndroidWindow.wait(seconds) else X11Window.wait(seconds);
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
