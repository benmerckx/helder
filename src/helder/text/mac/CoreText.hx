package helder.text.mac;

import hxmc.unsafe.*;
import helder.text.Shaping;
import helder.os.objc.ObjC;
import helder.os.objc.Msg;
import helder.os.objc.CGRect;
import helder.os.objc.CGPoint;

// macOS's text stack behind helder.text, Core Text through the Core
// Foundation and Objective-C interop: a family's faces matched by a
// CTFontDescriptor (its family name; the face closest to the weight and
// style among CTFontDescriptorCreateMatchingFontDescriptors's), a
// character's fallback from CTFontCopyDefaultCascadeListForLanguages (the
// language's cascade of the system font), else CTFontCreateForString; a
// run shaped as a CTLine of an attributed string in the face (its CTRuns'
// glyphs, advances, positions and string indices, at the face's units
// per em: font units; a run Core Text gave another font is not taken); a
// glyph drawn by CTFontDrawGlyphs into an alpha-only CGBitmapContext
// (anti-aliased, not smoothed: grayscale coverage). Faces are made from
// their files (CTFontManagerCreateFontDescriptorsFromURL, the face's
// index), else from their bytes (...FromData), once each.
class CoreText implements TextBackend {
	public static function create():Null<TextBackend>
		return new CoreText();

	// (per face: the CTFont at its units per em; per face and size, for rasters)
	final fonts = new Map<Int, Ptr>();
	final sized = new Map<String, Ptr>();
	var system = Ptr.nil();
	var buf:Ptr<UInt8> = Ptr.nil();
	var bufSize = 0;

	function new() {}

	public function blend():Null<GlyphBlend>
		return null;

	public function name():String
		return "Core Text";

	function room(n:Int):Ptr<UInt8> {
		if (n > bufSize) {
			if (!buf.isNull()) LibC.free(cast buf);
			bufSize = n * 2;
			buf = LibC.malloc((bufSize : hxmc.I64));
		}
		return buf;
	}

	// (a CFString constant the framework exports)
	static inline function constant(name:String):Ptr {
		var p:Ptr<Ptr> = cast Posix.dlsym(Ptr.ofI64(-2), Mem.cstr(name));
		return p.isNull() ? Ptr.nil() : p.value;
	}

	// (the face's descriptor: from its file, else its bytes; the face's index of a collection's)
	function descriptorOf(f:FontFile):Ptr {
		var arr = Ptr.nil();
		if (f.path != null) {
			var s = ObjC.str(f.path);
			var url = Msg.idPtr(ObjC.cls("NSURL"), ObjC.sel("fileURLWithPath:"), s);
			ObjC.release(s);
			arr = CT.CTFontManagerCreateFontDescriptorsFromURL(url);
		} else {
			var data = Arena.scopedValue(a -> Msg.idPtrInt(ObjC.cls("NSData"), ObjC.sel("dataWithBytes:length:"), cast a.copyBytes(f.data), f.data.length));
			arr = CT.CTFontManagerCreateFontDescriptorsFromData(data);
		}
		if (arr.isNull()) return Ptr.nil();
		var n = CF.CFArrayGetCount(arr).toInt(), k = f.faceIndex < n ? f.faceIndex : 0;
		var d = n > 0 ? CF.CFRetain(CF.CFArrayGetValueAtIndex(arr, (k : hxmc.I64))) : Ptr.nil();
		CF.CFRelease(arr);
		return d;
	}

	function fontOf(f:FontFile, size:Float):Ptr {
		var key = f.id + "@" + size;
		var h = sized.get(key);
		if (h != null) return h;
		var d = descriptorOf(f), font = Ptr.nil();
		if (!d.isNull()) {
			font = CT.CTFontCreateWithFontDescriptor(d, size, Ptr.nil());
			CF.CFRelease(d);
		}
		sized.set(key, font);
		return font;
	}

