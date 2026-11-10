package tables;

// JSON read with its objects' keys in order (a query's columns are its
// first row's keys): an object is a Record, an array an Array<Dynamic>,
// numbers Int while they are whole and fit, else Float
class Json {
	final s:String;
	var i = 0;

	function new(s:String)
		this.s = s;

	public static function parse(s:String):Dynamic {
		var p = new Json(s);
		var v = p.value();
		p.space();
		if (p.i < s.length) throw 'json: unexpected text at ${p.i}';
		return v;
	}

	// a value as one line of text: a string as it is, the rest as JSON
	public static function text(v:Dynamic):String {
		if (v == null) return "null";
		if (v is String) return v;
		var b = new StringBuf();
		write(b, v);
		return b.toString();
	}

	public static function stringify(v:Dynamic):String {
		var b = new StringBuf();
		write(b, v);
		return b.toString();
	}

	static function write(b:StringBuf, v:Dynamic) {
		if (v == null) b.add("null");
		else if (v is String) quote(b, v);
		else if (v is Bool) b.add(v ? "true" : "false");
		else if (v is Int) b.add(Std.string(v));
		else if (v is Float) {
			var f:Float = v;
			b.add(Math.isFinite(f) ? number(f) : "null");
		} else if (v is Record) {
			var r:Record = v;
			b.add("{");
			for (k in 0...r.keys.length) {
				if (k > 0) b.add(",");
				quote(b, r.keys[k]);
				b.add(":");
				write(b, r.values[k]);
			}
			b.add("}");
		} else if (v is Array) {
			var a:Array<Dynamic> = v;
			b.add("[");
			for (k in 0...a.length) {
				if (k > 0) b.add(",");
				write(b, a[k]);
			}
			b.add("]");
		} else quote(b, Std.string(v));
	}

	// (a float without a needless ".0")
	public static function number(f:Float):String {
		if (f == Math.ffloor(f) && Math.abs(f) < 1e15) return Std.string(haxe.Int64.fromFloat(f));
		return Std.string(f);
	}

	static function quote(b:StringBuf, s:String) {
		b.add('"');
		for (k in 0...s.length) {
			var c = StringTools.fastCodeAt(s, k);
			switch c {
				case '"'.code: b.add('\\"');
				case '\\'.code: b.add("\\\\");
				case '\n'.code: b.add("\\n");
				case '\r'.code: b.add("\\r");
				case '\t'.code: b.add("\\t");
				case _ if (c < 0x20): b.add("\\u" + StringTools.hex(c, 4));
				case _: b.addChar(c);
			}
		}
		b.add('"');
	}

	inline function at():Int
		return StringTools.fastCodeAt(s, i);

	function space()
		while (i < s.length) {
			var c = at();
			if (c != ' '.code && c != '\n'.code && c != '\r'.code && c != '\t'.code) break;
			i++;
		}

	function value():Dynamic {
		space();
		if (i >= s.length) throw "json: unexpected end";
		return switch at() {
			case '{'.code: object();
			case '['.code: array();
			case '"'.code: string();
			case 't'.code: word("true", true);
			case 'f'.code: word("false", false);
			case 'n'.code: word("null", null);
			case _: num();
		}
	}

	function word(w:String, v:Dynamic):Dynamic {
		if (s.substr(i, w.length) != w) throw 'json: bad literal at $i';
		i += w.length;
		return v;
	}

	function object():Record {
		i++;
		var r = new Record();
		space();
		if (at() == '}'.code) {
			i++;
			return r;
		}
		while (true) {
			space();
			var k = string();
			space();
			if (at() != ':'.code) throw 'json: ":" expected at $i';
			i++;
			r.keys.push(k);
			r.values.push(value());
			space();
			var c = at();
			i++;
			if (c == '}'.code) return r;
			if (c != ','.code) throw 'json: "," expected at ${i - 1}';
		}
	}

	function array():Array<Dynamic> {
		i++;
		var a:Array<Dynamic> = [];
		space();
		if (at() == ']'.code) {
			i++;
			return a;
		}
		while (true) {
			a.push(value());
			space();
			var c = at();
			i++;
			if (c == ']'.code) return a;
			if (c != ','.code) throw 'json: "," expected at ${i - 1}';
		}
	}

	function string():String {
		if (at() != '"'.code) throw 'json: string expected at $i';
		i++;
		var b:Null<StringBuf> = null, start = i;
		while (true) {
			if (i >= s.length) throw "json: unterminated string";
			var c = at();
			if (c == '"'.code) {
				var tail = s.substring(start, i);
				i++;
				if (b == null) return tail;
				b.add(tail);
				return b.toString();
			}
			if (c != '\\'.code) {
				i++;
				continue;
			}
			b ??= new StringBuf();
			b.add(s.substring(start, i));
			i++;
			var e = at();
			i++;
			switch e {
				case 'n'.code: b.add("\n");
				case 'r'.code: b.add("\r");
				case 't'.code: b.add("\t");
				case 'b'.code: b.add("\x08");
				case 'f'.code: b.add("\x0C");
				case 'u'.code:
					var code = Std.parseInt("0x" + s.substr(i, 4));
					i += 4;
					// (a surrogate pair: one character)
					if (code >= 0xD800 && code < 0xDC00 && s.substr(i, 2) == "\\u") {
						var low = Std.parseInt("0x" + s.substr(i + 2, 4));
						i += 6;
						code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
					}
					b.addChar(code);
				case _: b.addChar(e);
			}
			start = i;
		}
	}

	function num():Dynamic {
		var start = i, whole = true;
		while (i < s.length) {
			var c = at();
			if (c >= '0'.code && c <= '9'.code || c == '-'.code || c == '+'.code) i++;
			else if (c == '.'.code || c == 'e'.code || c == 'E'.code) {
				whole = false;
				i++;
			} else break;
		}
		if (i == start) throw 'json: unexpected "${s.charAt(i)}" at $i';
		var t = s.substring(start, i);
		if (whole && t.length < 10) return Std.parseInt(t);
		var f = Std.parseFloat(t);
		if (Math.isNaN(f)) throw 'json: bad number at $start';
		return f;
	}
}

// a JSON object: its keys in order
class Record {
	public final keys:Array<String> = [];
	public final values:Array<Dynamic> = [];

	public function new() {}

	public function set(key:String, value:Dynamic):Record {
		keys.push(key);
		values.push(value);
		return this;
	}

	public function get(key:String):Dynamic {
		var k = keys.indexOf(key);
		return k < 0 ? null : values[k];
	}
}
