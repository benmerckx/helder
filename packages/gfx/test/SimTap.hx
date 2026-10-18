import hxmc.os.objc.CGPoint;
import hxmc.unsafe.*;

// A tap on the iOS simulator's screen for ios.sh (macOS, a GUI session):
// the largest on-screen window of the Simulator app (CGWindowList), a left
// click (down, up) at a fraction of it posted as the HID system's events
// (CGEventPost), which the simulator turns into a touch. Needs the
// permission to post events (the runner's).
//   SimTap [fx fy]   (default 0.5 0.55: the screen's middle, under the title bar)
class SimTap {
	static function main() {
		var args = Sys.args();
		var fx = args.length > 1 ? Std.parseFloat(args[0]) : 0.5, fy = args.length > 1 ? Std.parseFloat(args[1]) : 0.55;
		var list = CG.CGWindowListCopyWindowInfo(1, 0); // (kCGWindowListOptionOnScreenOnly)
		var ownerKey = cf("kCGWindowOwnerName"), boundsKey = cf("kCGWindowBounds");
		var rect:Ptr<Float> = LibC.malloc(32);
		var name:Ptr<UInt8> = LibC.malloc(256);
		var best = -1.0, bx = 0.0, by = 0.0, bw = 0.0, bh = 0.0;
		for (i in 0...CF.CFArrayGetCount(list).toInt()) {
			var d = CF.CFArrayGetValueAtIndex(list, i);
			var owner = CF.CFDictionaryGetValue(d, ownerKey), bounds = CF.CFDictionaryGetValue(d, boundsKey);
			if (owner.isNull() || bounds.isNull()) continue;
			if (CF.CFStringGetCString(owner, name, 256, 0x08000100) & 0xff == 0 || (name : CString).toString() != "Simulator") continue;
			if (CG.CGRectMakeWithDictionaryRepresentation(bounds, rect) & 0xff == 0) continue;
			var w = Mem.getF64(rect, 16), h = Mem.getF64(rect, 24);
			if (w * h > best) {
				best = w * h;
				bx = Mem.getF64(rect, 0);
				by = Mem.getF64(rect, 8);
				bw = w;
				bh = h;
			}
		}
		if (best < 0) {
			Sys.println("SimTap: no Simulator window on screen");
			Sys.exit(1);
		}
		var p:Ptr<CGPoint> = LibC.malloc(16);
		p.value.x = bx + bw * fx;
		p.value.y = by + bh * fy;
		Sys.println('SimTap: the Simulator window at $bx,$by ${bw}x$bh: a click at ${p.value.x},${p.value.y}');
		// (mouse moved, left down, left up)
		for (type in [5, 1, 2]) {
			var ev = CG.CGEventCreateMouseEvent(Ptr.nil(), type, p.value, 0);
			CG.CGEventPost(0, ev); // (kCGHIDEventTap)
			CF.CFRelease(ev);
			Sys.sleep(0.1);
		}
	}

	static function cf(s:String):Ptr
		return Arena.scopedValue(a -> CF.CFStringCreateWithCString(Ptr.nil(), a.cstring(s), 0x08000100));
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics") extern class CG {
	static function CGWindowListCopyWindowInfo(option:Int, relativeTo:Int):Ptr;
	static function CGRectMakeWithDictionaryRepresentation(dict:Ptr, rect:Ptr):Int;
	static function CGEventCreateMouseEvent(source:Ptr, type:Int, p:CGPoint, button:Int):Ptr;
	static function CGEventPost(tap:Int, ev:Ptr):Void;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation") extern class CF {
	static function CFStringCreateWithCString(alloc:Ptr, s:Ptr, encoding:Int):Ptr;
	static function CFStringGetCString(s:Ptr, buf:Ptr, size:Int64, encoding:Int):Int;
	static function CFArrayGetCount(a:Ptr):Int64;
	static function CFArrayGetValueAtIndex(a:Ptr, i:Int64):Ptr;
	static function CFDictionaryGetValue(d:Ptr, key:Ptr):Ptr;
	static function CFRelease(o:Ptr):Void;
}
