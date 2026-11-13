package helder.native;

// What helder/native's C calls (native.c, a definition: the lowering's
// Natives) do around a call where values cross: a string as a C string, a
// typed array's bytes in C's memory, and back. Addresses are numbers
// (doubles: an address of today's machines fits in their 53 bits), C's
// memory malloc's. A program calls them through helder/native (native.string,
// native.free...), the lowering for a call's arguments.
class Script {
	// s as a NUL-terminated UTF-8 string in C's memory (free it), 0 for null
	public static function cstring(s:Null<String>):Float {
		#if (target.name == "hxmc")
		if (s == null) return 0;
		var p = hxmc.unsafe.LibC.malloc((3 * s.length + 1 : hxmc.I64));
		hxmc.rt.MemRepr.utf8To(s, p);
		return address(p);
		#else
		return 0;
		#end
	}

	// the NUL-terminated UTF-8 string at an address, copied (null for 0)
	public static function string(at:Float):Null<String> {
		#if (target.name == "hxmc")
		if (at == 0) return null;
		var c:hxmc.unsafe.CString = cast pointer(at);
		return c.toString();
		#else
		return null;
		#end
	}

	// b's bytes copied into C's memory (free it with back), 0 for null
	public static function bytesIn(b:Null<haxe.io.Bytes>):Float {
		#if (target.name == "hxmc")
		if (b == null) return 0;
		var p = hxmc.unsafe.LibC.malloc(((b.length > 0 ? b.length : 1) : hxmc.I64));
		if (b.length > 0) hxmc.unsafe.LibC.memcpy(p, hxmc.unsafe.BytesPtr.of(b, 0, b.length), (b.length : hxmc.I64));
		return address(p);
		#else
		return 0;
		#end
	}

	// after the call: what C left at an address bytesIn made copied back into b, the memory freed
	public static function bytesBack(at:Float, b:Null<haxe.io.Bytes>) {
		#if (target.name == "hxmc")
		if (at == 0 || b == null) return;
		if (b.length > 0) hxmc.unsafe.BytesPtr.copyIn(b, 0, pointer(at), b.length);
		free(at);
		#end
	}

	// C's memory of malloc's (cstring's, bytesIn's, a C function's) freed
	public static function free(at:Float) {
		#if (target.name == "hxmc")
		if (at != 0) hxmc.unsafe.LibC.free(pointer(at));
		#end
	}

	// n bytes at an address, copied
	public static function bytesAt(at:Float, n:Int):haxe.io.Bytes {
		var b = haxe.io.Bytes.alloc(n);
		#if (target.name == "hxmc")
		if (n > 0 && at != 0) hxmc.unsafe.BytesPtr.copyIn(b, 0, pointer(at), n);
		#end
		return b;
	}

	// the word (a pointer, 8 bytes) at index of the words at an address: a
	// vtable's entry (native.com's and native.jni's methods: the function at
	// a slot of an object's table, word(word(object, 0), slot))
	public static function word(at:Float, index:Int):Float {
		#if (target.name == "hxmc")
		if (at == 0) throw "helder/native: a method called on a null pointer";
		var p:hxmc.unsafe.Ptr<hxmc.unsafe.Ptr> = pointer(at);
		return address(p[index]);
		#else
		return 0;
		#end
	}

	// a GUID ("{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}") in C's memory, its 16
	// bytes as Windows lays them out, kept for the process (native.com's IIDs
	// and CLSIDs)
	public static function guid(text:String):Float {
		var h = StringTools.replace(StringTools.replace(StringTools.replace(text, "{", ""), "}", ""), "-", "");
		if (h.length != 32 || !~/^[0-9a-fA-F]+$/.match(h)) throw 'helder/native: "$text" is no GUID ({xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx})';
		var b = haxe.io.Bytes.alloc(16);
		inline function hex(i:Int, n:Int):Int
			return Std.parseInt("0x" + h.substr(i, n));
		b.setInt32(0, hex(0, 8));
		b.setUInt16(4, hex(8, 4));
		b.setUInt16(6, hex(12, 4));
		for (i in 0...8)
			b.set(8 + i, hex(16 + 2 * i, 2));
		return bytesIn(b);
	}

	// a COM object of the class clsid, by its interface iid (native.com's
	// create: CoInitializeEx once, apartment-threaded, then CoCreateInstance
	// in process or local; a failure thrown with its HRESULT)
	public static function comCreate(clsid:Float, iid:Float):Float {
		#if (target.name == "hxmc")
		if (hxmc.Platform.os() == 2) {
			if (!comReady) {
				ScriptCom.CoInitializeEx(hxmc.unsafe.Ptr.nil(), 2);
				comReady = true;
			}
			var out:hxmc.unsafe.Ptr<hxmc.unsafe.Ptr> = hxmc.unsafe.LibC.malloc(8);
			out.value = hxmc.unsafe.Ptr.nil();
			var hr = ScriptCom.CoCreateInstance(pointer(clsid), hxmc.unsafe.Ptr.nil(), 1 | 4, pointer(iid), out);
			var r = out.value;
			hxmc.unsafe.LibC.free(out);
			if (hr < 0) throw "helder/native: CoCreateInstance failed: HRESULT 0x" + StringTools.hex(hr, 8);
			return address(r);
		}
		#end
		throw "helder/native: COM is Windows'";
	}

