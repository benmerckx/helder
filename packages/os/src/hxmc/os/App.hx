package hxmc.os;

import hxmc.os.cocoa.CocoaWindow;
import hxmc.os.objc.Runtime;
import hxmc.os.web.CanvasWindow;
import hxmc.os.win32.Win32Window;
import hxmc.os.x11.X11Window;
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
	@:allow(hxmc.os) static function turn(onFrame:Void->Void, onEvent:Event->Void):Bool {
		if (!running || windows.length == 0) {
			running = false;
			return false;
		}
		// (macOS: what Cocoa autoreleases during a frame is freed after it)
		var pool = Mem.os() == 1 ? Runtime.objc_autoreleasePoolPush() : Ptr.nil();
		if (Mem.os() == 1) CocoaWindow.poll(onEvent) else if (Mem.os() == 2) Win32Window.poll(onEvent) else if (Mem.os() == 3) CanvasWindow.poll(onEvent) else
			X11Window.poll(onEvent);
		if (running && windows.length > 0) onFrame();
		if (Mem.os() == 1) Runtime.objc_autoreleasePoolPop(pool);
		return true;
	}

	// blocks until an event is pending or seconds pass (the browser: returns
	// at once, requestAnimationFrame paces the loop)
	public static function wait(seconds:Float) {
		if (Mem.os() == 1) CocoaWindow.wait(seconds) else if (Mem.os() == 2) Win32Window.wait(seconds) else if (Mem.os() == 3) {} else
			X11Window.wait(seconds);
	}

	public static function quit()
		running = false;

	// whether the system's appearance is dark: the browser's
	// prefers-color-scheme, macOS's AppleInterfaceStyle, Windows'
	// AppsUseLightTheme (0), GTK's settings on Linux (GTK_THEME ending in
	// :dark, gtk-application-prefer-dark-theme or a dark theme's name in
	// settings.ini); cheap enough to ask now and then
	public static function prefersDark():Bool {
		if (Mem.os() == 3) return hxmc.os.web.Dom.prefers_dark() == 1;
		if (Mem.os() == 1) {
			var key = hxmc.os.objc.ObjC.str("AppleInterfaceStyle");
			var v = hxmc.os.objc.Msg.idPtr(hxmc.os.objc.Msg.id(hxmc.os.objc.ObjC.cls("NSUserDefaults"), hxmc.os.objc.ObjC.sel("standardUserDefaults")),
				hxmc.os.objc.ObjC.sel("stringForKey:"), key);
			hxmc.os.objc.ObjC.release(key);
			var s = v.isNull() ? null : hxmc.os.objc.ObjC.string(v);
			return s != null && s.toLowerCase() == "dark";
		}
		if (Mem.os() == 2) return Arena.scopedValue(a -> {
			var data:Ptr<Int32> = a.alloc(4), size:Ptr<Int32> = a.alloc(4);
			size.value = 4;
			// (HKEY_CURRENT_USER, RRF_RT_REG_DWORD)
			var hkcu = Ptr.ofI64(haxe.Int64.make(0xFFFFFFFF, 0x80000001));
			var r = hxmc.os.win32.User32.Advapi32.RegGetValueW(hkcu, a.wstring("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
				a.wstring("AppsUseLightTheme"), 0x10, Ptr.nil(), data, size);
			r == 0 && data.value == 0;
		});
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
