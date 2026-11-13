package helder.os.linux;

import haxe.io.Bytes;
import helder.image.ImageError;
import helder.image.ImageLimits;
import hxmc.unsafe.*;

// Linux's image libraries behind SystemImages, each loaded at run time when
// first needed (helder.os.Dl; one absent: the formats it reads are not
// supported, nothing else changes): libtiff (TIFFReadRGBAImageOriented as
// stored, then its orientation tag applied), libheif (HEIC and HEIF, and
// AVIF where it has an AV1 decoder: its primary image as interleaved RGBA,
// its transformations applied), libavif (AVIF: YUV to RGBA), libraw
// (cameras' RAW files: dcraw's processing, 8-bit sRGB, its flip applied).
// ImageLimits is checked on the size each reports before it decodes a
// pixel (HEIF's and AVIF's from the file's ispe boxes, before libavif
// reads it). Pixels: RGBA8, straight alpha, upright.
@:hxmc.unsafe(gc)
class LinuxImages {
	static final state = new Map<String, Int>(); // (1: loaded, -1: absent)

	static function loaded(lib:String):Bool {
		if (!state.exists(lib)) {
			var ok = switch lib {
				case "tiff": Tiff.load("libtiff.so.6") == null || Tiff.load("libtiff.so.5") == null;
				case "heif": Heif.load("libheif.so.1") == null;
				case "avif": Avif.load("libavif.so.16") == null || Avif.load("libavif.so.15") == null || Avif.load("libavif.so.13") == null;
				case "raw": Raw.load("libraw_r.so.23") == null || Raw.load("libraw.so.23") == null || Raw.load("libraw_r.so.20") == null || Raw.load("libraw.so.20") == null;
				case _: false;
			}
			if (ok && lib == "tiff") {
				// (no messages of its own on stderr: its errors are ours)
				Tiff.TIFFSetErrorHandler(Ptr.nil());
				Tiff.TIFFSetWarningHandler(Ptr.nil());
			}
			if (ok && lib == "heif") Heif.heif_init(Ptr.nil());
			state.set(lib, ok ? 1 : -1);
		}
		return state.get(lib) > 0;
	}

	// (the library for an extension: AVIF's libavif, else libheif's when it decodes AV1)
	static function libFor(ext:String):Null<String>
		return switch ext {
			case "tif" | "tiff": loaded("tiff") ? "tiff" : null;
			case "heic" | "heif": loaded("heif") ? "heif" : null;
			case "avif": loaded("avif") ? "avif" : loaded("heif") && Heif.heif_have_decoder_for_format(4) != 0 ? "heif" : null; // (heif_compression_AV1)
			case "dng" | "cr2" | "cr3" | "nef" | "arw" | "raf" | "orf" | "rw2": loaded("raw") ? "raw" : null;
			case _: null;
		}

	public static function any():Bool
		return loaded("tiff") || loaded("heif") || loaded("avif") || loaded("raw");

	public static function supports(ext:String):Bool
		return libFor(ext) != null;

	public static function decode(path:String, ext:String):{width:Int, height:Int, rgba:Bytes} {
		var lib = libFor(ext);
		return switch lib {
			case "tiff": tiff(path);
			case "heif": heif(path);
			case "avif": avif(path);
			case "raw": raw(path);
			case _: throw ImageError.unsupported("SystemImages: no library on this system for " + path);
		}
	}

	// --- libtiff