	public function shape(f:FontFile, text:String, start:Int, end:Int, rtl:Bool, out:ShapedGlyphs):Bool {
		var font = fontOf(f, f.unitsPerEm);
		if (font.isNull()) return false;
		var pool = helder.os.objc.Runtime.objc_autoreleasePoolPush();
		var n = end - start, units:Ptr<UInt16> = cast room(2 * n + 2);
		for (i in 0...n)
			units[i] = StringTools.fastCodeAt(text, start + i);
		var str = CF.CFStringCreateWithCharacters(Ptr.nil(), cast units, (n : hxmc.I64));
		var attrs = Msg.idPtrPtr(ObjC.cls("NSDictionary"), ObjC.sel("dictionaryWithObject:forKey:"), font, constant("kCTFontAttributeName"));
		var astr = CF.CFAttributedStringCreate(Ptr.nil(), str, attrs);
		var line = CT.CTLineCreateWithAttributedString(astr);
		var runs = CT.CTLineGetGlyphRuns(line), ok = true;
		var count = CF.CFArrayGetCount(runs).toInt(), total = 0;
		for (r in 0...count)
			total += CT.CTRunGetGlyphCount(CF.CFArrayGetValueAtIndex(runs, (r : hxmc.I64))).toInt();
		out.reset(total);
		var fontKey = constant("kCTFontAttributeName");
		for (r in 0...count) {
			var run = CF.CFArrayGetValueAtIndex(runs, (r : hxmc.I64)), g = CT.CTRunGetGlyphCount(run).toInt();
			// (Core Text's own fallback for a character the face lacks: not this face's glyphs)
			var used = Msg.idPtr(CT.CTRunGetAttributes(run), ObjC.sel("objectForKey:"), fontKey);
			if (used.isNull() || !CF.CFEqual(used, font)) {
				ok = false;
				break;
			}
			var range:Ptr<CFRange> = cast room(2 * n + 2 + 16 * g + 8 * g + 2 * g + 8 * g + 64).add((2 * n + 9) & ~7);
			range.value.location = 0;
			range.value.length = g;
			var glyphs:Ptr<UInt16> = cast range.add(16), positions:Ptr<Float> = cast range.add(16 + ((2 * g + 7) & ~7));
			var advances:Ptr<Float> = cast positions.add(16 * g), indices:Ptr<hxmc.unsafe.Int64> = cast advances.add(16 * g);
			CT.CTRunGetGlyphs(run, range.value, cast glyphs);
			CT.CTRunGetPositions(run, range.value, cast positions);
			CT.CTRunGetAdvances(run, range.value, cast advances);
			CT.CTRunGetStringIndices(run, range.value, cast indices);
			// (each glyph's offset: its position less the pen, the advances before it)
			var pen = positions[0];
			for (k in 0...g) {
				var x = positions[2 * k], y = positions[2 * k + 1];
				out.push(glyphs[k], start + indices[k].toInt(), advances[2 * k], x - pen, y);
				pen += advances[2 * k];
			}
		}
		CF.CFRelease(line);
		CF.CFRelease(astr);
		CF.CFRelease(str);
		helder.os.objc.Runtime.objc_autoreleasePoolPop(pool);
		return ok && out.count > 0;
	}

	public function rasterize(f:FontFile, glyph:Int, size:Float, dx:Float, out:GlyphBitmap):Bool {
		var font = fontOf(f, size);
		if (font.isNull()) return false;
		var p = room(64), id:Ptr<UInt16> = cast p, rect:Ptr<CGRect> = cast p.add(8), at:Ptr<CGPoint> = cast p.add(40);
		id[0] = glyph;
		// (kCTFontOrientationDefault)
		var b = CT.CTFontGetBoundingRectsForGlyphs(font, 0, cast id, cast rect, 1);
		var r = rect.value;
		if (r.size.width <= 0 || r.size.height <= 0) {
			out.size(0, 0);
			out.left = out.top = 0;
			return true;
		}
		var x0 = Math.floor(r.origin.x + dx) - 1, x1 = Math.ceil(r.origin.x + r.size.width + dx) + 1;
		var y0 = Math.floor(r.origin.y) - 1, y1 = Math.ceil(r.origin.y + r.size.height) + 1;
		var w = x1 - x0, h = y1 - y0;
		var px = LibC.malloc((w * h : hxmc.I64));
		LibC.memset(px, 0, (w * h : hxmc.I64));
		// (8 bits of alpha a pixel: kCGImageAlphaOnly)
		var ctx = CG.CGBitmapContextCreate(px, w, h, 8, w, Ptr.nil(), 7);
		if (ctx.isNull()) {
			LibC.free(px);
			return false;
		}
		CG.CGContextSetShouldAntialias(ctx, true);
		CG.CGContextSetShouldSmoothFonts(ctx, false);
		CG.CGContextSetAllowsFontSubpixelPositioning(ctx, true);
		CG.CGContextSetShouldSubpixelPositionFonts(ctx, true);
		CG.CGContextSetGrayFillColor(ctx, 1, 1);
		// (the origin dx right of the bitmap's -x0, y0 below its bottom: y up)
		var pid = room(64);
		var q:Ptr<UInt16> = cast pid, pos:Ptr<CGPoint> = cast pid.add(8);
		q[0] = glyph;
		pos.value.x = dx - x0;
		pos.value.y = -y0;
		CT.CTFontDrawGlyphs(font, cast q, cast pos, 1, ctx);
		CG.CGContextFlush(ctx);
		out.size(w, h);
		// (a bitmap context's first row its top)
		BytesPtr.copyIn(out.pixels, 0, px, w * h);
		out.left = x0;
		out.top = -y1;
		CF.CFRelease(ctx);
		LibC.free(px);
		return true;
	}