	#if (target.name == "hxmc")
	static var comReady = false;
	#end

	// JNI (native.jni; Android): the calling thread's JNIEnv (the program's
	// thread attached to the activity's VM: ScriptJni)
	public static function jniEnv():Float {
		#if (target.name == "hxmc")
		if (hxmc.Platform.target() >= 9) return address(ScriptJni.env());
		#end
		throw "helder/native: JNI is Android's";
	}

	// a class by its name (android/os/Build$VERSION), a global reference
	// kept for the process
	public static function jniClass(name:String):Float {
		#if (target.name == "hxmc")
		if (hxmc.Platform.target() >= 9) return address(ScriptJni.cls(name));
		#end
		throw "helder/native: JNI is Android's";
	}

	// a method's ID (kind 0: an instance's, 1: a static one) or a field's
	// (2: an instance's, 3: a static one) by its name and JNI descriptor; a
	// missing one thrown
	public static function jniMember(cls:Float, name:String, descriptor:String, kind:Int):Float {
		#if (target.name == "hxmc")
		if (hxmc.Platform.target() >= 9) return address(ScriptJni.member(pointer(cls), name, descriptor, kind));
		#end
		throw "helder/native: JNI is Android's";
	}

	// the arguments of the next JNI call (jvalue[16]): argument i set (kind:
	// 0 an integer or a reference, 1 a jfloat, 2 a jdouble, 3 a jboolean)
	public static function jniArg(i:Int, kind:Int, v:Float) {
		#if (target.name == "hxmc")
		var at = jniArgs();
		var p = pointer(at).add(8 * i);
		hxmc.unsafe.Mem.setI64(p, 0, 0);
		switch kind {
			case 1: hxmc.unsafe.Mem.setF32(p, 0, v);
			case 2: hxmc.unsafe.Mem.setF64(p, 0, v);
			case 3: hxmc.unsafe.Mem.setI64(p, 0, v != 0 ? 1 : 0);
			case _: hxmc.unsafe.Mem.setI64(p, 0, haxe.Int64.fromFloat(v));
		}
		#end
	}

	// the address of those arguments
	public static function jniArgs():Float {
		#if (target.name == "hxmc")
		if (jvalues.isNull()) jvalues = hxmc.unsafe.LibC.malloc(16 * 8);
		return address(jvalues);
		#else
		return 0;
		#end
	}

	#if (target.name == "hxmc")
	static var jvalues = hxmc.unsafe.Ptr.nil();
	#end

	// after a JNI call: a pending Java exception thrown (its text), cleared
	public static function jniCheck() {
		#if (target.name == "hxmc")
		if (hxmc.Platform.target() >= 9) ScriptJni.check();
		#end
	}

	// a java.lang.String of s (a local reference; 0 for null)
	public static function jniString(s:Null<String>):Float {
		#if (target.name == "hxmc")
		if (hxmc.Platform.target() >= 9) return s == null ? 0 : address(ScriptJni.string(s));
		#end
		throw "helder/native: JNI is Android's";
	}

	// a java.lang.String's text (null for 0), its local reference deleted
	public static function jniText(at:Float):Null<String> {
		#if (target.name == "hxmc")
		if (hxmc.Platform.target() >= 9) return at == 0 ? null : ScriptJni.text(pointer(at));
		#end
		throw "helder/native: JNI is Android's";
	}

	#if (target.name == "hxmc")
	static function address(p:hxmc.unsafe.Ptr):Float {
		var v:haxe.Int64 = p.toI64();
		var lo = v.low;
		return v.high * 4294967296.0 + (lo < 0 ? lo + 4294967296.0 : lo);
	}

	static function pointer(at:Float):hxmc.unsafe.Ptr
		return hxmc.unsafe.Ptr.ofI64(haxe.Int64.fromFloat(at));
	#end
}

#if (target.name == "hxmc")
// (COM's creation, Script.comCreate: Windows only, linked where it is called)
@:hxmc.c @:hxmc.lib("ole32") extern class ScriptCom {
	static function CoInitializeEx(reserved:hxmc.unsafe.Ptr, flags:Int):Int;
	static function CoCreateInstance(clsid:hxmc.unsafe.Ptr, outer:hxmc.unsafe.Ptr, context:Int, iid:hxmc.unsafe.Ptr, out:hxmc.unsafe.Ptr<hxmc.unsafe.Ptr>):Int;
}
#end

