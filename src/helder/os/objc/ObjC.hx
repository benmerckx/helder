package helder.os.objc;

import hxmc.unsafe.*;

// Shorthands over Runtime and Msg: classes and selectors by name (a string
// literal: its C string is in read-only data), NSString in and out.
class ObjC {
	public static inline function cls(name:String):Ptr
		return Runtime.objc_getClass(Mem.cstr(name));

	public static inline function sel(name:String):Ptr
		return Runtime.sel_registerName(Mem.cstr(name));

	// a new NSString of s (owned: release it)
	public static function str(s:String):Ptr
		return Arena.scopedValue(a -> Msg.idPtr(Msg.id(cls("NSString"), sel("alloc")), sel("initWithUTF8String:"), a.cstring(s)));

	// the contents of an NSString (null: none)
	public static function string(ns:Ptr):Null<String> {
		if (ns.isNull()) return null;
		var s:Ptr<UInt8> = Msg.id(ns, sel("UTF8String"));
		return (s : CString).toString();
	}

	public static inline function release(o:Ptr)
		if (!o.isNull()) Runtime.objc_release(o);
}
