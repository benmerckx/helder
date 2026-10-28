package helder.os.android;

import helder.os.android.Jni;
import hxmc.unsafe.*;

// The activity's window insets (AndroidWindow's safe area) and its
// immersive mode, through JNI on the main thread (MainThread: views are
// Java's there): the decor view's root WindowInsets, their overlap with
// the window (which the native window, NativeActivity's surface, covers):
// on API 30 getInsets(systemBars | displayCutout), the bars that show and
// the cutout; on API 29 the system window insets (the bars, the soft
// keyboard when it resizes) and the cutout's safe insets, the larger of
// each. The program's thread asks (ask: on its window's create, resize,
// content rect and configuration changes), the main thread measures and
// wakes it, and its loop takes the new ones (take) at its next turn, a
// Resize then (AndroidWindow.pump). Immersive (Window.immersive): the
// system's bars hidden (API 30: WindowInsetsController.hide, shown again
// by a swipe for a while; API 29: the immersive sticky flags) and the
// window into the cutout's edges (layoutInDisplayCutoutMode SHORT_EDGES).
@:hxmc.android
class Insets {
	static final lock = new sys.thread.Mutex();
	// left, top, right, bottom in pixels: the last measured (under the lock)
	static final values = [0, 0, 0, 0];
	static var fresh = false;
	static var asked = false;

	// (the program's thread) measured again, on the main thread
	public static function ask() {
		lock.acquire();
		var again = asked;
		asked = true;
		lock.release();
		if (!again) MainThread.post(measure);
	}

	// (the program's thread) the insets measured since the last take into
	// out (left, top, right, bottom); false: none new
	public static function take(out:Array<Int>):Bool {
		if (!fresh) return false;
		lock.acquire();
		for (k in 0...4)
			out[k] = values[k];
		fresh = false;
		lock.release();
		return true;
	}

	// the API level (ANativeActivity.sdkVersion)
	static inline function sdk():Int
		return Activity.activity.isNull() ? 0 : Mem.getI32(Activity.activity, 48);

	static function window():Ptr
		return Jni.obj(Jni.activity, Jni.method(Jni.cls("android.app.Activity"), "getWindow", "()Landroid/view/Window;"));

	static function decor(win:Ptr):Ptr
		return Jni.obj(win, Jni.method(Jni.cls("android.view.Window"), "getDecorView", "()Landroid/view/View;"));

	// WindowInsets.Type's systemBars() (and displayCutout())
	static function types(cutout:Bool):Int {
		var t = Jni.cls("android.view.WindowInsets$Type");
		var bars = Jni.staticInt(t, Jni.staticMethod(t, "systemBars", "()I"));
		return cutout ? bars | Jni.staticInt(t, Jni.staticMethod(t, "displayCutout", "()I")) : bars;
	}

	// (the main thread) the root insets now, for the program's thread
	public static function measure() {
		lock.acquire();
		asked = false;
		lock.release();
		if (Activity.activity.isNull()) return;
		var r = [0, 0, 0, 0];
		var wi = Jni.obj(decor(window()), Jni.method(Jni.cls("android.view.View"), "getRootWindowInsets", "()Landroid/view/WindowInsets;"));
		// (null: the decor view not attached yet; a content rect's change asks again)
		if (!wi.isNull()) {
			var cls = Jni.cls("android.view.WindowInsets");
			var sides = ["Left", "Top", "Right", "Bottom"];
			if (sdk() >= 30) {
				var ins = Jni.obj(wi, Jni.method(cls, "getInsets", "(I)Landroid/graphics/Insets;"), types(true));
				var ic = Jni.cls("android.graphics.Insets");
				for (k in 0...4)
					r[k] = JniEnv.GetIntField(Jni.env, ins, Jni.field(ic, sides[k].toLowerCase(), "I"));
			} else {
				for (k in 0...4)
					r[k] = Jni.int(wi, Jni.method(cls, "getSystemWindowInset" + sides[k], "()I"));
				var cut = Jni.obj(wi, Jni.method(cls, "getDisplayCutout", "()Landroid/view/DisplayCutout;"));
				if (!cut.isNull()) {
					var cc = Jni.cls("android.view.DisplayCutout");
					for (k in 0...4) {
						var c = Jni.int(cut, Jni.method(cc, "getSafeInset" + sides[k], "()I"));
						if (c > r[k]) r[k] = c;
					}
				}
			}
		}
		lock.acquire();
		for (k in 0...4)
			values[k] = r[k];
		fresh = true;
		lock.release();
	}

	// (the main thread) the system's bars hidden or shown again
	public static function immerse(on:Bool) {
		if (Activity.activity.isNull()) return;
		var win = window(), wc = Jni.cls("android.view.Window");
		if (sdk() >= 30) {
			var ctl = Jni.obj(win, Jni.method(wc, "getInsetsController", "()Landroid/view/WindowInsetsController;"));
			var ic = Jni.cls("android.view.WindowInsetsController");
			if (on) {
				// (BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE)
				Jni.call(ctl, Jni.method(ic, "setSystemBarsBehavior", "(I)V"), 2);
				Jni.call(ctl, Jni.method(ic, "hide", "(I)V"), types(false));
			} else Jni.call(ctl, Jni.method(ic, "show", "(I)V"), types(false));
		} else {
			// (SYSTEM_UI_FLAG_IMMERSIVE_STICKY, _LAYOUT_FULLSCREEN, _LAYOUT_HIDE_NAVIGATION,
			// _LAYOUT_STABLE, _FULLSCREEN, _HIDE_NAVIGATION)
			Jni.call(decor(win), Jni.method(Jni.cls("android.view.View"), "setSystemUiVisibility", "(I)V"), on ? 0x1706 : 0);
		}
		// (LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES while immersive, else the default)
		var lpc = Jni.cls("android.view.WindowManager$LayoutParams");
		var lp = Jni.obj(win, Jni.method(wc, "getAttributes", "()Landroid/view/WindowManager$LayoutParams;"));
		JniEnv.SetIntField(Jni.env, lp, Jni.field(lpc, "layoutInDisplayCutoutMode", "I"), on ? 1 : 0);
		Jni.check();
		Jni.call(win, Jni.method(wc, "setAttributes", "(Landroid/view/WindowManager$LayoutParams;)V"), lp.toI64());
	}
}
