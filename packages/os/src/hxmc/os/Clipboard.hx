package hxmc.os;

import hxmc.os.cocoa.CocoaWindow;
import hxmc.os.web.CanvasWindow;
import hxmc.os.win32.Win32Window;
import hxmc.os.x11.X11Window;
import hxmc.unsafe.Mem;

// The system clipboard's text. write puts text there; read hands it to a
// callback (null: no text there), at once on Windows and macOS, after a
// round trip of events on X11 (the CLIPBOARD selection's owner converts
// it) and in the browser (the paste event of the key press that asked, or
// navigator.clipboard.readText). The window is the one asking: on X11 it
// owns the selection while its text is the clipboard's. Android: none yet
// (the system's ClipboardManager is Java's: JNI, docs/plans/targets.md),
// write keeps nothing and read hands null.
class Clipboard {
	public static function write(window:Window, text:String) {
		if (Mem.os() == 1) CocoaWindow.writeClipboard(text) else if (Mem.os() == 2) (cast @:privateAccess window.native : Win32Window).writeClipboard(text) else
			if (Mem.os() == 3) CanvasWindow.writeClipboard(text) else if (Mem.target() >= 9) {} else (cast @:privateAccess window.native : X11Window).writeClipboard(text);
	}

	public static function read(window:Window, callback:Null<String>->Void) {
		if (Mem.os() == 1) callback(CocoaWindow.readClipboard()) else if (Mem.os() == 2) callback((cast @:privateAccess window.native : Win32Window).readClipboard()) else
			if (Mem.os() == 3) CanvasWindow.readClipboard(callback) else if (Mem.target() >= 9) callback(null) else
			(cast @:privateAccess window.native : X11Window).readClipboard(callback);
	}
}
