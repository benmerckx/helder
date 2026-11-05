package helder.pdf;

import helder.pdf.PdfValue;
import helder.pdf.Document;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

// An embedded Type 1 font program (FontFile; Adobe's Type 1 Font Format):
// the clear part's /Encoding, the eexec part decrypted (r = 55665), its
// /Subrs and /CharStrings (each decrypted again, r = 4330, lenIV bytes
// skipped), the charstrings run into a Path's outline (hsbw, sbw, the
// moves, lines and curves, closepath, callsubr and return, seac's accents,
// flex through othersubrs 0 to 2, div; hints skipped), in its units (a
// thousand an em, by FontMatrix's default)
class Type1 {
	public final encoding = new Map<Int, String>();
	final charStrings = new Map<String, Bytes>();
	final subrs:Array<Bytes> = [];
	var lenIV = 4;
	public var fontMatrix:Array<Float> = [0.001, 0, 0, 0.001, 0, 0];

	public function new(data:Bytes, length1:Int) {
		// (a PFB's segments: their headers stripped)
		if (data.length > 6 && data.get(0) == 0x80) data = pfb(data);
		var clearEnd = findEexec(data, length1);
		var clear = latin1(data, 0, clearEnd);
		var re = ~/dup\s+(\d+)\s*\/([^\s\/\[\]{}()<>]+)\s+put/g;
		var pos = 0;
		while (re.matchSub(clear, pos)) {
			encoding.set(Std.parseInt(re.matched(1)), re.matched(2));
			var p = re.matchedPos();
			pos = p.pos + p.len;
		}
		var fm = ~/\/FontMatrix\s*\[([^\]]*)\]/;
		if (fm.match(clear)) {
			var n = [for (x in ~/\s+/g.split(StringTools.trim(fm.matched(1)))) Std.parseFloat(x)];
			if (n.length == 6 && !Lambda.exists(n, x -> Math.isNaN(x))) fontMatrix = n;
		}
		var enc = data.sub(clearEnd, data.length - clearEnd);
		// (eexec in hex, or binary)
		if (enc.length >= 4 && isHex(enc)) enc = hexBytes(enc);
		var plain = decrypt(enc, 55665, 4);
		parsePrivate(plain);
	}

	static function pfb(d:Bytes):Bytes {
		var out = new BytesBuffer(), p = 0;
		while (p + 6 <= d.length && d.get(p) == 0x80) {
			var t = d.get(p + 1);
			if (t == 3) break;
			var len = d.get(p + 2) | (d.get(p + 3) << 8) | (d.get(p + 4) << 16) | (d.get(p + 5) << 24);
			p += 6;
			if (len < 0 || p + len > d.length) len = d.length - p;
			out.addBytes(d, p, len);
			p += len;
		}
		return out.getBytes();
	}

	// (where what occurs from at: by the bytes, the font being binary)
	static function find(d:Bytes, what:String, from:Int):Int {
		var n = what.length;
		var i = from < 0 ? 0 : from;
		while (i + n <= d.length) {
			if (d.get(i) == StringTools.fastCodeAt(what, 0)) {
				var ok = true;
				for (k in 1...n)
					if (d.get(i + k) != StringTools.fastCodeAt(what, k)) {
						ok = false;
						break;
					}
				if (ok) return i;
			}
			i++;
		}
		return -1;
	}

	static function findEexec(d:Bytes, length1:Int):Int {
		var i = find(d, "eexec", 0);
		if (i < 0) return length1 > 0 && length1 < d.length ? length1 : d.length;
		i += 5;
		while (i < d.length && Parser.isWhite(d.get(i)))
			i++;
		return i;
	}

	static function latin1(b:Bytes, at:Int, n:Int):String {
		var sb = new StringBuf();
		for (i in at...at + n) {
			var c = b.get(i);
			sb.addChar(c < 128 ? c : 32);
		}
		return sb.toString();
	}

	static function isHex(b:Bytes):Bool {
		for (i in 0...4) {
			var c = b.get(i);
			if (!((c >= "0".code && c <= "9".code) || (c >= "a".code && c <= "f".code) || (c >= "A".code && c <= "F".code))) return false;
		}
		return true;
	}

	static function hexBytes(b:Bytes):Bytes {
		var out = new BytesBuffer(), hi = -1;
		for (i in 0...b.length) {
			var c = b.get(i);
			var v = c >= "0".code && c <= "9".code ? c - 48 : c >= "a".code && c <= "f".code ? c - 87 : c >= "A".code && c <= "F".code ? c - 55 : -1;
			if (v < 0) continue;
			if (hi < 0) hi = v else {
				out.addByte(hi * 16 + v);
				hi = -1;
			}
		}
		return out.getBytes();
	}

	static function decrypt(b:Bytes, key:Int, skip:Int):Bytes {
		var r = key, out = Bytes.alloc(Std.int(Math.max(0, b.length - skip)));
		for (i in 0...b.length) {
			var c = b.get(i);
			var p = c ^ (r >> 8);
			r = ((c + r) * 52845 + 22719) & 0xFFFF;
			if (i >= skip) out.set(i - skip, p & 255);
		}
		return out;
	}

	// /lenIV, /Subrs (dup i n RD <n bytes> NP), /CharStrings (/name n RD <n bytes> ND)
	function parsePrivate(p:Bytes) {
		var lvAt = find(p, "/lenIV", 0);
		if (lvAt >= 0) {
			var lv = ~/\/lenIV\s+(-?\d+)/;
			if (lv.match(latin1(p, lvAt, Std.int(Math.min(24, p.length - lvAt))))) lenIV = Std.parseInt(lv.matched(1));
		}
		var i = 0, n = p.length;
		inline function readInt():Int {
			while (i < n && Parser.isWhite(p.get(i)))
				i++;
			var st = i;
			while (i < n && p.get(i) >= "0".code && p.get(i) <= "9".code)
				i++;
			return Std.parseInt(p.getString(st, i - st)) ?? -1;
		}
		inline function binary():Null<Bytes> {
			var len = readInt();
			// (RD or -|, one space, then the bytes)
			while (i < n && Parser.isWhite(p.get(i)))
				i++;
			while (i < n && !Parser.isWhite(p.get(i)))
				i++;
			i++;
			if (len < 0 || i + len > n) return null;
			var b = p.sub(i, len);
			i += len;
			return lenIV >= 0 ? decrypt(b, 4330, lenIV) : b;
		}
		var subrsAt = find(p, "/Subrs", 0);
		if (subrsAt >= 0) {
			i = subrsAt + 6;
			var count = readInt();
			for (_ in 0...Std.int(Math.max(0, Math.min(count, 65536)))) {
				var d = find(p, "dup", i);
				if (d < 0) break;
				var cs = find(p, "/CharStrings", i);
				if (cs >= 0 && cs < d) break;
				i = d + 3;
				var index = readInt();
				var b = binary();
				if (b == null || index < 0) break;
				subrs[index] = b;
			}
		}
		var csAt = find(p, "/CharStrings", 0);
		if (csAt < 0) return;
		i = csAt + 12;
		readInt();
		while (i < n) {
			var slash = find(p, "/", i);
			if (slash < 0) break;
			var e = slash + 1;
			while (e < n && !Parser.isWhite(p.get(e)) && !Parser.isDelim(p.get(e)))
				e++;
			var name = p.getString(slash + 1, e - slash - 1);
			i = e;
			var save = i;
			var b = binary();
			if (b == null) {
				i = save + 1;
				if (name == "Private") break;
				continue;
			}
			charStrings.set(name, b);
		}
	}

	public function has(name:String):Bool
		return charStrings.exists(name);

	// the glyph's outline into out through m (glyph units in), its advance in glyph units
	public function outline(name:String, out:helder.canvas.Path, m:helder.canvas.Matrix):Float {
		var cs = charStrings.get(name) ?? charStrings.get(".notdef");
		if (cs == null) return 0;
		var r = new Run(this, out, m);
		r.run(cs, 0);
		return r.width;
	}

	@:allow(helder.pdf.Run) function subr(i:Int):Null<Bytes>
		return i >= 0 && i < subrs.length ? subrs[i] : null;

	@:allow(helder.pdf.Run) function glyph(name:String):Null<Bytes>
		return charStrings.get(name);
}

