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
}
