package hxmc.ui.native.appkit;

import hxmc.os.objc.CGPoint;
import hxmc.os.objc.CGRect;
import hxmc.os.objc.CGSize;
import hxmc.unsafe.*;

// The message shapes AppKitBackend sends (hxmc.os.objc.Sender, as Msg's):
// named by the result (id, v: void, i: an integer, b: BOOL, f: a double,
// or a struct), then the arguments.
@:build(hxmc.os.objc.Sender.build())
class AkMsg {
	static function id(self:Ptr, sel:Ptr):Ptr;
	static function idPtr(self:Ptr, sel:Ptr, a:Ptr):Ptr;
	static function idPtrPtr(self:Ptr, sel:Ptr, a:Ptr, b:Ptr):Ptr;
	static function idPtrPtrPtr(self:Ptr, sel:Ptr, a:Ptr, b:Ptr, c:Ptr):Ptr;
	static function idPtrInt(self:Ptr, sel:Ptr, a:Ptr, b:Int64):Ptr;
	static function idIntPtr(self:Ptr, sel:Ptr, a:Int64, b:Ptr):Ptr;
	static function idInt(self:Ptr, sel:Ptr, a:Int64):Ptr;
	static function idFloat(self:Ptr, sel:Ptr, a:Float):Ptr;
	static function idPtrFloat(self:Ptr, sel:Ptr, a:Ptr, b:Float):Ptr;
	static function idFloat4(self:Ptr, sel:Ptr, a:Float, b:Float, c:Float, d:Float):Ptr;
	static function idFloat3PtrPtr(self:Ptr, sel:Ptr, a:Float, b:Float, c:Float, d:Ptr, e:Ptr):Ptr;
	static function idRect(self:Ptr, sel:Ptr, r:CGRect):Ptr;
	static function idRectIntIntBool(self:Ptr, sel:Ptr, r:CGRect, a:Int64, b:Int64, c:Bool):Ptr;
	static function idIntPtrPtrBool(self:Ptr, sel:Ptr, a:Int64, b:Ptr, c:Ptr, d:Bool):Ptr;
	static function v(self:Ptr, sel:Ptr):Void;
	static function vPtr(self:Ptr, sel:Ptr, a:Ptr):Void;
	static function vInt(self:Ptr, sel:Ptr, a:Int64):Void;
	static function vBool(self:Ptr, sel:Ptr, a:Bool):Void;
	static function vFloat(self:Ptr, sel:Ptr, a:Float):Void;
	static function vRect(self:Ptr, sel:Ptr, r:CGRect):Void;
	static function vRectPtr(self:Ptr, sel:Ptr, r:CGRect, a:Ptr):Void;
	static function bPtrBool(self:Ptr, sel:Ptr, a:Ptr, b:Bool):Bool;
	static function bPtrPtr(self:Ptr, sel:Ptr, a:Ptr, b:Ptr):Bool;
	static function bPtrPointPtr(self:Ptr, sel:Ptr, a:Ptr, p:CGPoint, b:Ptr):Bool;
	static function vPtrPtrFloatPtr(self:Ptr, sel:Ptr, a:Ptr, b:Ptr, c:Float, d:Ptr):Void;
	static function i(self:Ptr, sel:Ptr):Int64;
	static function f(self:Ptr, sel:Ptr):Float;
	static function size(self:Ptr, sel:Ptr):CGSize;
	static function rect(self:Ptr, sel:Ptr):CGRect;
}
