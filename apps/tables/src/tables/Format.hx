package tables;

import tables.Table.Column;

// a value as a cell shows it and back from what was typed: Drizzle's
// timestamps (seconds or milliseconds) as UTC dates, its booleans as true
// and false, numbers as numbers, objects as JSON
class Format {
	public static function text(c:Column, v:Dynamic):Null<String> {
		if (v == null) return null;
		switch c.mode {
			case "timestamp" | "timestamp_ms" if (v is Float || v is Int):
				var s:Float = v;
				return date(c.mode == "timestamp_ms" ? s / 1000 : s);
			case "boolean" if (v is Float || v is Int || v is Bool):
				return v == true || v == 1 ? "true" : "false";
			case _:
		}
		if (v is String) return v;
		if (v is Bool) return v ? "true" : "false";
		if (v is Int) return Std.string(v);
		if (v is Float) return Json.number(v);
		return Json.stringify(v);
	}

	// what was typed as the column's value (null: NULL); an error when it is not one
	public static function parse(c:Column, s:String):Dynamic {
		var t = StringTools.trim(s);
		switch c.mode {
			case "timestamp" | "timestamp_ms":
				if (t == "") return null;
				var secs = seconds(t);
				if (secs == null) throw 'Not a date: $t (2024-05-06 13:42:25)';
				return c.mode == "timestamp_ms" ? secs * 1000 : secs;
			case "boolean":
				return switch t.toLowerCase() {
					case "true" | "1" | "yes": true;
					case "false" | "0" | "no": false;
					case "": null;
					case _: throw 'Not a boolean: $t';
				}
			case _:
		}
		if (c.numeric) {
			if (t == "") return null;
			var i = Std.parseInt(t);
			if (i != null && Std.string(i) == t) return i;
			var f = Std.parseFloat(t);
			if (Math.isNaN(f)) throw 'Not a number: $t';
			return f;
		}
		return s;
	}

	// seconds since 1970 as "2024-05-06 13:42:25" (UTC)
	public static function date(secs:Float):String {
		var s = Math.ffloor(secs), days = Math.floor(s / 86400), rest = Std.int(s - days * 86400.0);
		// (Howard Hinnant's civil_from_days)
		var z = days + 719468, era = Math.floor(z / 146097), doe = z - era * 146097;
		var yoe = Std.int((doe - Std.int(doe / 1460) + Std.int(doe / 36524) - Std.int(doe / 146096)) / 365);
		var y = yoe + era * 400, doy = doe - (365 * yoe + Std.int(yoe / 4) - Std.int(yoe / 100)), mp = Std.int((5 * doy + 2) / 153);
		var d = doy - Std.int((153 * mp + 2) / 5) + 1, m = mp < 10 ? mp + 3 : mp - 9;
		if (m <= 2) y++;
		return '$y-${two(m)}-${two(d)} ${two(Std.int(rest / 3600))}:${two(Std.int(rest / 60) % 60)}:${two(rest % 60)}';
	}

	// "2024-05-06", "2024-05-06 13:42" or "2024-05-06T13:42:25" (UTC) as seconds since 1970
	public static function seconds(t:String):Null<Float> {
		var r = ~/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?Z?$/;
		if (!r.match(t)) return null;
		var y = Std.parseInt(r.matched(1)), m = Std.parseInt(r.matched(2)), d = Std.parseInt(r.matched(3));
		function part(k:Int):Int {
			var v = r.matched(k);
			return v == null ? 0 : Std.parseInt(v);
		}
		// (days_from_civil)
		if (m <= 2) y--;
		var era = Math.floor(y / 400), yoe = y - era * 400;
		var doy = Std.int((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + d - 1;
		var doe = yoe * 365 + Std.int(yoe / 4) - Std.int(yoe / 100) + doy;
		var days = era * 146097.0 + doe - 719468;
		return days * 86400 + part(4) * 3600 + part(5) * 60 + part(6);
	}

	static inline function two(n:Int):String
		return n < 10 ? "0" + n : Std.string(n);

	// a count with thousands' commas
	public static function count(n:Int):String {
		var s = Std.string(n), out = "";
		while (s.length > 3) {
			out = "," + s.substr(s.length - 3) + out;
			s = s.substr(0, s.length - 3);
		}
		return s + out;
	}
}