	// glyphs drawn by Core Text into an opaque sRGB bitmap of w x h device
	// pixels, as macOS draws a window's text: CTFontDrawGlyphs, antialiased,
	// subpixel positioned and quantised, font smoothing on or off, fg on bg
	// (0xRRGGBB, sRGB). Each run: a font file's face, its size in points and
	// its glyphs at their pens (x and the baseline's y in device pixels, y
	// down, not quantised: Core Text quantises them); scale: device pixels a
	// point. The bitmap's green channel, rows top down: the text-quality
	// lane's references (tests/text/TextQuality.hx)
	public static function sheet(w:Int, h:Int, scale:Float, bg:Int, fg:Int, smooth:Bool, runs:Array<SheetRun>):haxe.io.Bytes {
		var pool = helder.os.objc.Runtime.objc_autoreleasePoolPush();
		var n = w * h * 4, px = LibC.malloc((n : hxmc.I64));
		LibC.memset(px, 0, (n : hxmc.I64));
		var space = CG.CGColorSpaceCreateWithName(srgb());
		// (kCGImageAlphaPremultipliedLast: R G B A)
		var ctx = CG.CGBitmapContextCreate(px, w, h, 8, w * 4, space, 1);
		inline function channel(c:Int, k:Int):Float
			return ((c >> k) & 255) / 255;
		var back = CG.CGColorCreateSRGB(channel(bg, 16), channel(bg, 8), channel(bg, 0), 1);
		CG.CGContextSetFillColorWithColor(ctx, back);
		var rect:Ptr<CGRect> = cast LibC.malloc(32);
		rect.value.origin.x = 0;
		rect.value.origin.y = 0;
		rect.value.size.width = w;
		rect.value.size.height = h;
		CG.CGContextFillRect(ctx, rect.value);
		LibC.free(cast rect);
		// (points: y up from the bottom, as the context's own)
		CG.CGContextScaleCTM(ctx, scale, scale);
		CG.CGContextSetAllowsAntialiasing(ctx, true);
		CG.CGContextSetShouldAntialias(ctx, true);
		CG.CGContextSetAllowsFontSmoothing(ctx, smooth);
		CG.CGContextSetShouldSmoothFonts(ctx, smooth);
		CG.CGContextSetAllowsFontSubpixelPositioning(ctx, true);
		CG.CGContextSetShouldSubpixelPositionFonts(ctx, true);
		CG.CGContextSetAllowsFontSubpixelQuantization(ctx, true);
		CG.CGContextSetShouldSubpixelQuantizeFonts(ctx, true);
		var ink = CG.CGColorCreateSRGB(channel(fg, 16), channel(fg, 8), channel(fg, 0), 1);
		CG.CGContextSetFillColorWithColor(ctx, ink);
		for (r in runs) {
			var s = ObjC.str(r.path);
			var url = Msg.idPtr(ObjC.cls("NSURL"), ObjC.sel("fileURLWithPath:"), s);
			ObjC.release(s);
			var arr = CT.CTFontManagerCreateFontDescriptorsFromURL(url);
			if (arr.isNull() || CF.CFArrayGetCount(arr).toInt() <= r.face) throw "CoreText.sheet: no such face in " + r.path;
			var font = CT.CTFontCreateWithFontDescriptor(CF.CFArrayGetValueAtIndex(arr, (r.face : hxmc.I64)), r.size, Ptr.nil());
			CF.CFRelease(arr);
			var k = r.ids.length;
			var ids:Ptr<UInt16> = cast LibC.malloc((2 * k + 8 : hxmc.I64)), at:Ptr<CGPoint> = cast LibC.malloc((16 * k + 16 : hxmc.I64));
			for (i in 0...k) {
				ids[i] = r.ids[i];
				var p:Ptr<CGPoint> = cast at.add(16 * i);
				p.value.x = r.xs[i] / scale;
				p.value.y = (h - r.ys[i]) / scale;
			}
			CT.CTFontDrawGlyphs(font, cast ids, cast at, k, ctx);
			LibC.free(cast ids);
			LibC.free(cast at);
			CF.CFRelease(font);
		}
		CG.CGContextFlush(ctx);
		var rgba = haxe.io.Bytes.alloc(n);
		BytesPtr.copyIn(rgba, 0, px, n);
		var green = haxe.io.Bytes.alloc(w * h);
		for (i in 0...w * h)
			green.set(i, rgba.get(4 * i + 1));
		CF.CFRelease(ctx);
		CF.CFRelease(space);
		CF.CFRelease(back);
		CF.CFRelease(ink);
		LibC.free(px);
		helder.os.objc.Runtime.objc_autoreleasePoolPop(pool);
		return green;
	}

