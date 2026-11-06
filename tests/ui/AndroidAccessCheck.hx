import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.view.*;

// helder.ui's accessibility on Android (AndroidAccess; CI's emulator job,
// tests/pack/android.sh): AccessFixture's controls in the window, read by
// `uiautomator dump` (the AccessibilityNodeInfos of the content view's
// virtual views, as TalkBack reads them; the first question makes the
// program publish its tree, so android.sh dumps twice). Its line once drawn:
// "access: ready"; then "access: asked" once a service asked for the tree.
class AndroidAccessCheck {
	static function main() {
		#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		helder.os.android.Activity.activity;
		#end
		Sys.println("access: started");
		var w = new UiWindow("fixture", 400, 640);
		Sys.println("access: a window");
		var f = new AccessFixture();
		Render.render(f.view(), w.root);
		var frames = 0, told = false;
		w.onFrame = () -> {
			if (++frames == 1) Sys.println("access: a first frame");
			if (frames == 3) Sys.println("access: ready");
			// (a few frames: the layout settled; then frames as the tree asks them, a service's first question one)
			if (frames < 3) w.ui.requestFrame();
			#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
			var a:Null<helder.ui.draw.AndroidAccess> = cast @:privateAccess w.androidAccess;
			if (!told && a != null && a.listening()) {
				told = true;
				Sys.println("access: asked");
			}
			#end
		};
		UiWindow.run();
	}
}