// A charstring's run: the stack, the point, flex's points
@:allow(helder.pdf.Type1)
private class Run {
	final font:Type1;
	final out:helder.canvas.Path;
	final m:helder.canvas.Matrix;
	final s:Array<Float> = [];
	final ps:Array<Float> = [];
	var x = 0.0;
	var y = 0.0;
	var sbx = 0.0;
	var open = false;
	var flex = false;
	final flexPts:Array<Float> = [];
	public var width = 0.0;
	var ops = 0;
	var done = false;

	public function new(font, out, m) {
		this.font = font;
		this.out = out;
		this.m = m;
	}

	inline function mv(nx:Float, ny:Float) {
		if (flex) {
			flexPts.push(nx);
			flexPts.push(ny);
			x = nx;
			y = ny;
			return;
		}
		if (open) out.close();
		x = nx;
		y = ny;
		out.moveTo(m.mapX(x, y), m.mapY(x, y));
		open = true;
	}

	inline function ln(nx:Float, ny:Float) {
		x = nx;
		y = ny;
		out.lineTo(m.mapX(x, y), m.mapY(x, y));
	}

	inline function cv(x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float) {
		out.cubicTo(m.mapX(x1, y1), m.mapY(x1, y1), m.mapX(x2, y2), m.mapY(x2, y2), m.mapX(x3, y3), m.mapY(x3, y3));
		x = x3;
		y = y3;
	}

