package helder.ui.platform;

import hxmc.unsafe.*;

// The message shapes AppleWebView sends beside Msg's (helder.os.objc.Sender):
// named by the result (id, v: void, b: BOOL), then the arguments.
@:build(helder.os.objc.Sender.build())
class WkMsg {
	static function idPtrIntBool(self:Ptr, sel:Ptr, a:Ptr, b:Int64, c:Bool):Ptr;
	static function idPtrIntPtrPtr(self:Ptr, sel:Ptr, a:Ptr, b:Int64, c:Ptr, d:Ptr):Ptr;
	static function idRectPtr(self:Ptr, sel:Ptr, r:helder.os.objc.CGRect, a:Ptr):Ptr;
	static function vPtrPtrIntPtr(self:Ptr, sel:Ptr, a:Ptr, b:Ptr, c:Int64, d:Ptr):Void;
	static function idFloat4(self:Ptr, sel:Ptr, a:Float, b:Float, c:Float, d:Float):Ptr;
	static function f(self:Ptr, sel:Ptr):Float;
}

// The Objective-C runtime's protocols, and blocks (a completion handler:
// a global block, its invoke a callback; Block_copy leaves it as it is)
@:hxmc.c @:hxmc.lib("/usr/lib/libobjc.A.dylib") extern class ObjcProtocols {
	static function objc_getProtocol(name:Ptr):Ptr;
	static function class_addProtocol(cls:Ptr, protocol:Ptr):Bool;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics") extern class WkCG {
	static function CGImageGetWidth(img:Ptr):Int64;
	static function CGImageGetHeight(img:Ptr):Int64;
	static function CGColorSpaceCreateDeviceRGB():Ptr;
	static function CGColorSpaceRelease(space:Ptr):Void;
	static function CGBitmapContextCreate(data:Ptr, w:Int64, h:Int64, bits:Int64, stride:Int64, space:Ptr, info:Int):Ptr;
	static function CGContextDrawImage(ctx:Ptr, rect:helder.os.objc.CGRect, img:Ptr):Void;
	static function CGContextRelease(ctx:Ptr):Void;
}