	static function tiff(path:String):{width:Int, height:Int, rgba:Bytes} {
		var t = Arena.scopedValue(a -> Tiff.TIFFOpen(a.cstring(path), a.cstring("r")));
		if (t.isNull()) throw ImageError.corrupt("SystemImages: libtiff cannot open it");
		var v:Ptr<Int32> = LibC.malloc(16);
		v[0] = v[1] = v[2] = 0;
		Tiff.TIFFGetField(t, 256, cast v); // (TIFFTAG_IMAGEWIDTH, TIFFTAG_IMAGELENGTH: uint32)
		Tiff.TIFFGetField(t, 257, cast v.add(4));
		Tiff.TIFFGetFieldDefaulted(t, 274, cast v.add(8)); // (TIFFTAG_ORIENTATION: uint16)
		var w = v[0], h = v[1], o = v[2] & 0xFFFF;
		LibC.free(cast v);
		if (o < 1 || o > 8) o = 1;
		try ImageLimits.check("SystemImages", w, h, 4) catch (e:ImageError) {
			Tiff.TIFFClose(t);
			throw e;
		}
		var n = w * h * 4, buf = LibC.malloc((n : hxmc.I64));
		// (as stored: the orientation asked its own, so libtiff flips nothing; then all of it applied)
		var ok = Tiff.TIFFReadRGBAImageOriented(t, w, h, buf, o, 0) != 0;
		Tiff.TIFFClose(t);
		var rgba = Bytes.alloc(n);
		if (ok) BytesPtr.copyIn(rgba, 0, buf, n);
		LibC.free(buf);
		if (!ok) throw ImageError.corrupt("SystemImages: libtiff cannot decode it");
		// (TIFFRGBAImage's pixels are premultiplied where the file's alpha is associated: straight here)
		return helder.image.Exif.apply(rgba, w, h, o);
	}

	// --- libheif

	static function heif(path:String):{width:Int, height:Int, rgba:Bytes} {
		ispeLimits(path);
		var ctx = Heif.heif_context_alloc();
		var out:Ptr<Ptr> = LibC.malloc(16);
		out.value = Ptr.nil();
		function fail(e:ImageError):Dynamic {
			LibC.free(cast out);
			Heif.heif_context_free(ctx);
			throw e;
		}
		// (heif_error by value: its code the first word's low half)
		if (Arena.scopedValue(a -> Heif.heif_context_read_from_file(ctx, a.cstring(path), Ptr.nil())).toInt() != 0) fail(ImageError.corrupt("SystemImages: libheif cannot read it"));
		if (Heif.heif_context_get_primary_image_handle(ctx, out).toInt() != 0 || out.value.isNull()) fail(ImageError.corrupt("SystemImages: no primary image"));
		var handle = out.value;
		var w = Heif.heif_image_handle_get_width(handle), h = Heif.heif_image_handle_get_height(handle);
		try ImageLimits.check("SystemImages", w, h, 4) catch (e:ImageError) {
			Heif.heif_image_handle_release(handle);
			fail(e);
		}
		out.value = Ptr.nil();
		// (heif_colorspace_RGB, heif_chroma_interleaved_RGBA; the default options: its transformations applied)
		var hr = Heif.heif_decode_image(handle, out, 1, 11, Ptr.nil()).toInt();
		Heif.heif_image_handle_release(handle);
		if (hr != 0 || out.value.isNull()) fail(ImageError.unsupported("SystemImages: libheif cannot decode it (no decoder for its codec?)"));
		var img = out.value, stride:Ptr<Int32> = cast out.add(8);
		var pw = Heif.heif_image_get_width(img, 10), ph = Heif.heif_image_get_height(img, 10); // (heif_channel_interleaved)
		var plane:Ptr<UInt8> = cast Heif.heif_image_get_plane_readonly(img, 10, cast stride);
		var rgba = Bytes.alloc(pw * ph * 4), s = stride[0];
		if (!plane.isNull()) for (y in 0...ph)
			BytesPtr.copyIn(rgba, y * pw * 4, plane.add(y * s), pw * 4);
		Heif.heif_image_release(img);
		LibC.free(cast out);
		Heif.heif_context_free(ctx);
		if (plane.isNull()) throw ImageError.corrupt("SystemImages: libheif gave no pixels");
		return {width: pw, height: ph, rgba: rgba};
	}

	// (HEIF's and AVIF's sizes from their ispe boxes, the largest, before any library reads the file)
	static function ispeLimits(path:String) {
		var f = try sys.io.File.read(path, true) catch (e:Dynamic) throw ImageError.corrupt("SystemImages: unreadable");
		var size = try sys.FileSystem.stat(path).size catch (e:Dynamic) 0;
		var head = try f.read(size < 65536 ? size : 65536) catch (e:Dynamic) Bytes.alloc(0);
		f.close();
		var w = 0, h = 0, i = 4;
		while (i + 16 <= head.length) {
			if (head.get(i) == "i".code && head.getString(i, 4) == "ispe") {
				inline function be(p:Int):Int
					return (head.get(p) << 24) | (head.get(p + 1) << 16) | (head.get(p + 2) << 8) | head.get(p + 3);
				var bw = be(i + 8), bh = be(i + 12);
				if ((bw : Float) * bh > (w : Float) * h) {
					w = bw;
					h = bh;
				}
			}
			i++;
		}
		if (w != 0) ImageLimits.check("SystemImages", w, h, 4);
	}

