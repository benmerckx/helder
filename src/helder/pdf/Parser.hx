package helder.pdf;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.pdf.PdfValue;

// PDF's syntax over bytes: whitespace and comments, numbers, literal and
// hex strings (their escapes), names (#xx), arrays, dictionaries, indirect
// references (n g R), keywords. Every read is bounded by the bytes' end
// and the nesting by PdfLimits.maxNesting: a hostile file ends in a
// PdfError, never a crash. Document reads objects with it, the content
// interpreter operands and operators (next: an operand, or null with
// keyword set).
class Parser {
	public final b:Bytes;
	public var pos:Int;
	public final end:Int;
	public var keyword(default, null):String = "";
	var depth = 0;
	final maxNesting:Int;

	public function new(b:Bytes, pos = 0, ?end:Int, maxNesting = 64) {
		this.b = b;
		this.pos = pos;
		this.end = end ?? b.length;
		this.maxNesting = maxNesting;
	}

	public inline function at(p:Int):Int
		return p < end && p >= 0 ? b.get(p) : -1;

	public static inline function isWhite(c:Int):Bool
		return c == 32 || c == 10 || c == 13 || c == 9 || c == 12 || c == 0;

	public static inline function isDelim(c:Int):Bool
		return c == "(".code || c == ")".code || c == "<".code || c == ">".code || c == "[".code || c == "]".code || c == "{".code || c == "}".code
			|| c == "/".code || c == "%".code;

	public function skip() {
		while (pos < end) {
			var c = b.get(pos);
			if (isWhite(c)) pos++ else if (c == "%".code) {
				while (pos < end && b.get(pos) != 10 && b.get(pos) != 13)
					pos++;
			} else
				break;
		}
	}

	// a regular token's characters from pos
	function word():String {
		var s = pos;
		while (pos < end && !isWhite(b.get(pos)) && !isDelim(b.get(pos)))
			pos++;
		return b.getString(s, pos - s);
	}

	// the next value, with references (n g R) read whole; at a keyword: null, keyword set
	public function next():Null<PdfValue> {
		skip();
		if (pos >= end) {
			keyword = "";
			return null;
		}
		var c = b.get(pos);
		switch c {
			case "/".code:
				pos++;
				var s = pos;
				while (pos < end && !isWhite(b.get(pos)) && !isDelim(b.get(pos)))
					pos++;
				var raw = b.getString(s, pos - s);
				return PName(raw.indexOf("#") >= 0 ? unescapeName(raw) : raw);
			case "(".code:
				return PStr(literal());
			case "<".code:
				if (at(pos + 1) == "<".code) {
					pos += 2;
					return PDict(dict());
				}
				return PStr(hex());
			case "[".code:
				pos++;
				nest();
				var a = [];
				while (true) {
					skip();
					if (pos >= end) throw PdfError.corrupt("an array not closed");
					if (b.get(pos) == "]".code) {
						pos++;
						break;
					}
					var v = next();
					if (v == null) {
						// (a keyword inside an array: true, false, null, or a stray one taken as null)
						a.push(PNull);
						continue;
					}
					a.push(v);
				}
				depth--;
				return PArray(a);
			case "]".code | ">".code | ")".code | "{".code | "}".code:
				pos++;
				keyword = String.fromCharCode(c);
				return null;
			case _:
		}
		if ((c >= "0".code && c <= "9".code) || c == "-".code || c == "+".code || c == ".".code) {
			var n = number();
			// (an integer followed by another and R: a reference)
			if (n >= 0 && n == Math.ffloor(n)) {
				var save = pos;
				skip();
				var p2 = pos;
				if (p2 < end && b.get(p2) >= "0".code && b.get(p2) <= "9".code) {
					var g = number();
					skip();
					if (at(pos) == "R".code && (pos + 1 >= end || isWhite(b.get(pos + 1)) || isDelim(b.get(pos + 1)))) {
						pos++;
						return PRef(Std.int(n), Std.int(g));
					}
				}
				pos = save;
			}
			return PNum(n);
		}
		var w = word();
		if (w == "") {
			pos++;
			keyword = "";
			return null;
		}
		switch w {
			case "true":
				return PBool(true);
			case "false":
				return PBool(false);
			case "null":
				return PNull;
			case _:
				keyword = w;
				return null;
		}
	}

