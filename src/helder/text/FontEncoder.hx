package helder.text;

import haxe.io.Bytes;
import haxe.io.BytesOutput;

// A point of a TrueType contour: on the curve, or the control point of a
// quadratic between its neighbours (two off-curve points in a row imply
// the on-curve point halfway between them, as glyf reads them)
typedef FontPoint = {x:Float, y:Float, on:Bool};

typedef FontGlyph = {
	// the characters it is (none: reached only by others, .notdef)
	codes:Array<Int>,
	advance:Float,
	// closed contours, outer ones clockwise (y up), holes the other way
	contours:Array<Array<FontPoint>>
}

typedef FontSource = {
	family:String,
	?style:String,
	unitsPerEm:Int,
	ascender:Int,
	// negative: below the baseline
	descender:Int,
	?lineGap:Int,
	?xHeight:Int,
	?capHeight:Int,
	?weight:Int,
	// glyph 0 is .notdef, drawn where a character is missing
	glyphs:Array<FontGlyph>,
	// its PostScript name (null: the family's and style's, "Family-Style");
	// a font replaced while running needs a new one, as a system's engine
	// (Core Text) keeps the first font of a name it was given
	?postScriptName:String,
	// when it was made, in seconds since 1970 (null: now)
	?modified:Float,
	// pairs of glyph indices and the space put between them
	?kerning:Array<{left:Int, right:Int, value:Int}>
}

// A TrueType font (.ttf) written from glyphs of quadratic contours: the
// tables an installed font and a browser's @font-face need (head, hhea,
// maxp, OS/2, hmtx, cmap formats 4, name, post 3, loca, glyf) and kerning
// as the old kern table; no hinting, the characters of the Basic
// Multilingual Plane. FontFile.parse reads it back.
class FontEncoder {
	public static function encode(font:FontSource):Bytes {
		if (font.glyphs.length == 0) throw "No glyphs";
		if (font.glyphs.length > 65535) throw "Too many glyphs";
		var glyphs = [for (g in font.glyphs) shape(g)];
		var tables = [
			"cmap" => cmap(font.glyphs),
			"glyf" => null,
			"hmtx" => hmtx(glyphs),
			"name" => name(font),
			"post" => post(font),
			"OS/2" => os2(font, glyphs)
		];
		var glyf = new BytesOutput(), offsets = [];
		glyf.bigEndian = true;
		for (g in glyphs) {
			offsets.push(glyf.length);
			writeGlyph(glyf, g);
		}
		offsets.push(glyf.length);
		tables["glyf"] = glyf.getBytes();
		tables["loca"] = loca(offsets);
		tables["head"] = head(font, glyphs);
		tables["hhea"] = hhea(font, glyphs);
		tables["maxp"] = maxp(glyphs);
		if (font.kerning != null && font.kerning.length > 0) tables["kern"] = kern(font.kerning);
		return sfnt(tables);
	}

	// a glyph's points rounded to the grid, repeats dropped, its bounds
	static function shape(g:FontGlyph):Shape {
		var contours = [];
		for (c in g.contours) {
			var out:Array<{x:Int, y:Int, on:Bool}> = [];
			for (p in c) {
				var x = Math.round(p.x), y = Math.round(p.y), last = out[out.length - 1];
				if (last != null && last.x == x && last.y == y && last.on == p.on) continue;
				out.push({x: x, y: y, on: p.on});
			}
			while (out.length > 1 && out[0].x == out[out.length - 1].x && out[0].y == out[out.length - 1].y && out[0].on == out[out.length - 1].on)
				out.pop();
			if (out.length > 1) contours.push(out);
		}
		var x0 = 0, y0 = 0, x1 = 0, y1 = 0, first = true;
		for (c in contours)
			for (p in c) {
				if (first || p.x < x0) x0 = p.x;
				if (first || p.y < y0) y0 = p.y;
				if (first || p.x > x1) x1 = p.x;
				if (first || p.y > y1) y1 = p.y;
				first = false;
			}
		return {contours: contours, advance: clamp(Math.round(g.advance), 0, 65535), x0: x0, y0: y0, x1: x1, y1: y1};
	}

