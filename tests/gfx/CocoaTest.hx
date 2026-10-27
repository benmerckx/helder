import haxe.io.Bytes;
import helder.os.Window;
import helder.os.objc.*;
import hxmc.unsafe.*;

// GfxTest's window mode on macOS: the close button pressed (performClose:,
// which asks the window's delegate), a key down posted (its character), and the window's pixels as the window
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

	// a key down of a (its key code 0), posted to the application's queue
	public static function input(w:Window) {
		var window = Msg.id(w.surface.handle, ObjC.sel("window"));
		var a = ObjC.str("a");
		var ev = Arena.scopedValue(m -> {
			var p = m.make(CGPoint);
			p.value.x = 10;
			p.value.y = 10;
			TestMsg.keyEvent(ObjC.cls("NSEvent"), ObjC.sel("keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:"),
				10, p.value, 0, 0, Msg.i(window, ObjC.sel("windowNumber")), Ptr.nil(), a, a, false, 0);
		});
		TestMsg.vPtrBool(Msg.id(ObjC.cls("NSApplication"), ObjC.sel("sharedApplication")), ObjC.sel("postEvent:atStart:"), ev, false);
		ObjC.release(a);
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

// the messages CocoaTest sends (helder.os.objc.Sender)
@:build(helder.os.objc.Sender.build())
class TestMsg {
	static function keyEvent(self:Ptr, sel:Ptr, type:Int64, location:CGPoint, flags:Int64, time:Float, window:Int64, context:Ptr, chars:Ptr, raw:Ptr,
		repeat:Bool, code:Int64):Ptr;
	static function vPtrBool(self:Ptr, sel:Ptr, a:Ptr, b:Bool):Void;
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
