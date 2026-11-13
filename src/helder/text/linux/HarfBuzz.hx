package helder.text.linux;

import hxmc.unsafe.*;
import helder.text.Shaping;

// HarfBuzz's shaping (Linux: libharfbuzz.so.0, loaded at run time by
// helder.os.Dl: absent, available() is false): a face's text in, its glyphs
// out: ids, clusters (UTF-16 indices), advances and offsets in font units,
// in visual order; the script and language guessed from the text, the
// direction given. Each face's hb_font is made once (its bytes copied for
// the process), the buffer reused.
@:hxmc.unsafe(gc)
class HarfBuzz {
	static var ready = 0;

	public static function available():Bool {
		if (ready == 0) ready = HB.load("libharfbuzz.so.0") == null ? 1 : -1;
		return ready > 0;
	}

	static final fonts = new Map<Int, Ptr>();
	static var buffer = Ptr.nil();
	static var units:Ptr<UInt16> = Ptr.nil();
	static var unitsCap = 0;
	static var features:Ptr<UInt8> = Ptr.nil();

	// (the face's hb_font_t, at a scale of its units per em)
	public static function fontOf(f:FontFile):Ptr {
		var h = fonts.get(f.id);
		if (h != null) return h;
		var n = f.data.length, data:Ptr<UInt8> = LibC.malloc((n : hxmc.I64));
		LibC.memcpy(data, Mem.addr(f.data.getData()), (n : hxmc.I64));
		var blob = HB.hb_blob_create(data, n, 1, Ptr.nil(), Ptr.nil()); // (HB_MEMORY_MODE_READONLY; kept)
		var face = HB.hb_face_create(blob, f.faceIndex), font = HB.hb_font_create(face);
		HB.hb_font_set_scale(font, f.unitsPerEm, f.unitsPerEm);
		fonts.set(f.id, font);
		return font;
	}

	// text[start...end] shaped in f into out (rtl: right to left; features
	// as hb_feature_from_string reads each, "liga=0,kern"); false: no HarfBuzz
	public static function shapeInto(f:FontFile, text:String, start:Int, end:Int, rtl:Bool, out:ShapedGlyphs, ?feats:String):Bool {
		if (!available()) return false;
		var font = fontOf(f);
		if (buffer.isNull()) buffer = HB.hb_buffer_create();
		if (features.isNull()) features = LibC.malloc(16 * 32);
		// (a few units of context each side: what joins or reorders across the run's ends)
		var from = start - 8 < 0 ? 0 : start - 8, to = end + 8 > text.length ? text.length : end + 8, n = to - from;
		if (n + 1 > unitsCap) {
			if (!units.isNull()) LibC.free(cast units);
			unitsCap = (n + 1) * 2;
			units = LibC.malloc(2 * unitsCap);
		}
		for (i in 0...n)
			units[i] = StringTools.fastCodeAt(text, from + i);
		var b = buffer;
		HB.hb_buffer_clear_contents(b);
		HB.hb_buffer_add_utf16(b, cast units, n, start - from, end - start);
		HB.hb_buffer_set_direction(b, rtl ? 5 : 4);
		HB.hb_buffer_guess_segment_properties(b);
		var nf = 0;
		if (feats != null) for (x in feats.split(","))
			if (x != "" && nf < 32 && Arena.scopedValue(a -> HB.hb_feature_from_string(a.cstring(x), x.length, cast features.add(16 * nf))) != 0) nf++;
		HB.hb_shape(font, b, cast features, nf);
		Arena.scoped(a -> {
			var len:Ptr<Int32> = a.alloc(4);
			var infos:Ptr<Int32> = cast HB.hb_buffer_get_glyph_infos(b, cast len), count = len.value;
			var pos:Ptr<Int32> = cast HB.hb_buffer_get_glyph_positions(b, cast len);
			out.reset(count);
			// (hb_glyph_info_t: codepoint, mask, cluster, two vars: 20 bytes; hb_glyph_position_t: x_advance, y_advance, x_offset, y_offset, var)
			for (i in 0...count)
				out.push(infos[5 * i], infos[5 * i + 2] + from, pos[5 * i], pos[5 * i + 2], pos[5 * i + 3]);
		});
		return true;
	}

	// a face's text shaped (the tests' comparison): glyph ids, clusters, advances and offsets
	public static function shape(f:FontFile, text:String, rtl = false, ?features:String):Array<{id:Int, cluster:Int, advance:Int, dx:Int, dy:Int}> {
		var out = new ShapedGlyphs();
		if (!shapeInto(f, text, 0, text.length, rtl, out, features)) return [];
		return [
			for (i in 0...out.count)
				{id: out.ids[i], cluster: out.clusters[i], advance: Std.int(out.advances[i]), dx: Std.int(out.dx[i]), dy: Std.int(out.dy[i])}
		];
	}
}

@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class HB {
	static function hb_blob_create(data:Ptr, length:Int, mode:Int, user:Ptr, destroy:Ptr):Ptr;
	static function hb_face_create(blob:Ptr, index:Int):Ptr;
	static function hb_font_create(face:Ptr):Ptr;
	static function hb_font_set_scale(f:Ptr, x:Int, y:Int):Void;
	static function hb_buffer_create():Ptr;
	static function hb_buffer_clear_contents(b:Ptr):Void;
	static function hb_buffer_add_utf16(b:Ptr, text:Ptr, length:Int, offset:Int, itemLength:Int):Void;
	static function hb_buffer_guess_segment_properties(b:Ptr):Void;
	static function hb_buffer_set_direction(b:Ptr, d:Int):Void;
	static function hb_feature_from_string(s:Ptr, len:Int, feature:Ptr):Int;
	static function hb_shape(font:Ptr, buffer:Ptr, features:Ptr, n:Int):Void;
	static function hb_buffer_get_glyph_infos(b:Ptr, length:Ptr):Ptr;
	static function hb_buffer_get_glyph_positions(b:Ptr, length:Ptr):Ptr;
}