	static function writeGlyph(out:BytesOutput, g:Shape) {
		if (g.contours.length == 0) return;
		out.writeInt16(g.contours.length);
		for (v in [g.x0, g.y0, g.x1, g.y1])
			out.writeInt16(v);
		var end = -1;
		for (c in g.contours)
			out.writeUInt16(end += c.length);
		out.writeUInt16(0);
		var flags = [], xs = new BytesOutput(), ys = new BytesOutput(), px = 0, py = 0;
		xs.bigEndian = ys.bigEndian = true;
		for (c in g.contours)
			for (p in c) {
				var dx = p.x - px, dy = p.y - py, f = p.on ? 1 : 0;
				px = p.x;
				py = p.y;
				if (dx == 0) f |= 0x10 else if (dx > -256 && dx < 256) {
					f |= dx > 0 ? 0x12 : 0x02;
					xs.writeByte(dx > 0 ? dx : -dx);
				} else xs.writeInt16(dx);
				if (dy == 0) f |= 0x20 else if (dy > -256 && dy < 256) {
					f |= dy > 0 ? 0x24 : 0x04;
					ys.writeByte(dy > 0 ? dy : -dy);
				} else ys.writeInt16(dy);
				flags.push(f);
			}
		for (f in flags)
			out.writeByte(f);
		out.write(xs.getBytes());
		out.write(ys.getBytes());
		while (out.length % 4 != 0)
			out.writeByte(0);
	}

	static function head(font:FontSource, glyphs:Array<Shape>):Bytes {
		var o = output(), b = bounds(glyphs);
		o.writeInt32(0x00010000);
		o.writeInt32(0x00010000);
		o.writeInt32(0); // checkSumAdjustment, set once the whole is written
		o.writeInt32(0x5F0F3CF5);
		o.writeUInt16(0x000B);
		o.writeUInt16(font.unitsPerEm);
		// created and modified: seconds since 1904 as 64 bits
		var t = (font.modified ?? Date.now().getTime() / 1000) + 2082844800.0;
		for (_ in 0...2) {
			o.writeInt32(Std.int(t / 4294967296.0));
			o.writeByte(Std.int(t / 16777216) & 0xFF);
			o.writeByte(Std.int(t / 65536 % 256));
			o.writeByte(Std.int(t / 256 % 256));
			o.writeByte(Std.int(t % 256));
		}
		for (v in b)
			o.writeInt16(v);
		o.writeUInt16(0);
		o.writeUInt16(8);
		o.writeInt16(2);
		o.writeInt16(1); // long offsets in loca
		o.writeInt16(0);
		return o.getBytes();
	}

	static function hhea(font:FontSource, glyphs:Array<Shape>):Bytes {
		var o = output(), maxAdvance = 0, minLeft = 0, minRight = 0, maxExtent = 0, first = true;
		for (g in glyphs) {
			if (g.advance > maxAdvance) maxAdvance = g.advance;
			if (g.contours.length == 0) continue;
			var right = g.advance - g.x1;
			if (first || g.x0 < minLeft) minLeft = g.x0;
			if (first || right < minRight) minRight = right;
			if (first || g.x1 > maxExtent) maxExtent = g.x1;
			first = false;
		}
		o.writeInt32(0x00010000);
		o.writeInt16(font.ascender);
		o.writeInt16(font.descender);
		o.writeInt16(font.lineGap ?? 0);
		o.writeUInt16(maxAdvance);
		o.writeInt16(minLeft);
		o.writeInt16(minRight);
		o.writeInt16(maxExtent);
		o.writeInt16(1);
		o.writeInt16(0);
		o.writeInt16(0);
		for (_ in 0...5)
			o.writeInt16(0);
		o.writeUInt16(glyphs.length);
		return o.getBytes();
	}

	static function maxp(glyphs:Array<Shape>):Bytes {
		var o = output(), points = 0, contours = 0;
		for (g in glyphs) {
			var n = 0;
			for (c in g.contours)
				n += c.length;
			if (n > points) points = n;
			if (g.contours.length > contours) contours = g.contours.length;
		}
		o.writeInt32(0x00010000);
		o.writeUInt16(glyphs.length);
		o.writeUInt16(points);
		o.writeUInt16(contours);
		o.writeUInt16(0);
		o.writeUInt16(0);
		o.writeUInt16(2);
		for (_ in 0...8)
			o.writeUInt16(0);
		return o.getBytes();
	}