	// (kCGColorSpaceSRGB: a CFStringRef the framework exports)
	static inline function srgb():Ptr {
		var p:Ptr<Ptr> = cast Posix.dlsym(Ptr.ofI64(-2), Mem.cstr("kCGColorSpaceSRGB"));
		return p.isNull() ? Ptr.nil() : p.value;
	}

	// (a font's file and the face in it: by its family and style among the file's faces)
	function fileOf(font:Ptr, cp:Int):Null<{path:String, index:Int}> {
		var url = CT.CTFontCopyAttribute(font, constant("kCTFontURLAttribute"));
		if (url.isNull()) return null;
		var p = room(4096);
		var ok = CF.CFURLGetFileSystemRepresentation(url, true, cast p, 4096);
		CF.CFRelease(url);
		if (!ok) return null;
		var path = (cast p : CString).toString();
		var family = ObjC.string(CT.CTFontCopyFamilyName(font)), style = ObjC.string(CT.CTFontCopyName(font, constant("kCTFontStyleNameKey")));
		var faces = helder.text.SystemFonts.FaceInfo.read(path), index = -1;
		for (fi in faces)
			if (index < 0 && fi.family == family && (style == null || fi.subfamily == style)) index = fi.index;
		if (index < 0) for (fi in faces)
			if (index < 0 && fi.family == family) index = fi.index;
		return {path: path, index: faces.length <= 1 ? 0 : index};
	}

