package hxmc.gfx.metal;

import hxmc.gfx.metal.Metal;
import hxmc.unsafe.*;

// Metal's shapes of objc_msgSend (hxmc.os.objc.Sender; the names as in
// hxmc.os.objc.Msg), the ones with Metal's structs
@:build(hxmc.os.objc.Sender.build())
class MtlMsg {
	static function vClear(self:Ptr, sel:Ptr, c:MTLClearColor):Void;
	static function vViewport(self:Ptr, sel:Ptr, v:MTLViewport):Void;
	static function vPtrIntInt(self:Ptr, sel:Ptr, a:Ptr, b:Int64, c:Int64):Void;
	static function vIntIntIntInt(self:Ptr, sel:Ptr, a:Int64, b:Int64, c:Int64, d:Int64):Void;
	static function vCopy(self:Ptr, sel:Ptr, texture:Ptr, slice:Int64, level:Int64, origin:MTLOrigin, size:MTLSize, buffer:Ptr, offset:Int64,
		bytesPerRow:Int64, bytesPerImage:Int64):Void;
}
