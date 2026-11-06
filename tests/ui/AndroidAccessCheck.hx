import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.view.*;

// helder.ui's accessibility on Android (AndroidAccess; CI's emulator job,
// tests/pack/android.sh): AccessFixture's controls in the window, read by
// `uiautomator dump` (the AccessibilityNodeInfos of the content view's
// virtual views, as TalkBack reads them). Its line once drawn: "access:
// ready"; then "access: asked" once a service asked for the tree.
class AndroidAccessCheck {
	static function main() {
		#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		helder.os.android.Activity.activity;
		#end
		var w = new UiWindow("fixture", 400, 640);
		var f = new AccessFixture();
		Render.render(f.view(), w.root);
		var frames = 0, told = false;
		w.onFrame = () -> {
			if (++frames == 3) Sys.println("access: ready");
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
