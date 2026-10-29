package helder.os.android;

import hxmc.unsafe.*;

// Java's calls into the program, on the main thread (MainThread): the
// listeners of classes.dex (helder.pack.android.Glue: one Java class
// for every kind of listener, made with an id, its methods calling the
// static native event, registered here). A listener's handler gets the
// kind, the object the listener was given (a View, an Editable, a
// SurfaceHolder) and two ints; its result is a boolean listener's. A
// program using this gets classes.dex in its APK; one that sets the
// activity's content (setContentView) gets org.hxmc.Activity, whose window
// draws views (helder.pack.android.Apk), otherwise NativeActivity's window stays
// the program's surface. After each call a frame is requested
// (MainThread.onFrame: what the handler changed is laid out).
// (@:helder.android.dex: an APK with this gets classes.dex,
// helder.pack.android.Classes)
@:hxmc.android @:helder.android.dex
class Glue {
	// the kinds (helder.pack.android.Glue's)
	public static inline var CLICK = 0;
	public static inline var TEXT = 1;
	public static inline var CHECKED = 2;
	public static inline var PROGRESS = 3;
	public static inline var EDITOR = 4;
	public static inline var LAYOUT = 5;
	public static inline var SURFACE_CREATED = 6;
	public static inline var SURFACE_CHANGED = 7;
	public static inline var SURFACE_DESTROYED = 8;
	public static inline var KEY = 9;

	static final handlers = new Map<Int, (kind:Int, o:Ptr, a:Int, b:Int) -> Int>();
	static var nextId = 1;
	static var cls = Ptr.nil();
	static var ctor = Ptr.nil();

	// a listener calling handler (a local reference to an org.hxmc.Glue) and its id
	public static function listener(handler:(kind:Int, o:Ptr, a:Int, b:Int) -> Int):{id:Int, obj:Ptr} {
		if (cls.isNull()) {
			cls = Jni.cls("org.hxmc.Glue");
			ctor = Jni.method(cls, "<init>", "(I)V");
			Jni.registerNatives(cls, [{name: "event", sig: "(IILjava/lang/Object;II)I", fn: Callback.addr(event)}]);
		}
		var id = nextId++;
		handlers.set(id, handler);
		return {id: id, obj: Jni.newObject(cls, ctor, id)};
	}

	// the activity's content: a view (only with org.hxmc.Activity, which a
	// program calling this gets); kept, for an activity made again in the
	// running process (a relaunch: Activity) gets it too
	public static function setContentView(view:Ptr) {
		if (!content.isNull()) Jni.deleteGlobal(content);
		content = Jni.global(view);
		AndroidWindow.recreated = () -> MainThread.post(moveContent);
		show();
	}

	static var content = Ptr.nil();

	static function show()
		Jni.call(Jni.activity, Jni.method(Jni.cls("android.app.Activity"), "setContentView", "(Landroid/view/View;)V"), content.toI64());

	// (the main thread, the new activity made) the content out of the old activity's window, into the new one's
	static function moveContent() {
		if (content.isNull() || Activity.activity.isNull()) return;
		var parent = Jni.obj(content, Jni.method(Jni.cls("android.view.View"), "getParent", "()Landroid/view/ViewParent;"));
		if (!parent.isNull())
			Jni.call(parent, Jni.method(Jni.cls("android.view.ViewGroup"), "removeView", "(Landroid/view/View;)V"), content.toI64());
		show();
		Sys.println("helder.os: the content moved to the new activity");
	}

	// the listener's handler goes (Java may still hold the listener: its calls do nothing)
	public static function release(id:Int)
		handlers.remove(id);

	@:hxmc.callback static function event(env:Ptr, cls:Ptr, id:Int, kind:Int, o:Ptr, a:Int, b:Int):Int {
		var h = handlers.get(id);
		var r = 0;
		if (h != null) r = try h(kind, o, a, b) catch (e:Dynamic) {
			Sys.println("helder.os: a Java listener: " + Std.string(e));
			0;
		}
		if (MainThread.onFrame != null) MainThread.requestFrame();
		return r;
	}
}