	static function os2(font:FontSource, glyphs:Array<Shape>):Bytes {
		var o = output(), em = font.unitsPerEm, sum = 0, n = 0;
		for (g in glyphs)
			if (g.advance > 0) {
				sum += g.advance;
				n++;
			}
		var codes = [for (g in font.glyphs) for (c in g.codes) if (c <= 0xFFFF) c];
		codes.sort((a, b) -> a - b);
		var b = bounds(glyphs), lineGap = font.lineGap ?? 0;
		o.writeUInt16(4);
		o.writeInt16(n == 0 ? 0 : Math.round(sum / n));
		o.writeUInt16(clamp(font.weight ?? 400, 1, 1000));
		o.writeUInt16(5);
		o.writeUInt16(0);
		// sub- and superscripts, the strikeout
		for (v in [em * 65 / 100, em * 60 / 100, 0, em * 7 / 100, em * 65 / 100, em * 60 / 100, 0, em * 35 / 100, em * 5 / 100, em * 25 / 100])
			o.writeInt16(Math.round(v));
		o.writeInt16(0);
		for (_ in 0...10)
			o.writeByte(0);
		o.writeInt32(codes.length > 0 && codes[codes.length - 1] > 0x7F ? 3 : 1);
		for (_ in 0...3)
			o.writeInt32(0);
		o.writeString("HLDR");
		o.writeUInt16(0x40 | 0x80); // regular, typographic metrics
		o.writeUInt16(codes.length > 0 ? codes[0] : 0);
		o.writeUInt16(codes.length > 0 ? codes[codes.length - 1] : 0);
		o.writeInt16(font.ascender);
		o.writeInt16(font.descender);
		o.writeInt16(lineGap);
		o.writeUInt16(clamp(b[3] > font.ascender ? b[3] : font.ascender, 0, 65535));
		o.writeUInt16(clamp(-b[1] > -font.descender ? -b[1] : -font.descender, 0, 65535));
		o.writeInt32(1);
		o.writeInt32(0);
		o.writeInt16(font.xHeight ?? Math.round(em / 2));
		o.writeInt16(font.capHeight ?? Math.round(em * 7 / 10));
		o.writeUInt16(0);
		o.writeUInt16(32);
		o.writeUInt16(0);
		return o.getBytes();
	}

	static function hmtx(glyphs:Array<Shape>):Bytes {
		var o = output();
		for (g in glyphs) {
			o.writeUInt16(g.advance);
			o.writeInt16(g.x0);
		}
		return o.getBytes();
	}

	// format 4: a segment per run of characters whose glyphs follow each other
	static function cmap(glyphs:Array<FontGlyph>):Bytes {
		var map = new Map<Int, Int>();
		for (i in 0...glyphs.length)
			for (c in glyphs[i].codes)
				if (c >= 0 && c < 0xFFFF && !map.exists(c)) map.set(c, i);
		var codes = [for (c in map.keys()) c];
		codes.sort((a, b) -> a - b);
		var segments:Array<{start:Int, end:Int, delta:Int}> = [];
		for (c in codes) {
			var g = map[c], last = segments[segments.length - 1];
			if (last != null && last.end == c - 1 && c + last.delta == g) last.end = c else segments.push({start: c, end: c, delta: g - c});
		}
		segments.push({start: 0xFFFF, end: 0xFFFF, delta: 1});
		var n = segments.length, power = 1, log = 0;
		while (power * 2 <= n) {
			power *= 2;
			log++;
		}
		var sub = output();
		sub.writeUInt16(4);
		sub.writeUInt16(16 + n * 8);
		sub.writeUInt16(0);
		sub.writeUInt16(n * 2);
		sub.writeUInt16(power * 2);
		sub.writeUInt16(log);
		sub.writeUInt16(n * 2 - power * 2);
		for (s in segments)
			sub.writeUInt16(s.end);
		sub.writeUInt16(0);
		for (s in segments)
			sub.writeUInt16(s.start);
		for (s in segments)
			sub.writeUInt16(s.delta & 0xFFFF);
		for (_ in segments)
			sub.writeUInt16(0);
		var o = output();
		o.writeUInt16(0);
		o.writeUInt16(2);
		// Unicode's BMP and Windows' Unicode, both the one subtable
		for (platform in [[0, 3], [3, 1]]) {
			o.writeUInt16(platform[0]);
			o.writeUInt16(platform[1]);
			o.writeInt32(20);
		}
		o.write(sub.getBytes());
		return o.getBytes();
	}

	static function name(font:FontSource):Bytes {
		var style = font.style ?? "Regular", ps = ~/[^A-Za-z0-9-]/g.replace(font.family, "");
		if (ps == "") ps = "Untitled";
		var names = [
			font.family,
			style,
			font.family + " " + style,
			style == "Regular" ? font.family : font.family + " " + style,
			"Version 1.000",
			font.postScriptName ?? ps + "-" + ~/[^A-Za-z0-9]/g.replace(style, "")
		];
		var strings = new BytesOutput(), o = output();
		strings.bigEndian = true;
		o.writeUInt16(0);
		o.writeUInt16(names.length);
		o.writeUInt16(6 + names.length * 12);
		for (id in 0...names.length) {
			var s = names[id], start = strings.length;
			for (i in 0...s.length) {
				var c = StringTools.fastCodeAt(s, i);
				strings.writeUInt16(c <= 0xFFFF ? c : 0xFFFD);
			}
			o.writeUInt16(3);
			o.writeUInt16(1);
			o.writeUInt16(0x409);
			o.writeUInt16(id + 1);
			o.writeUInt16(strings.length - start);
			o.writeUInt16(start);
		}
		o.write(strings.getBytes());
		return o.getBytes();
	}

