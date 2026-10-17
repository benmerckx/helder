package hxmc.os.android;

import hxmc.unsafe.*;

// JNI from Haxe: JNIEnv and JavaVM are function tables behind a pointer,
// bound as COM's vtables are (hxmc.os.VTable: @:slot is the index in jni.h's
// JNINativeInterface and JNIInvokeInterface). Java's methods are called
// with the *A variants (arguments as an array of jvalue: 8 bytes each, so
// one Int64 per argument here), never the variadic ones. Jni's helpers are
// for the activity's main thread (MainThread), whose JNIEnv NativeActivity
// gives: classes found by the app's class loader (also those of
// classes.dex: hxmc.android.Glue's), a Java exception thrown after a call
// described in logcat, cleared and thrown again as a Haxe one with its text
// (a JNI call with one pending aborts the app), strings copied as UTF-16.
@:build(hxmc.os.VTable.build())
class JniEnv {
	@:slot(6) static function FindClass(env:Ptr, name:Ptr):Ptr;
	@:slot(15) static function ExceptionOccurred(env:Ptr):Ptr;
	@:slot(16) static function ExceptionDescribe(env:Ptr):Void;
	@:slot(17) static function ExceptionClear(env:Ptr):Void;
	@:slot(19) static function PushLocalFrame(env:Ptr, capacity:Int):Int;
	@:slot(20) static function PopLocalFrame(env:Ptr, result:Ptr):Ptr;
	@:slot(21) static function NewGlobalRef(env:Ptr, o:Ptr):Ptr;
	@:slot(22) static function DeleteGlobalRef(env:Ptr, o:Ptr):Void;
	@:slot(23) static function DeleteLocalRef(env:Ptr, o:Ptr):Void;
	@:slot(30) static function NewObjectA(env:Ptr, cls:Ptr, ctor:Ptr, args:Ptr):Ptr;
	@:slot(31) static function GetObjectClass(env:Ptr, o:Ptr):Ptr;
	@:slot(33) static function GetMethodID(env:Ptr, cls:Ptr, name:Ptr, sig:Ptr):Ptr;
	@:slot(36) static function CallObjectMethodA(env:Ptr, o:Ptr, m:Ptr, args:Ptr):Ptr;
	@:slot(39) static function CallBooleanMethodA(env:Ptr, o:Ptr, m:Ptr, args:Ptr):Int;
	@:slot(51) static function CallIntMethodA(env:Ptr, o:Ptr, m:Ptr, args:Ptr):Int;
	@:slot(57) static function CallFloatMethodA(env:Ptr, o:Ptr, m:Ptr, args:Ptr):Float32;
	@:slot(63) static function CallVoidMethodA(env:Ptr, o:Ptr, m:Ptr, args:Ptr):Void;
	@:slot(94) static function GetFieldID(env:Ptr, cls:Ptr, name:Ptr, sig:Ptr):Ptr;
	@:slot(100) static function GetIntField(env:Ptr, o:Ptr, f:Ptr):Int;
	@:slot(102) static function GetFloatField(env:Ptr, o:Ptr, f:Ptr):Float32;
	@:slot(109) static function SetIntField(env:Ptr, o:Ptr, f:Ptr, v:Int):Void;
	@:slot(113) static function GetStaticMethodID(env:Ptr, cls:Ptr, name:Ptr, sig:Ptr):Ptr;
	@:slot(116) static function CallStaticObjectMethodA(env:Ptr, cls:Ptr, m:Ptr, args:Ptr):Ptr;
	@:slot(131) static function CallStaticIntMethodA(env:Ptr, cls:Ptr, m:Ptr, args:Ptr):Int;
	@:slot(143) static function CallStaticVoidMethodA(env:Ptr, cls:Ptr, m:Ptr, args:Ptr):Void;
	@:slot(163) static function NewString(env:Ptr, chars:Ptr, length:Int):Ptr;
	@:slot(164) static function GetStringLength(env:Ptr, s:Ptr):Int;
	@:slot(215) static function RegisterNatives(env:Ptr, cls:Ptr, methods:Ptr, count:Int):Int;
	@:slot(220) static function GetStringRegion(env:Ptr, s:Ptr, start:Int, length:Int, buf:Ptr):Void;
	@:slot(228) static function ExceptionCheck(env:Ptr):Int;
}

@:build(hxmc.os.VTable.build())
class JavaVm {
	@:slot(4) static function AttachCurrentThread(vm:Ptr, env:Ptr<Ptr>, args:Ptr):Int;
	@:slot(5) static function DetachCurrentThread(vm:Ptr):Int;
	@:slot(6) static function GetEnv(vm:Ptr, env:Ptr<Ptr>, version:Int):Int;
}

