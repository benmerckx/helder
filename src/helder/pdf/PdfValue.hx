package helder.pdf;

import haxe.io.Bytes;

// A PDF object as read: null, a boolean, a number, a string (its bytes), a
// name, an array, a dictionary, a reference to an indirect object, a stream
// (its dictionary and its bytes as in the file: Document.stream decodes)
enum PdfValue {
	PNull;
	PBool(b:Bool);
	PNum(n:Float);
	PStr(b:Bytes);
	PName(n:String);
	PArray(a:Array<PdfValue>);
	PDict(d:PdfDict);
	PRef(num:Int, gen:Int);
	PStream(d:PdfDict, data:Bytes);
}

// A dictionary: its keys (names, without the slash) in the order read
class PdfDict {
	public final map = new Map<String, PdfValue>();

	public function new() {}

	public inline function get(k:String):PdfValue
		return map.exists(k) ? map.get(k) : PNull;

	public inline function has(k:String):Bool
		return map.exists(k);

	public inline function set(k:String, v:PdfValue)
		map.set(k, v);
}

class Values {
	public static function num(v:PdfValue, def = 0.0):Float
		return v == null ? def : switch v {
			case PNum(n): n;
			case _: def;
		}

	public static function int(v:PdfValue, def = 0):Int
		return v == null ? def : switch v {
			case PNum(n): Math.isFinite(n) ? Std.int(n) : def;
			case _: def;
		}

	public static function name(v:PdfValue, ?def:String):Null<String>
		return v == null ? def : switch v {
			case PName(n): n;
			case _: def;
		}

	public static function bool(v:PdfValue, def = false):Bool
		return v == null ? def : switch v {
			case PBool(b): b;
			case _: def;
		}

	public static function str(v:PdfValue):Null<Bytes>
		return v == null ? null : switch v {
			case PStr(b): b;
			case _: null;
		}

	public static function arr(v:PdfValue):Null<Array<PdfValue>>
		return v == null ? null : switch v {
			case PArray(a): a;
			case _: null;
		}

	public static function dict(v:PdfValue):Null<PdfDict>
		return v == null ? null : switch v {
			case PDict(d): d;
			case PStream(d, _): d;
			case _: null;
		}

	public static function nums(v:PdfValue):Null<Array<Float>> {
		var a = arr(v);
		if (a != null) for (x in a) if (x == null) return null;
		if (a == null) return null;
		return [for (x in a) num(x)];
	}
}