	// --- libavif

	static function avif(path:String):{width:Int, height:Int, rgba:Bytes} {
		ispeLimits(path);
		var dec = Avif.avifDecoderCreate(), img = Avif.avifImageCreateEmpty();
		var r = Arena.scopedValue(a -> Avif.avifDecoderReadFile(dec, img, a.cstring(path)));
		Avif.avifDecoderDestroy(dec);
		if (r != 0) {
			Avif.avifImageDestroy(img);
			throw ImageError.corrupt("SystemImages: libavif cannot decode it (" + r + ")");
		}
		// (avifImage: width, height first, in every version)
		var dims:Ptr<Int32> = cast img, w = dims[0], h = dims[1];
		try ImageLimits.check("SystemImages", w, h, 4) catch (e:ImageError) {
			Avif.avifImageDestroy(img);
			throw e;
		}
		// (avifRGBImage: width, height, depth, format first; its pixels and rowBytes last, where
		// their offset differs by version: found as the pointer before a word of width * 4)
		var rgb:Ptr<Int32> = LibC.malloc(256);
		LibC.memset(cast rgb, 0, 256);
		Avif.avifRGBImageSetDefaults(cast rgb, img);
		rgb[2] = 8;
		rgb[3] = 1; // (AVIF_RGB_FORMAT_RGBA)
		Avif.avifRGBImageAllocatePixels(cast rgb);
		var pixels:Ptr<UInt8> = Ptr.nil(), row = 0, k = 16, base:Ptr<UInt8> = cast rgb;
		while (k + 12 <= 256 && pixels.isNull()) {
			var p:Ptr<Ptr> = cast base.add(k), next:Ptr<Int32> = cast base.add(k + 8);
			if (!p.value.isNull() && next.value == w * 4) {
				pixels = cast p.value;
				row = w * 4;
			}
			k += 8;
		}
		var ok = !pixels.isNull() && Avif.avifImageYUVToRGB(img, cast rgb) == 0;
		var rgba = Bytes.alloc(w * h * 4);
		if (ok) for (y in 0...h)
			BytesPtr.copyIn(rgba, y * w * 4, pixels.add(y * row), w * 4);
		Avif.avifRGBImageFreePixels(cast rgb);
		LibC.free(cast rgb);
		Avif.avifImageDestroy(img);
		if (!ok) throw ImageError.corrupt("SystemImages: libavif's colours");
		return {width: w, height: h, rgba: rgba};
	}

	// --- libraw

	static function raw(path:String):{width:Int, height:Int, rgba:Bytes} {
		var lr = Raw.libraw_init(0);
		if (lr.isNull()) throw ImageError.unsupported("SystemImages: libraw");
		function fail(e:ImageError):Dynamic {
			Raw.libraw_close(lr);
			throw e;
		}
		if (Arena.scopedValue(a -> Raw.libraw_open_file(lr, a.cstring(path))) != 0) fail(ImageError.unsupported("SystemImages: libraw cannot read it"));
		var w = Raw.libraw_get_iwidth(lr), h = Raw.libraw_get_iheight(lr);
		try ImageLimits.check("SystemImages", w, h, 4) catch (e:ImageError) fail(e);
		if (Raw.libraw_unpack(lr) != 0 || Raw.libraw_dcraw_process(lr) != 0) fail(ImageError.corrupt("SystemImages: libraw cannot decode it"));
		var err:Ptr<Int32> = LibC.malloc(8);
		var im:Ptr<UInt8> = cast Raw.libraw_dcraw_make_mem_image(lr, cast err);
		LibC.free(cast err);
		if (im.isNull()) fail(ImageError.corrupt("SystemImages: libraw made no image"));
		// (libraw_processed_image_t: type, height, width, colors, bits, data_size, data: 8-bit RGB, its flip applied)
		var u:Ptr<UInt16> = cast im;
		var ph:Int = u[2], pw:Int = u[3], colors:Int = u[4], bits:Int = u[5];
		var ok = colors == 3 && bits == 8;
		var rgba = Bytes.alloc(ok ? pw * ph * 4 : 0);
		if (ok) {
			var d = im.add(16);
			for (i in 0...pw * ph) {
				rgba.set(4 * i, d[3 * i]);
				rgba.set(4 * i + 1, d[3 * i + 1]);
				rgba.set(4 * i + 2, d[3 * i + 2]);
				rgba.set(4 * i + 3, 255);
			}
		}
		Raw.libraw_dcraw_clear_mem(cast im);
		Raw.libraw_close(lr);
		if (!ok) throw ImageError.unsupported("SystemImages: libraw's image is not 8-bit RGB");
		return {width: pw, height: ph, rgba: rgba};
	}
}

