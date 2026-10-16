package hxmc.os.objc;

import hxmc.unsafe.*;

// objc_msgSend, one typed C call per shape (Sender): a message is
// `Msg.idPtr(receiver, ObjC.sel("initWithUTF8String:"), cstring)`. Names: the
// result (id, v: void, i: an NSInteger or NSUInteger, b: BOOL, f: a double,
// or a struct), then the arguments. Structs go by value (arm64: hxmc's
// structs by value; x86-64 would need objc_msgSend_stret for results over
// 16 bytes).
@:build(hxmc.os.objc.Sender.build())
class Msg {
	// objc_msgSend's address (libobjc is loaded: Runtime imports from it)
	public static final send:Ptr = Posix.dlsym(Ptr.ofI64(-2), Mem.cstr("objc_msgSend")); // (RTLD_DEFAULT)

	static function id(self:Ptr, sel:Ptr):Ptr;
	static function idPtr(self:Ptr, sel:Ptr, a:Ptr):Ptr;
	static function idPtrPtr(self:Ptr, sel:Ptr, a:Ptr, b:Ptr):Ptr;
	static function idPtrPtrPtr(self:Ptr, sel:Ptr, a:Ptr, b:Ptr, c:Ptr):Ptr;
	static function idInt(self:Ptr, sel:Ptr, a:Int64):Ptr;
	static function idIntInt(self:Ptr, sel:Ptr, a:Int64, b:Int64):Ptr;
	static function idPtrIntInt(self:Ptr, sel:Ptr, a:Ptr, b:Int64, c:Int64):Ptr;
	static function idIntIntIntBool(self:Ptr, sel:Ptr, a:Int64, b:Int64, c:Int64, d:Bool):Ptr;
	static function idIntPtrPtrBool(self:Ptr, sel:Ptr, a:Int64, b:Ptr, c:Ptr, d:Bool):Ptr;
	static function idRectIntIntBool(self:Ptr, sel:Ptr, r:CGRect, a:Int64, b:Int64, c:Bool):Ptr;
	static function v(self:Ptr, sel:Ptr):Void;
	static function vPtr(self:Ptr, sel:Ptr, a:Ptr):Void;
	static function vInt(self:Ptr, sel:Ptr, a:Int64):Void;
	static function vBool(self:Ptr, sel:Ptr, a:Bool):Void;
	static function vFloat(self:Ptr, sel:Ptr, a:Float):Void;
	static function vSize(self:Ptr, sel:Ptr, a:CGSize):Void;
	static function i(self:Ptr, sel:Ptr):Int64;
	static function iInt(self:Ptr, sel:Ptr, a:Int64):Int64;
	static function iPtr(self:Ptr, sel:Ptr, a:Ptr):Int64;
	static function u16Int(self:Ptr, sel:Ptr, a:Int64):UInt16;
	static function f(self:Ptr, sel:Ptr):Float;
	static function rect(self:Ptr, sel:Ptr):CGRect;
	static function point(self:Ptr, sel:Ptr):CGPoint;
	static function pointPointPtr(self:Ptr, sel:Ptr, p:CGPoint, view:Ptr):CGPoint;
}
