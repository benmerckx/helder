package helder.os.android;

import helder.os.android.Jni;
import hxmc.unsafe.*;

// helder.os.Haptics on Android: the decor view's performHapticFeedback,
// on the main thread (MainThread.post: views are Java's there; the
// program's thread does not wait for it)
@:hxmc.android
class Haptic {
	public static function perform(strong:Bool)
		MainThread.post(() -> {
			if (Activity.activity.isNull()) return;
			var sdk = Mem.getI32(Activity.activity, 48);
			var win = Jni.obj(Jni.activity, Jni.method(Jni.cls("android.app.Activity"), "getWindow", "()Landroid/view/Window;"));
			var view = Jni.obj(win, Jni.method(Jni.cls("android.view.Window"), "getDecorView", "()Landroid/view/View;"));
			Jni.bool(view, Jni.method(Jni.cls("android.view.View"), "performHapticFeedback", "(I)Z"), helder.os.Haptics.androidFeedback(strong, sdk));
		});
}