@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class Tiff {
	static function TIFFOpen(path:Ptr, mode:Ptr):Ptr;
	static function TIFFClose(t:Ptr):Void;
	static function TIFFGetField(t:Ptr, tag:Int, out:Ptr):Int;
	static function TIFFGetFieldDefaulted(t:Ptr, tag:Int, out:Ptr):Int;
	static function TIFFReadRGBAImageOriented(t:Ptr, w:Int, h:Int, raster:Ptr, orientation:Int, stop:Int):Int;
	static function TIFFSetErrorHandler(h:Ptr):Ptr;
	static function TIFFSetWarningHandler(h:Ptr):Ptr;
}

// (struct heif_error returns as two words: its code and subcode the first)
@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class Heif {
	static function heif_init(params:Ptr):hxmc.I64;
	static function heif_have_decoder_for_format(format:Int):Int;
	static function heif_context_alloc():Ptr;
	static function heif_context_free(ctx:Ptr):Void;
	static function heif_context_read_from_file(ctx:Ptr, path:Ptr, options:Ptr):hxmc.I64;
	static function heif_context_get_primary_image_handle(ctx:Ptr, out:Ptr):hxmc.I64;
	static function heif_image_handle_get_width(h:Ptr):Int;
	static function heif_image_handle_get_height(h:Ptr):Int;
	static function heif_image_handle_release(h:Ptr):Void;
	static function heif_decode_image(h:Ptr, out:Ptr, colorspace:Int, chroma:Int, options:Ptr):hxmc.I64;
	static function heif_image_get_width(img:Ptr, channel:Int):Int;
	static function heif_image_get_height(img:Ptr, channel:Int):Int;
	static function heif_image_get_plane_readonly(img:Ptr, channel:Int, stride:Ptr):Ptr;
	static function heif_image_release(img:Ptr):Void;
}

@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class Avif {
	static function avifDecoderCreate():Ptr;
	static function avifDecoderDestroy(d:Ptr):Void;
	static function avifImageCreateEmpty():Ptr;
	static function avifImageDestroy(i:Ptr):Void;
	static function avifDecoderReadFile(d:Ptr, img:Ptr, path:Ptr):Int;
	static function avifRGBImageSetDefaults(rgb:Ptr, img:Ptr):Void;
	static function avifRGBImageAllocatePixels(rgb:Ptr):Int;
	static function avifImageYUVToRGB(img:Ptr, rgb:Ptr):Int;
	static function avifRGBImageFreePixels(rgb:Ptr):Void;
}

@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class Raw {
	static function libraw_init(flags:Int):Ptr;
	static function libraw_open_file(lr:Ptr, path:Ptr):Int;
	static function libraw_get_iwidth(lr:Ptr):Int;
	static function libraw_get_iheight(lr:Ptr):Int;
	static function libraw_unpack(lr:Ptr):Int;
	static function libraw_dcraw_process(lr:Ptr):Int;
	static function libraw_dcraw_make_mem_image(lr:Ptr, err:Ptr):Ptr;
	static function libraw_dcraw_clear_mem(img:Ptr):Void;
	static function libraw_close(lr:Ptr):Void;
}