	public function fallback(cp:Int, ?lang:String):Null<{path:String, index:Int}> {
		var pool = helder.os.objc.Runtime.objc_autoreleasePoolPush();
		if (system.isNull()) system = CT.CTFontCreateUIFontForLanguage(2, 13, Ptr.nil()); // (kCTFontUIFontSystem)
		var units:Ptr<UInt16> = cast room(16), n = 1;
		if (cp >= 0x10000) {
			units[0] = 0xD800 + ((cp - 0x10000) >> 10);
			units[1] = 0xDC00 + ((cp - 0x10000) & 0x3FF);
			n = 2;
		} else units[0] = cp;
		var glyphs:Ptr<UInt16> = cast units.add(8);
		var result:Null<{path:String, index:Int}> = null;
		// (the language's cascade of the system font, then Core Text's own pick for the string)
		var langs = lang == null ? Ptr.nil() : Msg.idPtr(ObjC.cls("NSArray"), ObjC.sel("arrayWithObject:"), ObjC.str(lang));
		var cascade = CT.CTFontCopyDefaultCascadeListForLanguages(system, langs);
		if (!cascade.isNull()) {
			var k = CF.CFArrayGetCount(cascade).toInt();
			for (i in 0...k) {
				if (result != null) break;
				var f = CT.CTFontCreateWithFontDescriptor(CF.CFArrayGetValueAtIndex(cascade, (i : hxmc.I64)), 13, Ptr.nil());
				if (f.isNull()) continue;
				if (CT.CTFontGetGlyphsForCharacters(f, cast units, cast glyphs, n)) result = fileOf(f, cp);
				CF.CFRelease(f);
			}
			CF.CFRelease(cascade);
		}
		if (result == null) {
			var str = CF.CFStringCreateWithCharacters(Ptr.nil(), cast units, (n : hxmc.I64));
			var range:Ptr<CFRange> = cast room(64).add(32);
			range.value.location = 0;
			range.value.length = n;
			var f = CT.CTFontCreateForString(system, str, range.value);
			CF.CFRelease(str);
			if (!f.isNull()) {
				if (CT.CTFontGetGlyphsForCharacters(f, cast units, cast glyphs, n)) result = fileOf(f, cp);
				CF.CFRelease(f);
			}
		}
		helder.os.objc.Runtime.objc_autoreleasePoolPop(pool);
		return result;
	}

	public function find(family:String, weight:Int, italic:Bool):Null<{path:String, index:Int}> {
		var pool = helder.os.objc.Runtime.objc_autoreleasePoolPush();
		var name = ObjC.str(family);
		var attrs = Msg.idPtrPtr(ObjC.cls("NSDictionary"), ObjC.sel("dictionaryWithObject:forKey:"), name, constant("kCTFontFamilyNameAttribute"));
		var desc = CT.CTFontDescriptorCreateWithAttributes(attrs);
		ObjC.release(name);
		var all = desc.isNull() ? Ptr.nil() : CT.CTFontDescriptorCreateMatchingFontDescriptors(desc, Ptr.nil());
		if (!desc.isNull()) CF.CFRelease(desc);
		var best:Null<{path:String, index:Int}> = null, score = 1 << 30;
		if (!all.isNull()) {
			for (i in 0...CF.CFArrayGetCount(all).toInt()) {
				var f = CT.CTFontCreateWithFontDescriptor(CF.CFArrayGetValueAtIndex(all, (i : hxmc.I64)), 13, Ptr.nil());
				if (f.isNull()) continue;
				var m = fileOf(f, -1);
				CF.CFRelease(f);
				if (m == null) continue;
				for (fi in helder.text.SystemFonts.FaceInfo.read(m.path))
					if (fi.index == (m.index < 0 ? 0 : m.index) && fi.family.toLowerCase() == family.toLowerCase()) {
						var s = (fi.italic == italic ? 0 : 10000) + Std.int(Math.abs(fi.weight - weight));
						if (s < score) {
							score = s;
							best = {path: m.path, index: fi.index};
						}
					}
			}
			CF.CFRelease(all);
		}
		helder.os.objc.Runtime.objc_autoreleasePoolPop(pool);
		return best;
	}
}

