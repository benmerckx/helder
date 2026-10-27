package helder.os.android;

import helder.os.Surface;
import helder.os.android.Native;
import hxmc.unsafe.*;

// A GPU view among views (the main thread, MainThread): a SurfaceView,
// whose surface (its holder's callbacks, through a Glue listener) becomes
// the ANativeWindow of an helder.os.Surface of kind Android, as the
// activity's window is for AndroidWindow: helder.gfx's GL back end makes its
// EGL surface on it, lets go of it when it goes (Surface.lost, before the
// callback returns: the system destroys the window after it) and makes one
// on the next. The handle is nil while there is none; changed() is called
// after each change (a frame to draw). The owner places `view` like any
// other view.
@:hxmc.android
class ChildSurface {
	public final surface = new Surface(Android, Ptr.nil(), Ptr.nil(), 0, 0);
	// the SurfaceView (a global reference)
	public final view:Ptr;
	public var changed:Null<Void->Void> = null;

	final listener:Int;
	static var getSurface = Ptr.nil();

	public function new() {
		var cls = Jni.cls("android.view.SurfaceView");
		var v = Jni.newObject(cls, Jni.method(cls, "<init>", "(Landroid/content/Context;)V"), Jni.activity.toI64());
		view = Jni.global(v);
		Jni.deleteLocal(v);
		var l = Glue.listener(event);
		listener = l.id;
		var holder = Jni.obj(view, Jni.method(cls, "getHolder", "()Landroid/view/SurfaceHolder;"));
		Jni.call(holder, Jni.method(Jni.cls("android.view.SurfaceHolder"), "addCallback", "(Landroid/view/SurfaceHolder$Callback;)V"), l.obj.toI64());
	}

	function event(kind:Int, holder:Ptr, a:Int, b:Int):Int {
		switch kind {
			case Glue.SURFACE_CREATED | Glue.SURFACE_CHANGED:
				if (getSurface.isNull()) getSurface = Jni.method(Jni.cls("android.view.SurfaceHolder"), "getSurface", "()Landroid/view/Surface;");
				var s = Jni.obj(holder, getSurface);
				var w = Android.ANativeWindow_fromSurface(Jni.env, s);
				Jni.deleteLocal(s);
				if (w == surface.handle) Android.ANativeWindow_release(w) else {
					drop();
					surface.reattach(w, Android.ANativeWindow_getWidth(w), Android.ANativeWindow_getHeight(w));
				}
				if (kind == Glue.SURFACE_CHANGED) surface.resized(a, b);
			case Glue.SURFACE_DESTROYED:
				drop();
			case _:
		}
		if (changed != null) changed();
		return 0;
	}

	// the window goes: the GPU lets go of it first
	function drop() {
		var w = surface.handle;
		if (w.isNull()) return;
		var lost = surface.lost;
		if (lost != null) lost();
		surface.reattach(Ptr.nil(), surface.width, surface.height);
		Android.ANativeWindow_release(w);
	}

	public function dispose() {
		drop();
		Glue.release(listener);
		Jni.deleteGlobal(view);
	}
}
