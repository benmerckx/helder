package hxmc.gfx.metal;

import hxmc.unsafe.*;

// Metal (the framework's one C function; the rest are messages, MtlMsg) and
// the structs its methods take by value.
@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/Metal.framework/Metal") extern class Metal {
	static function MTLCreateSystemDefaultDevice():Ptr;
}

class MTL {
	// MTLPixelFormat
	public static inline var PixelFormatBGRA8Unorm = 80;
	// MTLVertexFormat
	public static inline var VertexFormatUChar4Normalized = 9;
	public static inline var VertexFormatFloat = 28;
	public static inline var VertexFormatFloat2 = 29;
	public static inline var VertexFormatFloat3 = 30;
	public static inline var VertexFormatFloat4 = 31;
	// MTLPrimitiveType
	public static inline var PrimitiveTypePoint = 0;
	public static inline var PrimitiveTypeLine = 1;
	public static inline var PrimitiveTypeTriangle = 3;
	public static inline var PrimitiveTypeTriangleStrip = 4;
	// MTLCullMode, MTLWinding
	public static inline var CullModeNone = 0;
	public static inline var CullModeFront = 1;
	public static inline var CullModeBack = 2;
	public static inline var WindingCounterClockwise = 1;
	// MTLLoadAction, MTLStoreAction
	public static inline var LoadActionDontCare = 0;
	public static inline var LoadActionLoad = 1;
	public static inline var LoadActionClear = 2;
	public static inline var StoreActionStore = 1;
	// MTLResourceOptions, MTLStorageMode, MTLTextureUsage
	public static inline var ResourceStorageModeShared = 0;
	public static inline var StorageModePrivate = 2;
	public static inline var TextureUsageRenderTarget = 4;
	// MTLCommandBufferStatus
	public static inline var CommandBufferStatusError = 5;
}

@:hxmc.struct @:publicFields class MTLClearColor {
	var red:Float;
	var green:Float;
	var blue:Float;
	var alpha:Float;
}

@:hxmc.struct @:publicFields class MTLViewport {
	var originX:Float;
	var originY:Float;
	var width:Float;
	var height:Float;
	var znear:Float;
	var zfar:Float;
}

@:hxmc.struct @:publicFields class MTLOrigin {
	var x:Int64;
	var y:Int64;
	var z:Int64;
}

@:hxmc.struct @:publicFields class MTLSize {
	var width:Int64;
	var height:Int64;
	var depth:Int64;
}