@:hxmc.struct @:publicFields class CFRange {
	var location:hxmc.unsafe.Int64;
	var length:hxmc.unsafe.Int64;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreText.framework/CoreText") extern class CT {
	static function CTFontManagerCreateFontDescriptorsFromURL(url:Ptr):Ptr;
	static function CTFontManagerCreateFontDescriptorsFromData(data:Ptr):Ptr;
	static function CTFontCreateWithFontDescriptor(desc:Ptr, size:Float, matrix:Ptr):Ptr;
	static function CTFontCreateUIFontForLanguage(type:Int, size:Float, lang:Ptr):Ptr;
	static function CTFontCopyDefaultCascadeListForLanguages(font:Ptr, langs:Ptr):Ptr;
	static function CTFontCreateForString(font:Ptr, str:Ptr, range:CFRange):Ptr;
	static function CTFontGetGlyphsForCharacters(font:Ptr, chars:Ptr, glyphs:Ptr, n:hxmc.I64):Bool;
	static function CTFontCopyAttribute(font:Ptr, key:Ptr):Ptr;
	static function CTFontCopyFamilyName(font:Ptr):Ptr;
	static function CTFontCopyName(font:Ptr, key:Ptr):Ptr;
	static function CTFontGetBoundingRectsForGlyphs(font:Ptr, orientation:Int, glyphs:Ptr, rects:Ptr, n:hxmc.I64):CGRect;
	static function CTFontDrawGlyphs(font:Ptr, glyphs:Ptr, positions:Ptr, n:hxmc.I64, ctx:Ptr):Void;
	static function CTFontDescriptorCreateWithAttributes(attrs:Ptr):Ptr;
	static function CTFontDescriptorCreateMatchingFontDescriptors(desc:Ptr, mandatory:Ptr):Ptr;
	static function CTLineCreateWithAttributedString(s:Ptr):Ptr;
	static function CTLineGetGlyphRuns(line:Ptr):Ptr;
	static function CTRunGetGlyphCount(run:Ptr):hxmc.I64;
	static function CTRunGetAttributes(run:Ptr):Ptr;
	static function CTRunGetGlyphs(run:Ptr, range:CFRange, out:Ptr):Void;
	static function CTRunGetPositions(run:Ptr, range:CFRange, out:Ptr):Void;
	static function CTRunGetAdvances(run:Ptr, range:CFRange, out:Ptr):Void;
	static function CTRunGetStringIndices(run:Ptr, range:CFRange, out:Ptr):Void;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation") extern class CF {
	static function CFRelease(o:Ptr):Void;
	static function CFRetain(o:Ptr):Ptr;
	static function CFEqual(a:Ptr, b:Ptr):Bool;
	static function CFArrayGetCount(a:Ptr):hxmc.I64;
	static function CFArrayGetValueAtIndex(a:Ptr, i:hxmc.I64):Ptr;
	static function CFStringCreateWithCharacters(alloc:Ptr, chars:Ptr, n:hxmc.I64):Ptr;
	static function CFAttributedStringCreate(alloc:Ptr, str:Ptr, attrs:Ptr):Ptr;
	static function CFURLGetFileSystemRepresentation(url:Ptr, resolve:Bool, buf:Ptr, max:hxmc.I64):Bool;
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics") extern class CG {
	static function CGBitmapContextCreate(data:Ptr, w:hxmc.I64, h:hxmc.I64, bits:hxmc.I64, stride:hxmc.I64, space:Ptr, info:Int):Ptr;
	static function CGContextSetShouldAntialias(ctx:Ptr, v:Bool):Void;
	static function CGContextSetShouldSmoothFonts(ctx:Ptr, v:Bool):Void;
	static function CGContextSetAllowsFontSubpixelPositioning(ctx:Ptr, v:Bool):Void;
	static function CGContextSetShouldSubpixelPositionFonts(ctx:Ptr, v:Bool):Void;
	static function CGContextSetGrayFillColor(ctx:Ptr, gray:Float, alpha:Float):Void;
	static function CGContextFlush(ctx:Ptr):Void;
	// (the text-quality lane's references: CoreText.sheet)
	static function CGColorSpaceCreateWithName(name:Ptr):Ptr;
	static function CGColorCreateSRGB(r:Float, g:Float, b:Float, a:Float):Ptr;
	static function CGContextSetFillColorWithColor(ctx:Ptr, color:Ptr):Void;
	static function CGContextFillRect(ctx:Ptr, rect:CGRect):Void;
	static function CGContextScaleCTM(ctx:Ptr, sx:Float, sy:Float):Void;
	static function CGContextSetAllowsAntialiasing(ctx:Ptr, v:Bool):Void;
	static function CGContextSetAllowsFontSmoothing(ctx:Ptr, v:Bool):Void;
	static function CGContextSetAllowsFontSubpixelQuantization(ctx:Ptr, v:Bool):Void;
	static function CGContextSetShouldSubpixelQuantizeFonts(ctx:Ptr, v:Bool):Void;
}

// a run of glyphs CoreText.sheet draws: a font file's face at a size
// (points), each glyph's id and pen (device pixels, y down)
typedef SheetRun = {path:String, face:Int, size:Float, ids:Array<Int>, xs:Array<Float>, ys:Array<Float>};
