package hxmc.os.android;

import hxmc.unsafe.*;

// Java's calls into the program, on the main thread (MainThread): the
// listeners of classes.dex (hxmc.android.Glue in hxmc: one Java class
// for every kind of listener, made with an id, its methods calling the
// static native event, registered here). A listener's handler gets the
// kind, the object the listener was given (a View, an Editable, a
// SurfaceHolder) and two ints; its result is a boolean listener's. A
// program using this gets classes.dex in its APK; one that sets the
// activity's content (setContentView) gets org.hxmc.Activity, whose window
// draws views (hxmc.android.Apk), otherwise NativeActivity's window stays
// the program's surface. After each call a frame is requested
// (MainThread.onFrame: what the handler changed is laid out).
@:hxmc.android
class Glue {
	// the kinds (hxmc.android.Glue's)
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
	// program calling this gets)
	public static function setContentView(view:Ptr)
		Jni.call(Jni.activity, Jni.method(Jni.cls("android.app.Activity"), "setContentView", "(Landroid/view/View;)V"), view.toI64());

	// the listener's handler goes (Java may still hold the listener: its calls do nothing)
	public static function release(id:Int)
		handlers.remove(id);

	@:hxmc.callback static function event(env:Ptr, cls:Ptr, id:Int, kind:Int, o:Ptr, a:Int, b:Int):Int {
		var h = handlers.get(id);
		var r = 0;
		if (h != null) r = try h(kind, o, a, b) catch (e:Dynamic) {
			Sys.println("hxmc.os: a Java listener: " + Std.string(e));
			0;
		}
		if (MainThread.onFrame != null) MainThread.requestFrame();
		return r;
	}
}
