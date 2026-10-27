package helder.test;

import haxe.Constraints.IMap;
import haxe.io.Bytes;

// Deep equality, as `equals` compares: numbers by value (1 == 1.0), strings,
// arrays and lists by element, maps by key, anonymous structures and
// instances of the same class by field, enums by constructor and arguments,
// Bytes by content, Dates by time, functions by reference; and values shown
// as Haxe literals in failures.
class Equal {
	// where a and b first differ ("" at the top, "[2].name" inside), null if equal
	public static function diff(a:Dynamic, b:Dynamic):Null<String>
		return walk(a, b, "", 0);

	static function walk(a:Dynamic, b:Dynamic, at:String, depth:Int):Null<String> {
		if (a == b) return null;
		if (a == null || b == null || depth > 64) return at;
		switch [Type.typeof(a), Type.typeof(b)] {
			case [TInt | TFloat, TInt | TFloat]:
				var x:Float = a, y:Float = b;
				return x == y || (Math.isNaN(x) && Math.isNaN(y)) ? null : at;
			case [TEnum(e), TEnum(f)]:
				if (e != f || Type.enumIndex(a) != Type.enumIndex(b)) return at;
				var p = Type.enumParameters(a), q = Type.enumParameters(b);
				for (i in 0...p.length) {
					var d = walk(p[i], q[i], '$at(${Type.enumConstructor(a)} #$i)', depth + 1);
					if (d != null) return d;
				}
				return null;
			case [TObject, TObject]:
				return fields(a, b, at, depth);
			case [TClass(c), TClass(d)]:
				if (c != d) return at;
				if (a is String) return at;
				if (a is Array) {
					var x:Array<Dynamic> = a, y:Array<Dynamic> = b;
					for (i in 0...Std.int(Math.min(x.length, y.length))) {
						var r = walk(x[i], y[i], '$at[$i]', depth + 1);
						if (r != null) return r;
					}
					return x.length == y.length ? null : '$at.length';
				}
				if (a is Bytes) return (a : Bytes).compare(b) == 0 ? null : at;
				if (a is Date) return (a : Date).getTime() == (b : Date).getTime() ? null : at;
				if (a is List) return walk(Lambda.array(a), Lambda.array(b), at, depth);
				if (a is IMap) {
					var x:IMap<Dynamic, Dynamic> = a, y:IMap<Dynamic, Dynamic> = b;
					for (k in x.keys()) {
						if (!y.exists(k)) return '$at[${show(k)}]';
						var r = walk(x.get(k), y.get(k), '$at[${show(k)}]', depth + 1);
						if (r != null) return r;
					}
					for (k in y.keys())
						if (!x.exists(k)) return '$at[${show(k)}]';
					return null;
				}
				return fields(a, b, at, depth);
			case [TFunction, TFunction]:
				return Reflect.compareMethods(a, b) ? null : at;
			case _:
				return at;
		}
	}

	static function fields(a:Dynamic, b:Dynamic, at:String, depth:Int):Null<String> {
		var fa = Reflect.fields(a), fb = Reflect.fields(b);
		for (f in fa) {
			if (!Reflect.hasField(b, f)) return '$at.$f';
			var r = walk(Reflect.field(a, f), Reflect.field(b, f), '$at.$f', depth + 1);
			if (r != null) return r;
		}
		for (f in fb)
			if (!Reflect.hasField(a, f)) return '$at.$f';
		return null;
	}

	// v as a literal: strings quoted, structures' fields sorted (long values cut)
	public static function show(v:Dynamic):String {
		var s = new StringBuf();
		write(s, v, 0);
		var out = s.toString();
		return out.length > 2000 ? out.substr(0, 2000) + "..." : out;
	}

	static function write(s:StringBuf, v:Dynamic, depth:Int) {
		if (depth > 8) {
			s.add("...");
			return;
		}
		switch Type.typeof(v) {
			case TNull:
				s.add("null");
			case TEnum(_):
				s.add(Type.enumConstructor(v));
				var p = Type.enumParameters(v);
				if (p.length > 0) {
					s.add("(");
					list(s, p, depth);
					s.add(")");
				}
			case TObject:
				object(s, v, depth);
			case TClass(String):
				s.add(quote(v));
			case TClass(_) if (v is Array):
				s.add("[");
				list(s, v, depth);
				s.add("]");
			case TClass(_) if (v is Bytes):
				var b:Bytes = v;
				s.add('Bytes(${b.length}: ');
				s.add(b.length > 64 ? b.sub(0, 64).toHex() + "..." : b.toHex());
				s.add(")");
			case TClass(_) if (v is IMap):
				var m:IMap<Dynamic, Dynamic> = v;
				var keys = [for (k in m.keys()) k];
				keys.sort((x, y) -> Reflect.compare(Std.string(x), Std.string(y)));
				s.add("[");
				for (i => k in keys) {
					if (i > 0) s.add(", ");
					write(s, k, depth + 1);
					s.add(" => ");
					write(s, m.get(k), depth + 1);
				}
				s.add(keys.length == 0 ? "=>]" : "]");
			case TClass(_) if (v is Date || v is List):
				s.add(Std.string(v));
			case TClass(c):
				s.add(Type.getClassName(c));
				object(s, v, depth);
			case _:
				s.add(Std.string(v));
		}
	}

	static function list(s:StringBuf, a:Array<Dynamic>, depth:Int)
		for (i => x in a) {
			if (i > 0) s.add(", ");
			write(s, x, depth + 1);
		}

	static function object(s:StringBuf, v:Dynamic, depth:Int) {
		var fs = Reflect.fields(v);
		fs.sort(Reflect.compare);
		s.add("{");
		for (i => f in fs) {
			s.add(i > 0 ? ", " : "");
			s.add(f + ": ");
			write(s, Reflect.field(v, f), depth + 1);
		}
		s.add("}");
	}

	static function quote(v:String):String {
		var s = new StringBuf();
		s.add('"');
		for (i in 0...v.length) {
			var c = StringTools.fastCodeAt(v, i);
			switch c {
				case '"'.code: s.add('\\"');
				case '\\'.code: s.add("\\\\");
				case '\n'.code: s.add("\\n");
				case '\r'.code: s.add("\\r");
				case '\t'.code: s.add("\\t");
				case _: s.addChar(c);
			}
		}
		s.add('"');
		return s.toString();
	}
}
