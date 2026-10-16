package hxmc.os;

// The app loop, callback driven (Cocoa, GTK and the browser own their
// loops): run calls onEvent for each pending event, then onFrame, until
// quit() or the last window closes. On X11 the loop is hxmc's own; a
// frame's pace comes from the GPU's present (vsync).
class App {
	public static var windows(default, null):Array<Window> = [];
	static var running = false;

	public static function run(onFrame:Void->Void, onEvent:Event->Void) {
		running = true;
		while (running && windows.length > 0) {
			hxmc.os.x11.X11Window.poll(onEvent);
			if (!running || windows.length == 0) break;
			onFrame();
		}
		running = false;
	}

	public static function quit()
		running = false;
}