@:hxmc.android
class Jni {
	// the main thread's JNIEnv (ANativeActivity.env), the activity (.clazz: a global reference)
	public static var env(get, never):Ptr;
	public static var activity(get, never):Ptr;

	static inline function get_env():Ptr
		return Mem.getPtr(Activity.activity, 16);

	static inline function get_activity():Ptr
		return Mem.getPtr(Activity.activity, 24);

	// the arguments of the next call (jvalue[8])
	static var args = Ptr.nil();
	static final classes = new Map<String, Ptr>();
	static var loadClass = Ptr.nil();
	static var loader = Ptr.nil();

	// a class by its Java name (android.widget.Button), a global reference
	// kept for the process: through the app's class loader (the activity's
	// getClassLoader), which knows classes.dex's (FindClass from a callback of
	// the system's looper would ask the system's loader, and NativeActivity's
	// own class is the framework's)
	public static function cls(name:String):Ptr {
		var c = classes.get(name);
		if (c != null) return c;
		var e = env;
		if (loader.isNull()) {
			args = LibC.malloc(64);
			var ac = JniEnv.GetObjectClass(e, activity);
			loader = JniEnv.NewGlobalRef(e, obj(activity, method(ac, "getClassLoader", "()Ljava/lang/ClassLoader;")));
			loadClass = method(JniEnv.GetObjectClass(e, loader), "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;");
		}
		var s = string(name);
		var local = obj(loader, loadClass, s.toI64());
		c = JniEnv.NewGlobalRef(e, local);
		JniEnv.DeleteLocalRef(e, local);
		JniEnv.DeleteLocalRef(e, s);
		classes.set(name, c);
		return c;
	}

	public static function method(cls:Ptr, name:String, sig:String):Ptr {
		var m = Arena.scopedValue(a -> JniEnv.GetMethodID(env, cls, a.cstring(name), a.cstring(sig)));
		check();
		return m;
	}

	public static function staticMethod(cls:Ptr, name:String, sig:String):Ptr {
		var m = Arena.scopedValue(a -> JniEnv.GetStaticMethodID(env, cls, a.cstring(name), a.cstring(sig)));
		check();
		return m;
	}

	public static function field(cls:Ptr, name:String, sig:String):Ptr {
		var f = Arena.scopedValue(a -> JniEnv.GetFieldID(env, cls, a.cstring(name), a.cstring(sig)));
		check();
		return f;
	}

	static var toString = Ptr.nil();

	// a pending Java exception: described in logcat, cleared, thrown as a
	// Haxe one (its toString)
	public static function check() {
		var e = env;
		if (JniEnv.ExceptionCheck(e) & 0xff == 0) return;
		var t = JniEnv.ExceptionOccurred(e);
		JniEnv.ExceptionDescribe(e);
		JniEnv.ExceptionClear(e);
		if (toString.isNull()) toString = method(cls("java.lang.Throwable"), "toString", "()Ljava/lang/String;");
		throw "hxmc.os: Java threw " + fromString(JniEnv.CallObjectMethodA(e, t, toString, args));
	}

	// the arguments of a call: a..d (an object's .toI64(), an Int, a bool's 0
	// or 1, a float's f(x))
	static inline function set(a:Int64, b:Int64, c:Int64, d:Int64):Ptr {
		var p = args;
		Mem.setI64(p, 0, a);
		Mem.setI64(p, 8, b);
		Mem.setI64(p, 16, c);
		Mem.setI64(p, 24, d);
		return p;
	}

	// a float argument (jfloat: its bits in the low half)
	public static function f(x:Float):Int64 {
		var p = args.add(56);
		Mem.setI64(p, 0, 0);
		Mem.setF32(p, 0, x);
		return Mem.getI64(p, 0);
	}

	public static function z(b:Bool):Int64
		return b ? 1 : 0;

	public static function newObject(cls:Ptr, ctor:Ptr, a:Int64 = 0, b:Int64 = 0, c:Int64 = 0, d:Int64 = 0):Ptr {
		var r = JniEnv.NewObjectA(env, cls, ctor, set(a, b, c, d));
		check();
		return r;
	}

	public static function call(o:Ptr, m:Ptr, a:Int64 = 0, b:Int64 = 0, c:Int64 = 0, d:Int64 = 0) {
		JniEnv.CallVoidMethodA(env, o, m, set(a, b, c, d));
		check();
	}