#if (target.name == "hxmc")
// (JNI for Script on the calling thread: helder.os.android.Jni's helpers are
// the activity's main thread's, the program runs on a thread of its own:
// attached to the VM, its own JNIEnv; classes by FindClass, the system's)
private class ScriptJni {
	static final classes = new Map<String, hxmc.unsafe.Ptr>();

	public static function env():hxmc.unsafe.Ptr {
		// (a cell of hxmc's own JNI calls, named here only: the program counts
		// as one calling Java (hxmc_stack_flags' JNI, DataGen.jniCells), so its
		// main keeps the thread's own stack: ART's AttachCurrentThread checks
		// the stack pointer against the stack the thread was given, and aborts
		// on hxmc's reserved stack (InitStackHwm's FindStackTop); written, so
		// the reference stays)
		hxmc.unsafe.Mem.setI64(hxmc.unsafe.Mem.sym("hxmc$jni$68656c646572206e6174697665"), 0, 1);
		var vm =hxmc.unsafe.Mem.getPtr(helder.os.android.Activity.activity, 8);
		var out:hxmc.unsafe.Ptr<hxmc.unsafe.Ptr> = hxmc.unsafe.LibC.malloc(8);
		out.value = hxmc.unsafe.Ptr.nil();
		// (JNI_VERSION_1_6; JNI_EDETACHED: attached)
		if (helder.os.android.Jni.JavaVm.GetEnv(vm, out, 0x10006) != 0) helder.os.android.Jni.JavaVm.AttachCurrentThread(vm, out, hxmc.unsafe.Ptr.nil());
		var e = out.value;
		hxmc.unsafe.LibC.free(out);
		return e;
	}

	public static function cls(name:String):hxmc.unsafe.Ptr {
		var c = classes.get(name);
		if (c != null) return c;
		var e = env();
		var local = hxmc.unsafe.Arena.scopedValue(a -> helder.os.android.Jni.JniEnv.FindClass(e, a.cstring(StringTools.replace(name, ".", "/"))));
		check();
		c = helder.os.android.Jni.JniEnv.NewGlobalRef(e, local);
		helder.os.android.Jni.JniEnv.DeleteLocalRef(e, local);
		classes.set(name, c);
		return c;
	}

	public static function member(c:hxmc.unsafe.Ptr, name:String, descriptor:String, kind:Int):hxmc.unsafe.Ptr {
		var e = env();
		var m = hxmc.unsafe.Arena.scopedValue(a -> {
			var n = a.cstring(name), d = a.cstring(descriptor);
			switch kind {
				case 0: helder.os.android.Jni.JniEnv.GetMethodID(e, c, n, d);
				case 1: helder.os.android.Jni.JniEnv.GetStaticMethodID(e, c, n, d);
				case 2: helder.os.android.Jni.JniEnv.GetFieldID(e, c, n, d);
				case _: helder.os.android.Jni.JniEnv.GetStaticFieldID(e, c, n, d);
			}
		});
		check();
		if (m.isNull()) throw 'helder/native: no Java member $name $descriptor';
		return m;
	}

	// a pending exception: described in logcat, cleared, thrown with its toString
	public static function check() {
		var e = env();
		if (helder.os.android.Jni.JniEnv.ExceptionCheck(e) & 0xff == 0) return;
		var t = helder.os.android.Jni.JniEnv.ExceptionOccurred(e);
		helder.os.android.Jni.JniEnv.ExceptionDescribe(e);
		helder.os.android.Jni.JniEnv.ExceptionClear(e);
		var m = hxmc.unsafe.Arena.scopedValue(a -> helder.os.android.Jni.JniEnv.GetMethodID(e, helder.os.android.Jni.JniEnv.GetObjectClass(e, t),
			a.cstring("toString"), a.cstring("()Ljava/lang/String;")));
		var s = helder.os.android.Jni.JniEnv.CallObjectMethodA(e, t, m, hxmc.unsafe.Ptr.nil());
		throw "helder/native: Java threw " + text(s);
	}

	public static function string(s:String):hxmc.unsafe.Ptr {
		var e = env();
		return hxmc.unsafe.Arena.scopedValue(a -> helder.os.android.Jni.JniEnv.NewString(e, a.wstring(s), s.length));
	}

	public static function text(js:hxmc.unsafe.Ptr):String {
		var e = env();
		var n = helder.os.android.Jni.JniEnv.GetStringLength(e, js);
		var r = hxmc.unsafe.Arena.scopedValue(a -> {
			var buf = a.alloc(2 * n + 2, 2);
			helder.os.android.Jni.JniEnv.GetStringRegion(e, js, 0, n, buf);
			var s = hxmc.rt.Str.make2(n);
			hxmc.unsafe.LibC.memcpy(hxmc.rt.Str.unitsAddr(s), buf, (2 * n : hxmc.I64));
			s;
		});
		helder.os.android.Jni.JniEnv.DeleteLocalRef(e, js);
		return r;
	}
}
#end
