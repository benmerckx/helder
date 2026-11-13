package helder.os;

import haxe.io.Bytes;
import helder.image.ImageError;
import helder.image.ImageLimits;
import hxmc.Platform;
import hxmc.unsafe.*;

// The system's own image decoders, for what helder.image does not read:
// Windows' WIC (COM: the factory's decoder from the file, its first frame
// converted to 32bppRGBA, its pixels copied, its EXIF orientation applied
// as its metadata query reader gives it), macOS's ImageIO (an image
// source from the file, its size from its properties, then a thumbnail of
// at most the side asked for with its EXIF orientation applied, drawn into
// an sRGB RGBA bitmap, unpremultiplied): TIFF, HEIC and HEIF, AVIF, the
// cameras' RAW files where the system has their codecs (Windows: its HEIF
// and AV1 extensions, its Raw Image Extension). Linux: libtiff, libheif,
// libavif and libraw where installed, each loaded at run time
// (helder.os.linux.LinuxImages; none: supports() false for its formats).
// ImageLimits is checked on the size the system reports, before any pixel
// is decoded. The rest: none. Pixels: RGBA8, straight alpha, upright.
@:hxmc.unsafe(gc)
class SystemImages {
	// the extensions it may read where there are system decoders
	public static final EXTENSIONS = ["tif", "tiff", "heic", "heif", "avif", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"];

	// (Linux's: a constant condition, so that no other target links its libraries' loaders)
	static inline function linux():Bool
		return Platform.apple() == 0 && Platform.os() == 0 && Platform.target() < 9;

	public static function available():Bool
		return Platform.apple() == 0 && (Platform.os() == 1 || Platform.os() == 2) || linux() && helder.os.linux.LinuxImages.any();

	public static function supports(path:String):Bool {
		var dot = path.lastIndexOf("."), ext = dot > 0 ? path.substr(dot + 1).toLowerCase() : "";
		if (!EXTENSIONS.contains(ext)) return false;
		return if (linux()) helder.os.linux.LinuxImages.supports(ext) else available();
	}

	// the file decoded (side > 0: at most that a side, where the system scales
	// as it decodes); an ImageError when it cannot be
	public static function decode(path:String, side = 0):{width:Int, height:Int, pixelsWidth:Int, pixelsHeight:Int, rgba:Bytes}
		return if (Platform.apple() != 0) throw ImageError.unsupported("SystemImages: none here") else if (Platform.os() == 2) wic(path) else if (Platform.os() == 1)
			imageIO(path, side) else if (linux()) linuxLibraries(path) else throw ImageError.unsupported("SystemImages: none on this system");

	// --- Linux: libtiff, libheif, libavif, libraw where they are (helder.os.linux.LinuxImages)

	static function linuxLibraries(path:String):{width:Int, height:Int, pixelsWidth:Int, pixelsHeight:Int, rgba:Bytes} {
		var ext = path.substr(path.lastIndexOf(".") + 1).toLowerCase();
		var d = helder.os.linux.LinuxImages.decode(path, ext);
		// (libtiff's RGBA premultiplied: straight, as the others')
		if (ext == "tif" || ext == "tiff") unpremultiply(d.rgba);
		return {width: d.width, height: d.height, pixelsWidth: d.width, pixelsHeight: d.height, rgba: d.rgba};
	}

	// --- Windows: WIC

	static var factory = Ptr.nil();
	static final CLSID_WICImagingFactory = helder.os.win32.Com.guid(0xCACAF262, 0x9370, 0x4615, [0xA1, 0x3B, 0x9F, 0x55, 0x39, 0xDA, 0x4C, 0x0A]);
	static final IID_IWICImagingFactory = helder.os.win32.Com.guid(0xEC5EC8A9, 0xC395, 0x4314, [0x9C, 0x77, 0x54, 0xD7, 0xA9, 0x35, 0xFF, 0x70]);
	static final RGBA = helder.os.win32.Com.guid(0xF5C7AD2D, 0x6A8D, 0x43DD, [0xA7, 0xA8, 0xA2, 0x99, 0x35, 0x26, 0x1A, 0xE9]);

	static function wic(path:String):{width:Int, height:Int, pixelsWidth:Int, pixelsHeight:Int, rgba:Bytes} {
		if (factory.isNull()) {
			helder.os.win32.FileOpenDialog.Shell32Com.CoInitializeEx(Ptr.nil(), 0); // (COINIT_MULTITHREADED: a decode's thread)
			var out:Ptr<Ptr> = LibC.malloc(8);
			out.value = Ptr.nil();
			helder.os.win32.FileOpenDialog.Shell32Com.CoCreateInstance(CLSID_WICImagingFactory, Ptr.nil(), 1, IID_IWICImagingFactory, out);
			factory = out.value;
			LibC.free(cast out);
			if (factory.isNull()) throw ImageError.unsupported("SystemImages: no WIC");
		}
		var held:Array<Ptr> = [];
		inline function one():Ptr<Ptr> {
			var p:Ptr<Ptr> = LibC.malloc(8);
			p.value = Ptr.nil();
			return p;
		}
		var out = one();
		function done() {
			for (h in held)
				helder.os.win32.Com.release(h);
			LibC.free(cast out);
		}
		// (GENERIC_READ, WICDecodeMetadataCacheOnDemand)
		var hr = Arena.scopedValue(a -> IWICImagingFactory.CreateDecoderFromFilename(factory, a.wstring(path), Ptr.nil(), 0x80000000, 0, out));
		if (hr < 0 || out.value.isNull()) {
			done();
			// (WINCODEC_ERR_COMPONENTNOTFOUND: no codec for it)
			throw hr == 0x88982F50 ? ImageError.unsupported("SystemImages: no codec on this system for " + path) : ImageError.corrupt("SystemImages: WIC cannot read it (0x" + StringTools.hex(hr, 8) + ")");
		}
		var decoder = out.value;
		held.push(decoder);
		out.value = Ptr.nil();
		if (IWICBitmapDecoder.GetFrame(decoder, 0, out) < 0 || out.value.isNull()) {
			done();
			throw ImageError.corrupt("SystemImages: no frame");
		}
		var frame = out.value;
		held.push(frame);
		var size:Ptr<Int32> = LibC.malloc(8);
		IWICBitmapSource.GetSize(frame, cast size, cast size.add(4));
		var w = size[0], h = size[1];
		LibC.free(cast size);
		try ImageLimits.check("SystemImages", w, h, 4) catch (e:ImageError) {
			done();
			throw e;
		}
		out.value = Ptr.nil();
		IWICImagingFactory.CreateFormatConverter(factory, out);
		var conv = out.value;
		if (conv.isNull()) {
			done();
			throw ImageError.unsupported("SystemImages: no converter");
		}
		held.push(conv);
		// (WICBitmapDitherTypeNone, WICBitmapPaletteTypeCustom)
		if (IWICFormatConverter.Initialize(conv, frame, RGBA, 0, Ptr.nil(), 0, 0) < 0) {
			done();
			throw ImageError.unsupported("SystemImages: not convertible to RGBA");
		}
		var o = orientation(frame);
		var n = w * h * 4, buf = LibC.malloc((n : hxmc.I64));
		var r = IWICBitmapSource.CopyPixels(conv, Ptr.nil(), w * 4, n, buf);
		var rgba = Bytes.alloc(n);
		if (r >= 0) BytesPtr.copyIn(rgba, 0, buf, n);
		LibC.free(buf);
		done();
		if (r < 0) throw ImageError.corrupt("SystemImages: WIC's pixels (0x" + StringTools.hex(r, 8) + ")");
		// (upright, as ImageIO's: EXIF's orientation applied, the sides swapped by a quarter turn)
		var up = helder.image.Exif.apply(rgba, w, h, o);
		return {width: up.width, height: up.height, pixelsWidth: up.width, pixelsHeight: up.height, rgba: up.rgba};
	}

	// (the frame's EXIF orientation, 1 to 8, by its metadata query reader: the photo
	// policy System.Photo.Orientation, else JPEG's and TIFF's IFD0 tag 274; 1: none)
	static function orientation(frame:Ptr):Int {
		var out:Ptr<Ptr> = LibC.malloc(8);
		out.value = Ptr.nil();
		var o = 1;
		if (IWICBitmapFrameDecode.GetMetadataQueryReader(frame, out) >= 0 && !out.value.isNull()) {
			var reader = out.value;
			// (PROPVARIANT: vt at 0, the value at 8; VT_UI2 18)
			var pv:Ptr<UInt16> = LibC.malloc(24);
			for (q in ["System.Photo.Orientation", "/app1/ifd/{ushort=274}", "/ifd/{ushort=274}"]) {
				LibC.memset(cast pv, 0, 24);
				var hr = Arena.scopedValue(a -> IWICMetadataQueryReader.GetMetadataByName(reader, a.wstring(q), cast pv));
				if (hr >= 0 && pv[0] == 18 && pv[4] >= 1 && pv[4] <= 8) {
					o = pv[4];
					break;
				}
				if (hr >= 0) helder.os.win32.FileOpenDialog.Shell32Com.PropVariantClear(cast pv);
			}
			LibC.free(cast pv);
			helder.os.win32.Com.release(reader);
		}
		LibC.free(cast out);
		return o;
	}

	// --- macOS: ImageIO

	static function imageIO(path:String, side:Int):{width:Int, height:Int, pixelsWidth:Int, pixelsHeight:Int, rgba:Bytes} {
		var pool = helder.os.objc.Runtime.objc_autoreleasePoolPush();
		try {
			var p = helder.os.objc.ObjC.str(path);
			var url = helder.os.objc.Msg.idPtr(helder.os.objc.ObjC.cls("NSURL"), helder.os.objc.ObjC.sel("fileURLWithPath:"), p);
			helder.os.objc.ObjC.release(p);
			var src = ImageIO.CGImageSourceCreateWithURL(url, Ptr.nil());
			if (src.isNull()) throw ImageError.unsupported("SystemImages: ImageIO cannot open it");
			var props = ImageIO.CGImageSourceCopyPropertiesAtIndex(src, 0, Ptr.nil());
			if (props.isNull()) {
				CFs.CFRelease(src);
				throw ImageError.unsupported("SystemImages: ImageIO reads no image in it");
			}
			inline function number(key:String):Int {
				var k = helder.os.objc.ObjC.str(key);
				var v = helder.os.objc.Msg.idPtr(props, helder.os.objc.ObjC.sel("objectForKey:"), k);
				helder.os.objc.ObjC.release(k);
				return v.isNull() ? 0 : helder.os.objc.Msg.i(v, helder.os.objc.ObjC.sel("integerValue")).toInt();
			}
			var w = number("PixelWidth"), h = number("PixelHeight"), o = number("Orientation");
			CFs.CFRelease(props);
			try ImageLimits.check("SystemImages", w, h, 4) catch (e:ImageError) {
				CFs.CFRelease(src);
				throw e;
			}
			// (a thumbnail of the whole, its orientation applied, at most the side asked for)
			var max = side > 0 ? Std.int(Math.min(side, Math.max(w, h))) : Std.int(Math.max(w, h));
			var keys = ["kCGImageSourceCreateThumbnailFromImageAlways", "kCGImageSourceCreateThumbnailWithTransform", "kCGImageSourceThumbnailMaxPixelSize", "kCGImageSourceShouldCacheImmediately"];
			var dict = helder.os.objc.Msg.id(helder.os.objc.ObjC.cls("NSMutableDictionary"), helder.os.objc.ObjC.sel("dictionary"));
			for (i in 0...keys.length) {
				var k = helder.os.objc.ObjC.str(keys[i]);
				var v = i == 2 ? helder.os.objc.Msg.idInt(helder.os.objc.ObjC.cls("NSNumber"), helder.os.objc.ObjC.sel("numberWithInteger:"), max) : helder.os.objc.Msg.idInt(helder.os.objc.ObjC.cls("NSNumber"),
					helder.os.objc.ObjC.sel("numberWithBool:"), 1);
				helder.os.objc.Msg.vPtrPtr(dict, helder.os.objc.ObjC.sel("setObject:forKey:"), v, k);
				helder.os.objc.ObjC.release(k);
			}
			var img = ImageIO.CGImageSourceCreateThumbnailAtIndex(src, 0, dict);
			CFs.CFRelease(src);
			if (img.isNull()) throw ImageError.corrupt("SystemImages: ImageIO cannot decode it");
			var pw = CG.CGImageGetWidth(img).toInt(), ph = CG.CGImageGetHeight(img).toInt();
			var n = pw * ph * 4, buf = LibC.malloc((n : hxmc.I64));
			// (cleared: CGContextDrawImage composites over what the bitmap holds, so an image with alpha
			// drawn into malloc's leftovers took them in where it is not opaque)
			LibC.memset(buf, 0, (n : hxmc.I64));
			var space = CG.CGColorSpaceCreateWithName(CG.srgb());
			// (kCGImageAlphaPremultipliedLast: R G B A, premultiplied as Core Graphics draws)
			var ctx = CG.CGBitmapContextCreate(buf, pw, ph, 8, pw * 4, space, 1);
			var rect:Ptr<helder.os.objc.CGRect> = LibC.malloc(32);
			rect.value.origin.x = 0;
			rect.value.origin.y = 0;
			rect.value.size.width = pw;
			rect.value.size.height = ph;
			CG.CGContextDrawImage(ctx, rect.value, img);
			LibC.free(cast rect);
			var rgba = Bytes.alloc(n);
			BytesPtr.copyIn(rgba, 0, buf, n);
			LibC.free(buf);
			CFs.CFRelease(ctx);
			CFs.CFRelease(space);
			CFs.CFRelease(img);
			unpremultiply(rgba);
			// (its size as shown: the orientation's quarter turns swap the sides)
			var turned = o >= 5 && o <= 8;
			helder.os.objc.Runtime.objc_autoreleasePoolPop(pool);
			return {width: turned ? h : w, height: turned ? w : h, pixelsWidth: pw, pixelsHeight: ph, rgba: rgba};
		} catch (e:ImageError) {
			helder.os.objc.Runtime.objc_autoreleasePoolPop(pool);
			throw e;
		}
	}

	static function unpremultiply(b:Bytes)
		for (i in 0...b.length >> 2) {
			var a = b.get(4 * i + 3);
			if (a == 0 || a == 255) continue;
			for (c in 0...3)
				b.set(4 * i + c, Std.int(Math.min(255, Math.round(b.get(4 * i + c) * 255 / a))));
		}
}

// (WIC's interfaces: IUnknown 0-2, then each's own, in the headers' order)
@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IWICImagingFactory {
	@:slot(3) static function CreateDecoderFromFilename(self:Ptr, name:Ptr, vendor:Ptr, access:Int, options:Int, out:Ptr<Ptr>):Int;
	@:slot(10) static function CreateFormatConverter(self:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IWICBitmapDecoder {
	@:slot(13) static function GetFrame(self:Ptr, index:Int, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IWICBitmapFrameDecode {
	@:slot(8) static function GetMetadataQueryReader(self:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IWICMetadataQueryReader {
	@:slot(5) static function GetMetadataByName(self:Ptr, name:Ptr, value:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IWICBitmapSource {
	@:slot(3) static function GetSize(self:Ptr, w:Ptr, h:Ptr):Int;
	@:slot(7) static function CopyPixels(self:Ptr, rect:Ptr, stride:Int, size:Int, buffer:Ptr):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IWICFormatConverter {
	@:slot(8) static function Initialize(self:Ptr, source:Ptr, format:Ptr, dither:Int, palette:Ptr, alpha:Float, paletteType:Int):Int;
}

// (each function from the framework that has it: they are bound as the program loads)
@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/ImageIO.framework/ImageIO") extern class ImageIO {
	static function CGImageSourceCreateWithURL(url:Ptr, options:Ptr):Ptr;
	static function CGImageSourceCopyPropertiesAtIndex(src:Ptr, index:hxmc.I64, options:Ptr):Ptr;
	static function CGImageSourceCreateThumbnailAtIndex(src:Ptr, index:hxmc.I64, options:Ptr):Ptr;
}

@:hxmc.unsafe(gc)
@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics") extern class CG {
	static function CGImageGetWidth(img:Ptr):hxmc.I64;
	static function CGImageGetHeight(img:Ptr):hxmc.I64;
	static function CGColorSpaceCreateWithName(name:Ptr):Ptr;
	static function CGBitmapContextCreate(data:Ptr, w:hxmc.I64, h:hxmc.I64, bits:hxmc.I64, stride:hxmc.I64, space:Ptr, info:Int):Ptr;
	static function CGContextDrawImage(ctx:Ptr, rect:helder.os.objc.CGRect, img:Ptr):Void;
	// (kCGColorSpaceSRGB: a CFStringRef the framework exports)
	static inline function srgb():Ptr {
		var p:Ptr<Ptr> = cast Posix.dlsym(Ptr.ofI64(-2), Mem.cstr("kCGColorSpaceSRGB"));
		return p.isNull() ? Ptr.nil() : p.value;
	}
}

@:hxmc.c @:hxmc.lib("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation") extern class CFs {
	static function CFRelease(o:Ptr):Void;
}
