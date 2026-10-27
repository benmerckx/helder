package helder.os.objc;

import hxmc.unsafe.*;

// objc_msgSend, one typed C call per shape (Sender; AppKit's and UIKit's): a message is
// `Msg.idPtr(receiver, ObjC.sel("initWithUTF8String:"), cstring)`. Names: the
// result (id, v: void, i: an NSInteger or NSUInteger, b: BOOL, f: a double,
// or a struct), then the arguments. Structs go by value (arm64: hxmc's
// structs by value; x86-64 would need objc_msgSend_stret for results over
// 16 bytes).
@:build(helder.os.objc.Sender.build())
class Msg {
	// objc_msgSend's address (libobjc is loaded: Runtime imports from it)
	public static final send:Ptr = Posix.dlsym(Ptr.ofI64(-2), Mem.cstr("objc_msgSend")); // (RTLD_DEFAULT)

	static function id(self:Ptr, sel:Ptr):Ptr;
	static function idPtr(self:Ptr, sel:Ptr, a:Ptr):Ptr;
	static function idPtrPtr(self:Ptr, sel:Ptr, a:Ptr, b:Ptr):Ptr;
	static function idPtrPtrPtr(self:Ptr, sel:Ptr, a:Ptr, b:Ptr, c:Ptr):Ptr;
	static function idInt(self:Ptr, sel:Ptr, a:Int64):Ptr;
	static function idFloat(self:Ptr, sel:Ptr, a:Float):Ptr;
	static function idFloatPtrPtrPtrBool(self:Ptr, sel:Ptr, a:Float, b:Ptr, c:Ptr, d:Ptr, e:Bool):Ptr;
	static function idIntInt(self:Ptr, sel:Ptr, a:Int64, b:Int64):Ptr;
	static function idPtrIntInt(self:Ptr, sel:Ptr, a:Ptr, b:Int64, c:Int64):Ptr;
	static function idIntIntIntBool(self:Ptr, sel:Ptr, a:Int64, b:Int64, c:Int64, d:Bool):Ptr;
	static function idIntPtrPtrBool(self:Ptr, sel:Ptr, a:Int64, b:Ptr, c:Ptr, d:Bool):Ptr;
	static function idRectIntIntBool(self:Ptr, sel:Ptr, r:CGRect, a:Int64, b:Int64, c:Bool):Ptr;
	static function idRect(self:Ptr, sel:Ptr, r:CGRect):Ptr;
	static function idPoint(self:Ptr, sel:Ptr, p:CGPoint):Ptr;
	static function idPtrInt(self:Ptr, sel:Ptr, a:Ptr, b:Int64):Ptr;
	static function rectRect(self:Ptr, sel:Ptr, r:CGRect):CGRect;
	static function rectRectPtr(self:Ptr, sel:Ptr, r:CGRect, a:Ptr):CGRect;
	static function idIntPointIntFloatIntPtrPtrPtrBoolU16(self:Ptr, sel:Ptr, a:Int64, p:CGPoint, b:Int64, c:Float, d:Int64, e:Ptr, f:Ptr, g:Ptr, h:Bool,
		i:UInt16):Ptr;
	static function v(self:Ptr, sel:Ptr):Void;
	static function vPtr(self:Ptr, sel:Ptr, a:Ptr):Void;
	static function vInt(self:Ptr, sel:Ptr, a:Int64):Void;
	static function vBool(self:Ptr, sel:Ptr, a:Bool):Void;
	static function vFloat(self:Ptr, sel:Ptr, a:Float):Void;
	static function vSize(self:Ptr, sel:Ptr, a:CGSize):Void;
	static function vRect(self:Ptr, sel:Ptr, a:CGRect):Void;
	static function vPtrBool(self:Ptr, sel:Ptr, a:Ptr, b:Bool):Void;
	static function vPtrPtr(self:Ptr, sel:Ptr, a:Ptr, b:Ptr):Void;
	// (an NSRange by value: two NSUIntegers)
	static function vPtrIntInt(self:Ptr, sel:Ptr, a:Ptr, b:Int64, c:Int64):Void;
	static function vPtrIntIntIntInt(self:Ptr, sel:Ptr, a:Ptr, b:Int64, c:Int64, d:Int64, e:Int64):Void;
	static function b(self:Ptr, sel:Ptr):Bool;
	static function bPtr(self:Ptr, sel:Ptr, a:Ptr):Bool;
	static function i(self:Ptr, sel:Ptr):Int64;
	static function iInt(self:Ptr, sel:Ptr, a:Int64):Int64;
	static function iPtr(self:Ptr, sel:Ptr, a:Ptr):Int64;
	static function u16Int(self:Ptr, sel:Ptr, a:Int64):UInt16;
	static function f(self:Ptr, sel:Ptr):Float;
	static function rect(self:Ptr, sel:Ptr):CGRect;
	static function point(self:Ptr, sel:Ptr):CGPoint;
	static function pointPointPtr(self:Ptr, sel:Ptr, p:CGPoint, view:Ptr):CGPoint;
	static function pointPtr(self:Ptr, sel:Ptr, a:Ptr):CGPoint;
	static function insets(self:Ptr, sel:Ptr):UIEdgeInsets;
}
