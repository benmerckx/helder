package helder.ui.platform;

import helder.os.objc.CGPoint;
import hxmc.unsafe.*;

// The message shapes MacViews sends beside Msg's (helder.os.objc.Sender):
// named by the result (id, v: void, i: an integer, b: BOOL, f: a double,
// or a struct), then the arguments.
@:build(helder.os.objc.Sender.build())
class AkMsg {
	static function id(self:Ptr, sel:Ptr):Ptr;
	static function idPtrInt(self:Ptr, sel:Ptr, a:Ptr, b:Int64):Ptr;
	static function idFloat(self:Ptr, sel:Ptr, a:Float):Ptr;
	static function idPtrFloat(self:Ptr, sel:Ptr, a:Ptr, b:Float):Ptr;
	static function idFloat4(self:Ptr, sel:Ptr, a:Float, b:Float, c:Float, d:Float):Ptr;
	static function bPtrPtrPtr(self:Ptr, sel:Ptr, a:Ptr, b:Ptr, c:Ptr):Bool;
	static function bPtrPointPtr(self:Ptr, sel:Ptr, a:Ptr, p:CGPoint, b:Ptr):Bool;
	static function vPtrInt(self:Ptr, sel:Ptr, a:Ptr, b:Int64):Void;
}
