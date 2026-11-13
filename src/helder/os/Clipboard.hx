package helder.os;

import helder.os.cocoa.CocoaWindow;
import helder.os.uikit.UIKitWindow;
import helder.os.web.CanvasWindow;
import helder.os.win32.Win32Window;
import helder.os.x11.X11Window;
import helder.os.wayland.WaylandWindow;
import hxmc.Platform;

// The system clipboard's text. write puts text there; read hands it to a
// callback (null: no text there), at once on Windows and macOS, after a
// round trip of events on X11; iOS: UIPasteboard (the CLIPBOARD selection's owner converts
// it) and in the browser (the paste event of the key press that asked, or
// navigator.clipboard.readText). The window is the one asking: on X11 it
// owns the selection while its text is the clipboard's. Android: none yet
// (the system's ClipboardManager is Java's: JNI, hxmc's docs/plans/targets.md),
// write keeps nothing and read hands null.
class Clipboard {
	public static function write(window:Window, text:String) {
		if (Platform.apple() >= 1) UIKitWindow.writeClipboard(text) else if (Platform.os() == 1) CocoaWindow.writeClipboard(text) else if (Platform.os() == 2) (cast @:privateAccess window.native : Win32Window).writeClipboard(text) else
			if (Platform.os() == 3) CanvasWindow.writeClipboard(text) else if (Platform.target() >= 9) {} else if (Std.isOfType(@:privateAccess window.native, WaylandWindow))
				(cast @:privateAccess window.native : WaylandWindow).writeClipboard(text) else (cast @:privateAccess window.native : X11Window).writeClipboard(text);
	}

	public static function read(window:Window, callback:Null<String>->Void) {
		if (Platform.apple() >= 1) callback(UIKitWindow.readClipboard()) else if (Platform.os() == 1) callback(CocoaWindow.readClipboard()) else if (Platform.os() == 2) callback((cast @:privateAccess window.native : Win32Window).readClipboard()) else
			if (Platform.os() == 3) CanvasWindow.readClipboard(callback) else if (Platform.target() >= 9) callback(null) else
			if (Std.isOfType(@:privateAccess window.native, WaylandWindow)) (cast @:privateAccess window.native : WaylandWindow).readClipboard(callback) else
				(cast @:privateAccess window.native : X11Window).readClipboard(callback);
	}
}