	public function run(b:Bytes, depth:Int) {
		if (depth > 10) return;
		var i = 0;
		while (i < b.length && !done) {
			if (++ops > 100000) return;
			var v = b.get(i++);
			if (v >= 32) {
				var n:Float;
				if (v <= 246) n = v - 139 else if (v <= 250) n = (v - 247) * 256 + (i < b.length ? b.get(i++) : 0) + 108 else if (v <= 254)
					n = -(v - 251) * 256 - (i < b.length ? b.get(i++) : 0) - 108 else {
					if (i + 4 > b.length) return;
					n = (b.get(i) << 24) | (b.get(i + 1) << 16) | (b.get(i + 2) << 8) | b.get(i + 3);
					i += 4;
				}
				s.push(n);
				continue;
			}
			inline function a(k:Int):Float
				return k < s.length ? s[k] : 0;
			switch v {
				case 13: // hsbw
					sbx = a(0);
					width = a(1);
					x = sbx;
					y = 0;
					s.resize(0);
				case 12:
					var e = i < b.length ? b.get(i++) : 0;
					switch e {
						case 7: // sbw
							sbx = a(0);
							x = a(0);
							y = a(1);
							width = a(2);
						case 6: // seac
							seac(a(1), a(2), Std.int(a(3)), Std.int(a(4)), depth);
							done = true;
						case 12: // div
							var d = s.pop(), n = s.pop();
							s.push(d == 0 ? 0 : n / d);
							continue;
						case 16: // callothersubr
							var k = Std.int(s.pop()), n = Std.int(s.pop());
							var args = [for (_ in 0...Std.int(Math.max(0, Math.min(n, s.length)))) s.pop()];
							args.reverse();
							othersubr(k, args);
							continue;
						case 17: // pop
							s.push(ps.length > 0 ? ps.pop() : 0);
							continue;
						case 33: // setcurrentpoint
							x = a(0);
							y = a(1);
						case _:
					}
					s.resize(0);
				case 21:
					mv(x + a(0), y + a(1));
					s.resize(0);
				case 22:
					mv(x + a(0), y);
					s.resize(0);
				case 4:
					mv(x, y + a(0));
					s.resize(0);
				case 5:
					ln(x + a(0), y + a(1));
					s.resize(0);
				case 6:
					ln(x + a(0), y);
					s.resize(0);
				case 7:
					ln(x, y + a(0));
					s.resize(0);
				case 8:
					var x1 = x + a(0), y1 = y + a(1), x2 = x1 + a(2), y2 = y1 + a(3);
					cv(x1, y1, x2, y2, x2 + a(4), y2 + a(5));
					s.resize(0);
				case 30: // vhcurveto
					var x1 = x, y1 = y + a(0), x2 = x1 + a(1), y2 = y1 + a(2);
					cv(x1, y1, x2, y2, x2 + a(3), y2);
					s.resize(0);
				case 31: // hvcurveto
					var x1 = x + a(0), y1 = y, x2 = x1 + a(1), y2 = y1 + a(2);
					cv(x1, y1, x2, y2, x2, y2 + a(3));
					s.resize(0);
				case 9:
					if (open) out.close();
					open = false;
					s.resize(0);
				case 10: // callsubr
					var k = Std.int(s.pop());
					var sub = font.subr(k);
					if (sub != null) run(sub, depth + 1);
				case 11:
					return;
				case 14:
					if (open) out.close();
					open = false;
					done = true;
					return;
				case _:
					s.resize(0);
			}
		}
	}

	// flex (0, 1, 2) and hint replacement (3: its subr pushed back)
	function othersubr(k:Int, args:Array<Float>) {
		switch k {
			case 1:
				flex = true;
				flexPts.resize(0);
			case 2:
			case 0:
				flex = false;
				// (the reference point then the six of the two curves)
				if (flexPts.length >= 14) {
					var p = flexPts;
					if (!open) {
						out.moveTo(m.mapX(p[0], p[1]), m.mapY(p[0], p[1]));
						open = true;
					}
					cv(p[2], p[3], p[4], p[5], p[6], p[7]);
					cv(p[8], p[9], p[10], p[11], p[12], p[13]);
				}
				ps.push(args.length > 2 ? args[2] : y);
				ps.push(args.length > 1 ? args[1] : x);
			case 3:
				ps.push(3);
			case _:
				for (i in 0...args.length)
					ps.push(args[args.length - 1 - i]);
		}
	}

	// an accented character: the base and the accent (StandardEncoding's codes) at (adx, ady) from the base
	function seac(adx:Float, ady:Float, base:Int, accent:Int, depth:Int) {
		var std = Encodings.standardEncoding();
		var bn = base >= 0 && base < 256 ? std[base] : null, an = accent >= 0 && accent < 256 ? std[accent] : null;
		var w = width;
		if (bn != null && font.glyph(bn) != null) {
			var r = new Run(font, out, m);
			r.run(font.glyph(bn), depth + 1);
		}
		if (an != null && font.glyph(an) != null) {
			var mm = m.clone().translate(adx - sbx, ady);
			var r = new Run(font, out, mm);
			r.run(font.glyph(an), depth + 1);
		}
		width = w;
	}
}
