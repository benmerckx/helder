package helder.text.linux;

import hxmc.unsafe.*;
import helder.text.Shaping;

// FreeType's rasterising (Linux: libfreetype.so.6, loaded at run time by
// helder.os.Dl): a face's glyph at a size and a subpixel offset as an 8-bit
// coverage bitmap (FT_RENDER_MODE_NORMAL, unhinted, as helder's own
// rasterizer draws it: the glyphs' places are the layout's). A colour
// glyph (an emoji's bitmap) is left to helder's own colour path.
@:hxmc.unsafe(gc)
class FreeType {
	static var ready = 0;
	static var library = Ptr.nil();
	static final faces = new Map<Int, Ptr>();
	static var vector:Ptr<hxmc.I64> = Ptr.nil();

	public static function available():Bool {
		if (ready == 0) {
			ready = -1;
			if (FT.load("libfreetype.so.6") == null) {
				var p:Ptr<Ptr> = LibC.malloc(8);
				if (FT.FT_Init_FreeType(cast p) == 0) {
					library = p.value;
					ready = 1;
				}
				LibC.free(cast p);
			}
		}
		return ready > 0;
	}

	static function faceOf(f:FontFile):Ptr {
		var h = faces.get(f.id);
		if (h != null) return h;
		var n = f.data.length, data:Ptr<UInt8> = LibC.malloc((n : hxmc.I64));
		LibC.memcpy(data, Mem.addr(f.data.getData()), (n : hxmc.I64));
		var p:Ptr<Ptr> = LibC.malloc(8);
		p.value = Ptr.nil();
		var face = FT.FT_New_Memory_Face(library, data, (n : hxmc.I64), (f.faceIndex : hxmc.I64), cast p) == 0 ? p.value : Ptr.nil();
		LibC.free(cast p);
		faces.set(f.id, face);
		return face;
	}

	// (FT_FaceRec's glyph at 152; FT_GlyphSlotRec's bitmap at 152, bitmap_left 192, bitmap_top 196;
	// FT_Bitmap's rows 0, width 4, pitch 8, buffer 16, pixel_mode 26: x86-64's and arm64's LP64)
	public static function rasterize(f:FontFile, glyph:Int, size:Float, dx:Float, out:GlyphBitmap):Bool {
		if (!available()) return false;
		var face = faceOf(f);
		if (face.isNull()) return false;
		if (vector.isNull()) vector = LibC.malloc(16);
		FT.FT_Set_Char_Size(face, 0, (Math.round(size * 64) : hxmc.I64), 72, 72);
		vector[0] = (Math.round(dx * 64) : hxmc.I64);
		vector[1] = 0;
		FT.FT_Set_Transform(face, Ptr.nil(), cast vector);
		// (FT_LOAD_NO_HINTING | FT_LOAD_NO_BITMAP)
		if (FT.FT_Load_Glyph(face, glyph, 2 | 8) != 0) return false;
		var slot:Ptr = (cast face.add(152) : Ptr<Ptr>).value;
		if (FT.FT_Render_Glyph(slot, 0) != 0) return false;
		var bm:Ptr<UInt8> = cast slot.add(152);
		var rows:Int = (cast bm : Ptr<Int32>)[0], width:Int = (cast bm.add(4) : Ptr<Int32>)[0], pitch:Int = (cast bm.add(8) : Ptr<Int32>)[0];
		var buf:Ptr<UInt8> = (cast bm.add(16) : Ptr<Ptr>).value;
		if (bm[26] != 2) return false; // (FT_PIXEL_MODE_GRAY)
		out.size(width, rows);
		out.left = (cast slot.add(192) : Ptr<Int32>)[0];
		out.top = -(cast slot.add(196) : Ptr<Int32>)[0];
		for (y in 0...rows)
			BytesPtr.copyIn(out.pixels, y * width, buf.add(y * pitch), width);
		return true;
	}
}

@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class FT {
	static function FT_Init_FreeType(library:Ptr):Int;
	static function FT_New_Memory_Face(library:Ptr, data:Ptr, size:hxmc.I64, index:hxmc.I64, face:Ptr):Int;
	static function FT_Set_Char_Size(face:Ptr, w:hxmc.I64, h:hxmc.I64, xdpi:Int, ydpi:Int):Int;
	static function FT_Set_Transform(face:Ptr, matrix:Ptr, delta:Ptr):Void;
	static function FT_Load_Glyph(face:Ptr, glyph:Int, flags:Int):Int;
	static function FT_Render_Glyph(slot:Ptr, mode:Int):Int;
}
