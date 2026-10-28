package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Lib.*;

class JsDate extends JsObject {
	public var time:Float;
	override public function tag():String return "Date";
}

// Date: the specification's time arithmetic (exact in UTC); local time uses
// the host's timezone offset for each instant.
class Dates {
	public static var DateProto:JsObject;
	static inline var msPerDay = 86400000.0;
	static var dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
	static var monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
	static function day(t:Float):Float return Math.ffloor(t / msPerDay);

	static function timeWithinDay(t:Float):Float {
		var r = t % msPerDay;
		return r < 0 ? r + msPerDay : r;
	}

	static function daysInYear(y:Float):Float return (y % 4 != 0) ? 365 : (y % 100 != 0) ? 366 : (y % 400 != 0) ? 365 : 366;

	static function dayFromYear(y:Float):Float return 365 * (y - 1970) + Math.ffloor((y - 1969) / 4) - Math.ffloor((y - 1901) / 100) + Math.ffloor((y - 1601) / 400);

	static function yearFromTime(t:Float):Float {
		var y = Math.ffloor(day(t) / 365.2425) + 1970;
		while (dayFromYear(y) * msPerDay > t) y--;
		while (dayFromYear(y + 1) * msPerDay <= t) y++;
		return y;
	}

	static function inLeapYear(t:Float):Int return daysInYear(yearFromTime(t)) == 366 ? 1 : 0;

