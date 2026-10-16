import haxe.io.Bytes;
import hxmc.os.Window;
import hxmc.os.objc.*;
import hxmc.unsafe.*;

// GfxTest's window mode on macOS: the close button pressed (performClose:,
// which asks the window's delegate), and the window's pixels as the window
// server composited them (CGWindowListCreateImage: no permission needed for
// the process's own windows). The layer is tagged with the screen's colour
// space, so that the window server shows the GPU's values unconverted (as
// X11 does), and they come back as rendered.
class CocoaTest {
	public static function prepare(w:Window) {
		var screen = Msg.id(Msg.id(w.surface.handle, ObjC.sel("window")), ObjC.sel("screen"));
		var space = Msg.id(Msg.id(screen, ObjC.sel("colorSpace")), ObjC.sel("CGColorSpace"));
		Msg.vPtr(w.surface.display, ObjC.sel("setColorspace:"), space);
	}

	public static function close(w:Window) {
		var window = Msg.id(w.surface.handle, ObjC.sel("window"));
		Msg.vPtr(window, ObjC.sel("performClose:"), Ptr.nil());
	}

	// the content's pixels as RGBA, rows top to bottom; alpha below 255 where
	// the window server shows none of it (the rounded corners). null: no capture
	public static function capture(w:Window, width:Int, height:Int):Null<Bytes> {
		var window = Msg.id(w.surface.handle, ObjC.sel("window"));
		var id = Msg.i(window, ObjC.sel("windowNumber")).toInt();
		var img = Arena.scopedValue(a -> {
			// (CGRectNull: the window's own bounds)
			var r = a.make(CGRect);
			r.value.origin.x = Math.POSITIVE_INFINITY;
			r.value.origin.y = Math.POSITIVE_INFINITY;
			CG.CGWindowListCreateImage(r.value, 8, id, 1 | 8); // that window; no shadow, its pixels
		});
		if (img.isNull()) return null;
		var iw = CG.CGImageGetWidth(img).toInt(), ih = CG.CGImageGetHeight(img).toInt();
		var bpr = CG.CGImageGetBytesPerRow(img).toInt(), info = CG.CGImageGetBitmapInfo(img);
		if (iw != width || ih < height || CG.CGImageGetBitsPerPixel(img).toInt() != 32 || info & 0x7000 != 0x2000) {
			Sys.println('GfxTest: a ${iw}x${ih} capture, bitmap info 0x' + StringTools.hex(info));
			CG.CGImageRelease(img);
			return null;
		}
		var data = CG.CGDataProviderCopyData(CG.CGImageGetDataProvider(img));
		var px:Ptr<UInt8> = CF.CFDataGetBytePtr(data);
		// (32 bits, little endian: B, G, R, A; the title bar above the content)
		var rgba = Bytes.alloc(width * height * 4);
		for (y in 0...height) {
			var row = px.add((ih - height + y) * bpr);
			for (x in 0...width) {
				var q = 4 * (y * width + x);
				rgba.set(q, row[4 * x + 2]);
				rgba.set(q + 1, row[4 * x + 1]);
				rgba.set(q + 2, row[4 * x]);
				rgba.set(q + 3, row[4 * x + 3]);
			}
		}
		CF.CFRelease(data);
		CG.CGImageRelease(img);
		return rgba;
	}
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics") extern class CG {
	static function CGWindowListCreateImage(bounds:CGRect, listOption:Int, window:Int, imageOption:Int):Ptr;
	static function CGImageGetWidth(img:Ptr):Int64;
	static function CGImageGetHeight(img:Ptr):Int64;
	static function CGImageGetBytesPerRow(img:Ptr):Int64;
	static function CGImageGetBitsPerPixel(img:Ptr):Int64;
	static function CGImageGetBitmapInfo(img:Ptr):Int;
	static function CGImageGetDataProvider(img:Ptr):Ptr;
	static function CGDataProviderCopyData(provider:Ptr):Ptr;
	static function CGImageRelease(img:Ptr):Void;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation") extern class CF {
	static function CFDataGetBytePtr(data:Ptr):Ptr;
	static function CFRelease(o:Ptr):Void;
}