	public static function obj(o:Ptr, m:Ptr, a:Int64 = 0, b:Int64 = 0, c:Int64 = 0, d:Int64 = 0):Ptr {
		var r = JniEnv.CallObjectMethodA(env, o, m, set(a, b, c, d));
		check();
		return r;
	}

	public static function int(o:Ptr, m:Ptr, a:Int64 = 0, b:Int64 = 0, c:Int64 = 0, d:Int64 = 0):Int {
		var r = JniEnv.CallIntMethodA(env, o, m, set(a, b, c, d));
		check();
		return r;
	}

	public static function bool(o:Ptr, m:Ptr, a:Int64 = 0, b:Int64 = 0, c:Int64 = 0, d:Int64 = 0):Bool {
		var r = JniEnv.CallBooleanMethodA(env, o, m, set(a, b, c, d)) & 0xff;
		check();
		return r != 0;
	}

	public static function float(o:Ptr, m:Ptr, a:Int64 = 0, b:Int64 = 0, c:Int64 = 0, d:Int64 = 0):Float {
		var r:Float = JniEnv.CallFloatMethodA(env, o, m, set(a, b, c, d));
		check();
		return r;
	}

	public static function staticObj(cls:Ptr, m:Ptr, a:Int64 = 0, b:Int64 = 0, c:Int64 = 0, d:Int64 = 0):Ptr {
		var r = JniEnv.CallStaticObjectMethodA(env, cls, m, set(a, b, c, d));
		check();
		return r;
	}

	public static function staticInt(cls:Ptr, m:Ptr, a:Int64 = 0, b:Int64 = 0, c:Int64 = 0, d:Int64 = 0):Int {
		var r = JniEnv.CallStaticIntMethodA(env, cls, m, set(a, b, c, d));
		check();
		return r;
	}

	public static function staticCall(cls:Ptr, m:Ptr, a:Int64 = 0, b:Int64 = 0, c:Int64 = 0, d:Int64 = 0) {
		JniEnv.CallStaticVoidMethodA(env, cls, m, set(a, b, c, d));
		check();
	}

	public static inline function global(o:Ptr):Ptr
		return JniEnv.NewGlobalRef(env, o);

	public static inline function deleteGlobal(o:Ptr)
		JniEnv.DeleteGlobalRef(env, o);

	public static inline function deleteLocal(o:Ptr)
		JniEnv.DeleteLocalRef(env, o);

	// a java.lang.String of s (a local reference)
	public static function string(s:String):Ptr
		return Arena.scopedValue(a -> JniEnv.NewString(env, a.wstring(s), s.length));

	// a CharSequence's text (toString first: an Editable is one)
	public static function text(cs:Ptr):String {
		if (cs.isNull()) return "";
		var s = obj(cs, method(cls("java.lang.CharSequence"), "toString", "()Ljava/lang/String;"));
		var r = fromString(s);
		deleteLocal(s);
		return r;
	}

	// a java.lang.String's text
	public static function fromString(js:Ptr):String {
		if (js.isNull()) return "";
		var e = env;
		var n = JniEnv.GetStringLength(e, js);
		return Arena.scopedValue(a -> {
			var buf = a.alloc(2 * n + 2, 2);
			JniEnv.GetStringRegion(e, js, 0, n, buf);
			var s = hxmc.rt.Str.make(n);
			LibC.memcpy(hxmc.rt.Str.chars(s), buf, (2 * n : Int64));
			s;
		});
	}

	// natives of a class: name, JNI signature, the @:hxmc.callback's address
	public static function registerNatives(cls:Ptr, natives:Array<{name:String, sig:String, fn:Ptr}>) {
		Arena.scoped(a -> {
			var m = a.alloc(24 * natives.length);
			for (i in 0...natives.length) {
				Mem.setPtr(m, 24 * i, a.cstring(natives[i].name));
				Mem.setPtr(m, 24 * i + 8, a.cstring(natives[i].sig));
				Mem.setPtr(m, 24 * i + 16, natives[i].fn);
			}
			if (JniEnv.RegisterNatives(env, cls, m, natives.length) != 0) {
				check();
				throw "hxmc.os: RegisterNatives failed";
			}
		});
	}

	// a scope of local references (the code the system's looper calls on the
	// main thread has no Java frame that would free them)
	public static inline function pushFrame()
		JniEnv.PushLocalFrame(env, 64);

	public static inline function popFrame()
		JniEnv.PopLocalFrame(env, Ptr.nil());
}