	static function dayWithinYear(t:Float):Float return day(t) - dayFromYear(yearFromTime(t));
	static var monthStarts = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365];
	static function monthFromTime(t:Float):Int {
		var d = dayWithinYear(t);
		var leap = inLeapYear(t);
		for (m in 0...12) {
			var end = monthStarts[m + 1] + (m >= 1 ? leap : 0);
			if (d < end) return m;
		}
		return 11;
	}

	static function dateFromTime(t:Float):Float {
		var m = monthFromTime(t);
		return dayWithinYear(t) - monthStarts[m] - (m >= 2 ? inLeapYear(t) : 0) + 1;
	}

	static function weekDay(t:Float):Int {
		var r = (day(t) + 4) % 7;
		return Std.int(r < 0 ? r + 7 : r);
	}

	static function hourFromTime(t:Float):Int return Std.int(Math.ffloor(timeWithinDay(t) / 3600000));

	static function minFromTime(t:Float):Int return Std.int(Math.ffloor(timeWithinDay(t) / 60000) % 60);

	static function secFromTime(t:Float):Int return Std.int(Math.ffloor(timeWithinDay(t) / 1000) % 60);

	static function msFromTime(t:Float):Int return Std.int(timeWithinDay(t) % 1000);

	static function makeTime(h:Float, m:Float, s:Float, ms:Float):Float {
		if (!Math.isFinite(h) || !Math.isFinite(m) || !Math.isFinite(s) || !Math.isFinite(ms)) return Math.NaN;
		return trunc(h) * 3600000 + trunc(m) * 60000 + trunc(s) * 1000 + trunc(ms);
	}

	static function trunc(v:Float):Float return v < 0 ? Math.fceil(v) : Math.ffloor(v);

	static function makeDay(year:Float, month:Float, date:Float):Float {
		if (!Math.isFinite(year) || !Math.isFinite(month) || !Math.isFinite(date)) return Math.NaN;
		var y = trunc(year), m = trunc(month), dt = trunc(date);
		var ym = y + Math.ffloor(m / 12);
		var mn = m % 12;
		if (mn < 0) mn += 12;
		if (Math.abs(ym) > 400000) return Math.NaN;
		var t = dayFromYear(ym) + monthStarts[Std.int(mn)] + (mn >= 2 && daysInYear(ym) == 366 ? 1 : 0);
		return t + dt - 1;
	}

	static function makeDate(d:Float, t:Float):Float return !Math.isFinite(d) || !Math.isFinite(t) ? Math.NaN : d * msPerDay + t;

	static function timeClip(t:Float):Float return !Math.isFinite(t) || Math.abs(t) > 8.64e15 ? Math.NaN : trunc(t) + 0;

	// (local time minus UTC, in ms, at UTC instant t)
	static function offsetAt(t:Float):Float {
		if (!Math.isFinite(t)) return 0;
		var clamped = Math.max(-8.64e15, Math.min(t, 8.64e15));
		return -Date.fromTime(clamped).getTimezoneOffset() * 60000.0;
	}

	static function localTime(t:Float):Float return t + offsetAt(t);

	static function utc(local:Float):Float {
		if (!Math.isFinite(local)) return Math.NaN;
		var guess = local - offsetAt(local);
		return local - offsetAt(guess);
	}

	public static function now():Float return Math.ffloor(Date.now().getTime());

	static function pad(v:Float, n:Int):String {
		var s = Std.string(Std.int(Math.abs(v)));
		while (s.length < n) s = "0" + s;
		return s;
	}

	static function year(y:Float):String return y >= 0 ? pad(y, 4) : "-" + pad(-y, 6);

	public static function iso(t:Float):String {
		var y = yearFromTime(t);
		var ys = y >= 0 && y <= 9999 ? pad(y, 4) : (y < 0 ? "-" : "+") + pad(Math.abs(y), 6);
		return ys + "-" + pad(monthFromTime(t) + 1, 2) + "-" + pad(dateFromTime(t), 2) + "T" + pad(hourFromTime(t), 2) + ":" + pad(minFromTime(t), 2) + ":" + pad(secFromTime(t), 2) + "." + pad(msFromTime(t), 3) + "Z";
	}

	static function zone(t:Float):String {
		var off = offsetAt(t) / 60000;
		var sign = off < 0 ? "-" : "+";
		var a = Math.abs(off);
		return "GMT" + sign + pad(Math.ffloor(a / 60), 2) + pad(a % 60, 2);
	}

	static function zoneName(t:Float):String return offsetAt(t) == 0 ? "Coordinated Universal Time" : zone(t);

	static function dateString(t:Float):String {
		var l = localTime(t);
		return dayNames[weekDay(l)] + " " + monthNames[monthFromTime(l)] + " " + pad(dateFromTime(l), 2) + " " + year(yearFromTime(l));
	}

	static function timeString(t:Float):String {
		var l = localTime(t);
		return pad(hourFromTime(l), 2) + ":" + pad(minFromTime(l), 2) + ":" + pad(secFromTime(l), 2) + " " + zone(t) + " (" + zoneName(t) + ")";
	}

	static function localeDate(t:Float):String {
		var l = localTime(t);
		return (monthFromTime(l) + 1) + "/" + Std.int(dateFromTime(l)) + "/" + Std.int(yearFromTime(l));
	}

	static function localeTime(t:Float):String {
		var l = localTime(t);
		var h = hourFromTime(l);
		return (h % 12 == 0 ? 12 : h % 12) + ":" + pad(minFromTime(l), 2) + ":" + pad(secFromTime(l), 2) + " " + (h < 12 ? "AM" : "PM");
	}

	// Date.parse: ISO strings (date-only forms are UTC, date-times without a
	// zone local), and the toString/toUTCString forms and similar.
	public static function parse(s:String):Float {
		s = StringTools.trim(s);
		var iso = parseIso(s);
		if (iso != null) return iso;
		return parseLoose(s);
	}

	static function digits(s:String, i:Int, n:Int):Int {
		if (i + n > s.length) return -1;
		var v = 0;
		for (k in 0...n) {
			var c = s.charCodeAt(i + k);
			if (c < 48 || c > 57) return -1;
			v = v * 10 + c - 48;
		}
		return v;
	}

	static function parseIso(s:String):Null<Float> {
		var i = 0;
		var y:Float;
		if (s.charAt(0) == "+" || s.charAt(0) == "-") {
			var v = digits(s, 1, 6);
			if (v < 0) return null;
			y = s.charAt(0) == "-" ? -v : v;
			if (s.charAt(0) == "-" && v == 0) return Math.NaN;
			i = 7;
		}
		else {
			var v = digits(s, 0, 4);
			if (v < 0) return null;
			y = v;
			i = 4;
		}
		var mo = 1, d = 1, h = 0, mi = 0, sec = 0, ms = 0.0;
		var dateOnly = true;
		var offset:Null<Float> = null;
		if (s.charAt(i) == "-") {
			mo = digits(s, i + 1, 2);
			if (mo < 0) return null;
			i += 3;
			if (s.charAt(i) == "-") {
				d = digits(s, i + 1, 2);
				if (d < 0) return null;
				i += 3;
			}
		}
		if (s.charAt(i) == "T" || s.charAt(i) == "t" || s.charAt(i) == " " && i < s.length - 1) {
			dateOnly = false;
			h = digits(s, i + 1, 2);
			mi = digits(s, i + 4, 2);
			if (h < 0 || mi < 0 || s.charAt(i + 3) != ":") return null;
			i += 6;
			if (s.charAt(i) == ":") {
				sec = digits(s, i + 1, 2);
				if (sec < 0) return null;
				i += 3;
				if (s.charAt(i) == "." || s.charAt(i) == ",") {
					var start = i + 1;
					i++;
					while (i < s.length && s.charCodeAt(i) >= 48 && s.charCodeAt(i) <= 57) i++;
					var frac = s.substring(start, i);
					if (frac == "") return null;
					ms = Math.ffloor(Std.parseFloat("0." + frac) * 1000 + 1e-9);
				}
			}
			if (s.charAt(i) == "Z" || s.charAt(i) == "z") {
				offset = 0;
				i++;
			}
			else if (s.charAt(i) == "+" || s.charAt(i) == "-") {
				var oh = digits(s, i + 1, 2);
				var om = s.charAt(i + 3) == ":" ? digits(s, i + 4, 2) : digits(s, i + 3, 2);
				if (oh < 0 || om < 0) return null;
				offset = (s.charAt(i) == "-" ? -1 : 1) * (oh * 60 + om) * 60000.0;
				i += s.charAt(i + 3) == ":" ? 6 : 5;
			}
		}
		if (i != s.length) return null;
		if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 24 || mi > 59 || sec > 59 || h == 24 && (mi > 0 || sec > 0 || ms > 0)) return Math.NaN;
		var t = makeDate(makeDay(y, mo - 1, d), makeTime(h, mi, sec, ms));
		if (dateOnly) return timeClip(t);
		return timeClip(offset != null ? t - offset : utc(t));
	}

	static function parseLoose(s:String):Float {
		var words = [for (w in s.split(" ")) if (w != "") w];
		var month = -1, d = -1.0, y = Math.NaN, h = 0.0, mi = 0.0, sec = 0.0;
		var offset:Null<Float> = null;
		for (w in words) {
			var clean = StringTools.replace(w, ",", "");
			var lower = clean.toLowerCase();
			var m = -1;
			for (k in 0...12) if (lower.length >= 3 && monthNames[k].toLowerCase() == lower.substr(0, 3)) m = k;
			if (m >= 0) {
				month = m;
				continue;
			}
			if (clean.indexOf(":") > 0) {
				var parts = clean.split(":");
				h = Std.parseFloat(parts[0]);
				mi = Std.parseFloat(parts[1]);
				if (parts.length > 2) sec = Std.parseFloat(parts[2]);
				continue;
			}
			if (lower == "pm" && h < 12) {
				h += 12;
				continue;
			}
			if (lower == "am") {
				if (h == 12) h = 0;
				continue;
			}
			if (StringTools.startsWith(clean, "GMT") || StringTools.startsWith(clean, "UTC") || clean == "Z") {
				var rest = clean.substr(clean == "Z" ? 1 : 3);
				offset = 0;
				if (rest.length >= 5) {
					var sign = rest.charAt(0) == "-" ? -1 : 1;
					offset = sign * (Std.parseFloat(rest.substr(1, 2)) * 60 + Std.parseFloat(rest.substr(rest.charAt(3) == ":" ? 4 : 3, 2))) * 60000;
				}
				continue;
			}
			if (StringTools.startsWith(clean, "(")) break;
			var slash = clean.split("/");
			if (slash.length == 3) {
				month = Std.parseInt(slash[0]) - 1;
				d = Std.parseFloat(slash[1]);
				y = Std.parseFloat(slash[2]);
				continue;
			}
			var n = Std.parseFloat(clean);
			if (Math.isNaN(n)) {
				if (dayNames.indexOf(clean.substr(0, 3)) >= 0) continue;
				return Math.NaN;
			}
			if (d < 0 && n <= 31 && clean.length <= 2) d = n; else y = n;
		}
		if (month < 0 || d < 0 || Math.isNaN(y)) return Math.NaN;
		var t = makeDate(makeDay(y, month, d), makeTime(h, mi, sec, 0));
		return timeClip(offset != null ? t - offset : utc(t));
	}

	static function thisTime(t:Dynamic):Float {
		if (!Std.isOfType(t, JsDate)) error("TypeError", "this is not a Date object.");
		return (t : JsDate).time;
	}

	public static function make(time:Float):JsDate {
		var d = new JsDate(DateProto);
		d.time = time;
		return d;
	}

	public static function setup():Void {
		DateProto = new JsObject(Builtins.ObjectProto);
		var ctor:JsFunction = null;
		ctor = Builtins.nativeFunction("Date", 7, (_, a, nt) -> {
			if (nt == undef()) return (dateString(now()) + " " + timeString(now()) : Dynamic);
			var t:Float;
			if (a.length == 0) t = now();
			else if (a.length == 1) {
				var v = arg(a, 0);
				if (Std.isOfType(v, JsDate)) t = (v : JsDate).time;
				else {
					var p = toPrimitive(v, "default");
					t = Std.isOfType(p, String) ? parse(p) : timeClip(Seed.numeric(p));
				}
			}
			else {
				var nums = [for (x in a) Seed.numeric(x)];
				var y = nums[0];
				if (!Math.isNaN(y)) {
					var yi = trunc(y);
					if (yi >= 0 && yi <= 99) y = 1900 + yi;
				}
				var finalDate = makeDate(makeDay(y, nums[1], a.length > 2 ? nums[2] : 1), makeTime(a.length > 3 ? nums[3] : 0, a.length > 4 ? nums[4] : 0, a.length > 5 ? nums[5] : 0, a.length > 6 ? nums[6] : 0));
				t = timeClip(utc(finalDate));
			}
			var d = make(t);
			d.proto = protoFrom(nt, DateProto);
			return d;
		}, true);
		ctor.setOwn("prototype", DateProto, Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);
		DateProto.setOwn("constructor", ctor, Attr.HIDDEN);
		Builtins.globals.set("Date", ctor);
		(Builtins.globals.get("globalThis") : JsObject).setOwn("Date", ctor, Attr.HIDDEN);
		function method(target:JsObject, name:String, arity:Int, fn:(Dynamic, Array<Dynamic>, Dynamic) -> Dynamic) target.setOwn(name, Builtins.nativeFunction(Symbols.functionName(name), arity, fn), Attr.HIDDEN);
		method(ctor, "now", 0, (_, _, _) -> now());
		method(ctor, "parse", 1, (_, a, _) -> parse(Seed.text(arg(a, 0))));
		method(ctor, "UTC", 7, (_, a, _) -> {
			var nums = [for (x in a) Seed.numeric(x)];
			var y = a.length > 0 ? nums[0] : Math.NaN;
			if (!Math.isNaN(y)) {
				var yi = trunc(y);
				if (yi >= 0 && yi <= 99) y = 1900 + yi;
			}
			return timeClip(makeDate(makeDay(y, a.length > 1 ? nums[1] : 0, a.length > 2 ? nums[2] : 1), makeTime(a.length > 3 ? nums[3] : 0, a.length > 4 ? nums[4] : 0, a.length > 5 ? nums[5] : 0, a.length > 6 ? nums[6] : 0)));
		});
		var p = DateProto;
		method(p, "getTime", 0, (t, _, _) -> thisTime(t));
		method(p, "valueOf", 0, (t, _, _) -> thisTime(t));
		method(p, "getTimezoneOffset", 0, (t, _, _) -> {
			var v = thisTime(t);
			return Math.isNaN(v) ? Math.NaN : -offsetAt(v) / 60000;});
		var parts:Array<{name:String, fn:Float->Float}> = [
			     {name: "FullYear", fn: yearFromTime}, {name: "Month", fn: t -> monthFromTime(t)},           {name: "Date", fn: dateFromTime},           {name: "Day", fn: t -> weekDay(t)},
			{name: "Hours", fn: t -> hourFromTime(t)}, {name: "Minutes", fn: t -> minFromTime(t)}, {name: "Seconds", fn: t -> secFromTime(t)}, {name: "Milliseconds", fn: t -> msFromTime(t)}
		];
		for (part in parts) {
			method(p, "get" + part.name, 0, (t, _, _) -> {
				var v = thisTime(t);
				return Math.isNaN(v) ? Math.NaN : part.fn(localTime(v));});
			method(p, "getUTC" + part.name, 0, (t, _, _) -> {
				var v = thisTime(t);
				return Math.isNaN(v) ? Math.NaN : part.fn(v);});
		}
		method(p, "getYear", 0, (t, _, _) -> {
			var v = thisTime(t);
			return Math.isNaN(v) ? Math.NaN : yearFromTime(localTime(v)) - 1900;});
		method(p, "setTime", 1, (t, a, _) -> {
			thisTime(t);
			var v = timeClip(Seed.numeric(arg(a, 0)));
			(t : JsDate).time = v;
			return v;});
		// (setters: the components given replace those of the current time)
		function setter(name:String, arity:Int, utcMode:Bool, apply:(Float, Array<Float>) -> Float) method(p, "set" + (utcMode ? "UTC" : "") + name, arity, (t, a, _) -> {
			var v = thisTime(t);
			var nums = [for (x in a) Seed.numeric(x)];
			if (a.length == 0) nums = [Math.NaN];
			var base = Math.isNaN(v) ? (name == "FullYear" ? 0.0 : Math.NaN) : (utcMode ? v : localTime(v));
			if (Math.isNaN(base)) {
				return Math.NaN;
			}
			var r = apply(base, nums);
			var result = timeClip(utcMode ? r : utc(r));
			(t : JsDate).time = result;
			return result;
		});
		for (utcMode in [false, true]) {
			setter("Milliseconds", 1, utcMode, (b, n) -> makeDate(day(b), makeTime(hourFromTime(b), minFromTime(b), secFromTime(b), n[0])));
			setter("Seconds", 2, utcMode, (b, n) -> makeDate(day(b), makeTime(hourFromTime(b), minFromTime(b), n[0], n.length > 1 ? n[1] : msFromTime(b))));
			setter("Minutes", 3, utcMode, (b, n) -> makeDate(day(b), makeTime(hourFromTime(b), n[0], n.length > 1 ? n[1] : secFromTime(b), n.length > 2 ? n[2] : msFromTime(b))));
			setter("Hours", 4, utcMode, (b, n) -> makeDate(day(b), makeTime(n[0], n.length > 1 ? n[1] : minFromTime(b), n.length > 2 ? n[2] : secFromTime(b), n.length > 3 ? n[3] : msFromTime(b))));
			setter("Date", 1, utcMode, (b, n) -> makeDate(makeDay(yearFromTime(b), monthFromTime(b), n[0]), timeWithinDay(b)));
			setter("Month", 2, utcMode, (b, n) -> makeDate(makeDay(yearFromTime(b), n[0], n.length > 1 ? n[1] : dateFromTime(b)), timeWithinDay(b)));
			setter("FullYear", 3, utcMode, (b, n) -> makeDate(makeDay(n[0], n.length > 1 ? n[1] : monthFromTime(b), n.length > 2 ? n[2] : dateFromTime(b)), timeWithinDay(b)));
		}
		function formatter(name:String, fn:Float->String) method(p, name, 0, (t, _, _) -> {
			var v = thisTime(t);
			return Math.isNaN(v) ? "Invalid Date" : fn(v);});
		formatter("toString", v -> dateString(v) + " " + timeString(v));
		formatter("toDateString", dateString);
		formatter("toTimeString", timeString);
		formatter("toUTCString", v -> dayNames[weekDay(v)] + ", " + pad(dateFromTime(v), 2) + " " + monthNames[monthFromTime(v)] + " " + year(yearFromTime(v)) + " " + pad(hourFromTime(v), 2) + ":" + pad(minFromTime(v), 2) + ":" + pad(secFromTime(v), 2) + " GMT");
		p.setOwn("toGMTString", p.slots.get("toUTCString"), Attr.HIDDEN);
		formatter("toLocaleDateString", localeDate);
		formatter("toLocaleTimeString", localeTime);
		formatter("toLocaleString", v -> localeDate(v) + ", " + localeTime(v));
		method(p, "toISOString", 0, (t, _, _) -> {
			var v = thisTime(t);
			if (Math.isNaN(v)) error("RangeError", "Invalid time value");
			return iso(v);});
		method(p, "toJSON", 1, (t, _, _) -> {
			var tv = toPrimitive(t, "number");
			if (Lib.isNumber(tv) && !Math.isFinite(tv)) return null;
			return callMethod(t, "toISOString", []);});
		method(p, Symbols.toPrimitive, 1, (t, a, _) -> {
			var hint = arg(a, 0);
			if (!isObject(t)) error("TypeError", "Date.prototype[Symbol.toPrimitive] called on non-object");
			var order = hint == "number" ? ["valueOf", "toString"] : hint == "string" || hint == "default" ? ["toString", "valueOf"] : error("TypeError", "Invalid hint: " + Seed.text(hint));
			for (m in (order : Array<String>)) {
				var f = get(t, m);
				if (isCallable(f)) {
					var r = call(f, t, []);
					if (!isObject(r)) return r;
				}
			}
			return error("TypeError", "Cannot convert object to primitive value");
		});
	}
}