	inline function nest() {
		if (++depth > maxNesting) throw PdfError.corrupt("objects nested past " + maxNesting);
	}

	function dict():PdfDict {
		nest();
		var d = new PdfDict();
		while (true) {
			skip();
			if (pos >= end) throw PdfError.corrupt("a dictionary not closed");
			if (b.get(pos) == ">".code) {
				pos += at(pos + 1) == ">".code ? 2 : 1;
				break;
			}
			var k = next();
			switch k {
				case PName(name):
					var v = next();
					d.set(name, v ?? PNull);
				case null:
					if (keyword == "") throw PdfError.corrupt("a dictionary not closed");
				case _:
			}
		}
		depth--;
		return d;
	}

	public function number():Float {
		var s = pos;
		if (pos < end && (b.get(pos) == "-".code || b.get(pos) == "+".code)) pos++;
		while (pos < end && ((b.get(pos) >= "0".code && b.get(pos) <= "9".code) || b.get(pos) == ".".code))
			pos++;
		// (stray signs as in "--5" or "4-": what is a number of it)
		var t = b.getString(s, pos - s);
		while (pos < end && (b.get(pos) == "-".code))
			pos++;
		var f = Std.parseFloat(t);
		return Math.isNaN(f) ? 0 : f;
	}

	function literal():Bytes {
		pos++;
		var out = new BytesBuffer(), level = 1;
		while (pos < end) {
			var c = b.get(pos++);
			if (c == "\\".code) {
				if (pos >= end) break;
				var e = b.get(pos++);
				switch e {
					case "n".code: out.addByte(10);
					case "r".code: out.addByte(13);
					case "t".code: out.addByte(9);
					case "b".code: out.addByte(8);
					case "f".code: out.addByte(12);
					case 13:
						if (at(pos) == 10) pos++;
					case 10:
					case _ if (e >= "0".code && e <= "7".code):
						var v = e - "0".code;
						for (_ in 0...2)
							if (at(pos) >= "0".code && at(pos) <= "7".code) v = v * 8 + (b.get(pos++) - "0".code);
						out.addByte(v & 255);
					case _:
						out.addByte(e);
				}
			} else if (c == "(".code) {
				level++;
				out.addByte(c);
			} else if (c == ")".code) {
				if (--level == 0) break;
				out.addByte(c);
			} else
				out.addByte(c);
		}
		return out.getBytes();
	}

	function hex():Bytes {
		pos++;
		var out = new BytesBuffer(), hi = -1;
		while (pos < end) {
			var c = b.get(pos++);
			if (c == ">".code) break;
			var v = c >= "0".code && c <= "9".code ? c - "0".code : c >= "a".code && c <= "f".code ? c - "a".code + 10 : c >= "A".code
				&& c <= "F".code ? c - "A".code + 10 : -1;
			if (v < 0) continue;
			if (hi < 0) hi = v else {
				out.addByte(hi * 16 + v);
				hi = -1;
			}
		}
		if (hi >= 0) out.addByte(hi * 16);
		return out.getBytes();
	}

	static function unescapeName(s:String):String {
		var out = new BytesBuffer(), i = 0;
		while (i < s.length) {
			var c = StringTools.fastCodeAt(s, i);
			if (c == "#".code && i + 2 < s.length + 0) {
				var v = Std.parseInt("0x" + s.substr(i + 1, 2));
				if (v != null) {
					out.addByte(v);
					i += 3;
					continue;
				}
			}
			out.addByte(c & 255);
			i++;
		}
		return out.getBytes().toString();
	}
}
