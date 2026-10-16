package hxmc.os;

import hxmc.os.cocoa.CocoaWindow;
import hxmc.os.objc.Runtime;
import hxmc.os.x11.X11Window;
import hxmc.unsafe.*;

// The app loop, callback driven (Cocoa, GTK and the browser own their
// loops): run calls onEvent for each pending event, then onFrame, until
// quit() or the last window closes. The loop is hxmc's own, polling the
// system's events without waiting (CocoaWindow on macOS, X11Window
// elsewhere); a frame's pace comes from the GPU's present (vsync).
class App {
	public static var windows(default, null):Array<Window> = [];
	static var running = false;

	public static function run(onFrame:Void->Void, onEvent:Event->Void) {
		running = true;
		while (running && windows.length > 0) {
			// (macOS: what Cocoa autoreleases during a frame is freed after it)
			var pool = Mem.os() == 1 ? Runtime.objc_autoreleasePoolPush() : Ptr.nil();
			if (Mem.os() == 1) CocoaWindow.poll(onEvent) else X11Window.poll(onEvent);
			if (running && windows.length > 0) onFrame();
			if (Mem.os() == 1) Runtime.objc_autoreleasePoolPop(pool);
		}
		running = false;
	}

	public static function quit()
		running = false;
}
