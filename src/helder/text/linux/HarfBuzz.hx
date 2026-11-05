package helder.text.linux;

import haxe.io.Bytes;
import hxmc.unsafe.*;

// HarfBuzz's shaping (Linux: libharfbuzz.so.0 through dlopen): a font's
// bytes and a text in, its glyphs out: ids, clusters (UTF-16 indices),
// advances and offsets in font units, in visual order; the script,
// direction and language guessed from the text (or given). The native
// shaper helder.text's layout can be compared with (tests) and, later,
// shape with.
class HarfBuzz {
	public static function available():Bool
		return try HB.hb_version_string() != Ptr.nil() catch (_:Dynamic) false;

	// (direction: 0 guessed, 4 left to right, 5 right to left; features: "liga=0,kern" as hb_feature_from_string reads each)
	public static function shape(font:Bytes, index:Int, text:String, direction = 0, ?features:String):Array<{id:Int, cluster:Int, advance:Int, dx:Int, dy:Int}> {
		var out = [];
		Arena.scoped(a -> {
			var data = a.copyBytes(font);
			var blob = HB.hb_blob_create(data, font.length, 1, Ptr.nil(), Ptr.nil()); // (HB_MEMORY_MODE_READONLY)
			var face = HB.hb_face_create(blob, index), f = HB.hb_font_create(face);
			var upem = HB.hb_face_get_upem(face);
			HB.hb_font_set_scale(f, upem, upem);
			var buf = HB.hb_buffer_create();
			var u16:Ptr<UInt16> = a.alloc(2 * text.length + 2);
			for (i in 0...text.length)
				u16[i] = StringTools.fastCodeAt(text, i);
			HB.hb_buffer_add_utf16(buf, cast u16, text.length, 0, text.length);
			HB.hb_buffer_guess_segment_properties(buf);
			if (direction != 0) HB.hb_buffer_set_direction(buf, direction);
			var feats = features == null ? [] : features.split(",").filter(x -> x != "");
			var fp:Ptr<UInt8> = a.alloc(16 * feats.length + 16), nf = 0;
			for (x in feats)
				if (HB.hb_feature_from_string(a.cstring(x), x.length, cast fp.add(16 * nf)) != 0) nf++;
			HB.hb_shape(f, buf, cast fp, nf);
			var len:Ptr<Int32> = a.alloc(4);
			var infos:Ptr<Int32> = cast HB.hb_buffer_get_glyph_infos(buf, cast len), n = len.value;
			var pos:Ptr<Int32> = cast HB.hb_buffer_get_glyph_positions(buf, cast len);
			// (hb_glyph_info_t: codepoint, mask, cluster, two vars: 20 bytes; hb_glyph_position_t: x_advance, y_advance, x_offset, y_offset, var)
			for (i in 0...n)
				out.push({id: infos[5 * i], cluster: infos[5 * i + 2], advance: pos[5 * i], dx: pos[5 * i + 2], dy: pos[5 * i + 3]});
			HB.hb_buffer_destroy(buf);
			HB.hb_font_destroy(f);
			HB.hb_face_destroy(face);
			HB.hb_blob_destroy(blob);
		});
		return out;
	}
}

@:hxmc.c @:hxmc.lib("libharfbuzz.so.0") extern class HB {
	static function hb_version_string():Ptr;
	static function hb_blob_create(data:Ptr, length:Int, mode:Int, user:Ptr, destroy:Ptr):Ptr;
	static function hb_blob_destroy(b:Ptr):Void;
	static function hb_face_create(blob:Ptr, index:Int):Ptr;
	static function hb_face_destroy(f:Ptr):Void;
	static function hb_face_get_upem(f:Ptr):Int;
	static function hb_font_create(face:Ptr):Ptr;
	static function hb_font_destroy(f:Ptr):Void;
	static function hb_font_set_scale(f:Ptr, x:Int, y:Int):Void;
	static function hb_buffer_create():Ptr;
	static function hb_buffer_destroy(b:Ptr):Void;
	static function hb_buffer_add_utf16(b:Ptr, text:Ptr, length:Int, offset:Int, itemLength:Int):Void;
	static function hb_buffer_guess_segment_properties(b:Ptr):Void;
	static function hb_buffer_set_direction(b:Ptr, d:Int):Void;
	static function hb_feature_from_string(s:Ptr, len:Int, feature:Ptr):Int;
	static function hb_shape(font:Ptr, buffer:Ptr, features:Ptr, n:Int):Void;
	static function hb_buffer_get_glyph_infos(b:Ptr, length:Ptr):Ptr;
	static function hb_buffer_get_glyph_positions(b:Ptr, length:Ptr):Ptr;
}