	static function post(font:FontSource):Bytes {
		var o = output();
		o.writeInt32(0x00030000);
		o.writeInt32(0);
		o.writeInt16(-Math.round(font.unitsPerEm / 10));
		o.writeInt16(Math.round(font.unitsPerEm / 20));
		for (_ in 0...5)
			o.writeInt32(0);
		return o.getBytes();
	}

	static function loca(offsets:Array<Int>):Bytes {
		var o = output();
		for (v in offsets)
			o.writeInt32(v);
		return o.getBytes();
	}

	static function kern(pairs:Array<{left:Int, right:Int, value:Int}>):Bytes {
		var sorted = [for (p in pairs) if (p.value != 0) p];
		sorted.sort((a, b) -> a.left != b.left ? a.left - b.left : a.right - b.right);
		if (sorted.length > 10000) sorted.resize(10000);
		var n = sorted.length, power = 1, log = 0;
		while (power * 2 <= n) {
			power *= 2;
			log++;
		}
		var o = output();
		o.writeUInt16(0);
		o.writeUInt16(1);
		o.writeUInt16(0);
		o.writeUInt16(14 + n * 6);
		o.writeUInt16(1);
		o.writeUInt16(n);
		o.writeUInt16(power * 6);
		o.writeUInt16(log);
		o.writeUInt16((n - power) * 6);
		for (p in sorted) {
			o.writeUInt16(p.left);
			o.writeUInt16(p.right);
			o.writeInt16(clamp(p.value, -32768, 32767));
		}
		return o.getBytes();
	}

	// the table directory, then each table on four bytes, head's adjustment last
	static function sfnt(tables:Map<String, Bytes>):Bytes {
		var tags = [for (t in tables.keys()) t];
		tags.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		var n = tags.length, power = 1, log = 0;
		while (power * 2 <= n) {
			power *= 2;
			log++;
		}
		var o = output();
		o.writeInt32(0x00010000);
		o.writeUInt16(n);
		o.writeUInt16(power * 16);
		o.writeUInt16(log);
		o.writeUInt16(n * 16 - power * 16);
		var offset = 12 + n * 16, headAt = 0;
		for (t in tags) {
			var b = tables[t];
			if (t == "head") headAt = offset;
			o.writeString(t);
			o.writeInt32(checksum(b));
			o.writeInt32(offset);
			o.writeInt32(b.length);
			offset += (b.length + 3) & ~3;
		}
		for (t in tags) {
			var b = tables[t];
			o.write(b);
			for (_ in 0...((4 - b.length % 4) % 4))
				o.writeByte(0);
		}
		var out = o.getBytes();
		var adjust = 0xB1B0AFBA - checksum(out);
		out.set(headAt + 8, (adjust >>> 24) & 0xFF);
		out.set(headAt + 9, (adjust >>> 16) & 0xFF);
		out.set(headAt + 10, (adjust >>> 8) & 0xFF);
		out.set(headAt + 11, adjust & 0xFF);
		return out;
	}

	static function checksum(b:Bytes):Int {
		var sum = 0, i = 0;
		while (i < b.length) {
			var v = 0;
			for (k in 0...4)
				v = (v << 8) | (i + k < b.length ? b.get(i + k) : 0);
			sum = (sum + v) | 0;
			i += 4;
		}
		return sum;
	}

	static function bounds(glyphs:Array<Shape>):Array<Int> {
		var b = [0, 0, 0, 0], first = true;
		for (g in glyphs) {
			if (g.contours.length == 0) continue;
			if (first || g.x0 < b[0]) b[0] = g.x0;
			if (first || g.y0 < b[1]) b[1] = g.y0;
			if (first || g.x1 > b[2]) b[2] = g.x1;
			if (first || g.y1 > b[3]) b[3] = g.y1;
			first = false;
		}
		return b;
	}

	static function output():BytesOutput {
		var o = new BytesOutput();
		o.bigEndian = true;
		return o;
	}

	static inline function clamp(v:Int, lo:Int, hi:Int):Int
		return v < lo ? lo : v > hi ? hi : v;
}

private typedef Shape = {
	contours:Array<Array<{x:Int, y:Int, on:Bool}>>,
	advance:Int,
	x0:Int,
	y0:Int,
	x1:Int,
	y1:Int
}
