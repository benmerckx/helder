package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Symbols.JsSymbol;
import helder.typescript.js.Lib.*;

// console.log formatting: Node's util.formatWithOptions and util.inspect with
// default options (depth 2, breakLength 80, compact 3), without colors.
class Inspect {
	static inline var breakLength = 80;
	static inline var compact = 3;
	static inline var maxArrayLength = 100;
	static inline var ARRAY = 1;
	static inline var ARRAY_EXTRAS = 2;
	var depth:Int;
	// (%o: non-enumerable properties too, in brackets)
	var showHidden = false;
	var seen:Array<Dynamic> = [];
	var circular:Array<Dynamic> = [];
	var indentationLvl = 0;
	var currentDepth = 0;
	function new(depth:Int) this.depth = depth;

	public static function inspect(v:Dynamic, depth = 2, showHidden = false):String {
		var i = new Inspect(depth);
		i.showHidden = showHidden;
		return i.formatValue(v, 0);
	}

	public static function format(args:Array<Dynamic>):String {
		var first = arg(args, 0);
		var a = 0;
		var out = new StringBuf();
		var join = "";
		if (Std.isOfType(first, String)) {
			var s:String = first;
			if (args.length == 1) return s;
			var lastPos = 0;
			var i = 0;
			while (i < s.length - 1) {
				if (s.charCodeAt(i) == 37) {
					var next = s.charCodeAt(++i);
					if (a + 1 != args.length) {
						var piece:String;
						switch (next) {
							case "s".code:
								var v:Dynamic = args[++a];
								piece = isNumber(v) ? number(v) : Std.isOfType(v, Symbols.JsSymbol) ? Symbols.text(v) : !isObject(v) ? Seed.text(v) : userToString(v) ? Seed.text(v) : inspect(v, 0);
							case "j".code: try piece = Seed.text(call(get(Builtins.global("JSON"), "stringify"), undef(), [args[++a]])) catch (e:Dynamic) {
									piece = "[Circular]";
								}
							case "d".code:
								var v:Dynamic = args[++a];
								piece = isObject(v) || Std.isOfType(v, Symbols.JsSymbol) ? "NaN" : number(Seed.numeric(v));
							case "i".code:
								var v:Dynamic = args[++a];
								piece = Std.isOfType(v, Symbols.JsSymbol) ? "NaN" : number(Numbers.parseInteger(Seed.text(v), undef()));
							case "f".code:
								var v:Dynamic = args[++a];
								piece = Std.isOfType(v, Symbols.JsSymbol) ? "NaN" : number(Numbers.parseDecimalPrefix(Seed.text(v)));
							case "O".code: piece = inspect(args[++a]);
							case "o".code: piece = inspect(args[++a], 4, true);
							case "c".code:
								++a;
								piece = "";
							case "%".code:
								out.add(s.substring(lastPos, i));
								lastPos = i + 1;
								i++;
								continue;
							case _:
								i++;
								continue;
						}
						if (lastPos != i - 1) out.add(s.substring(lastPos, i - 1));
						out.add(piece);
						lastPos = i + 1;
					}
					else if (next == "%".code) {
						out.add(s.substring(lastPos, i));
						lastPos = i + 1;
					}
				}
				i++;
			}
			if (lastPos != 0) {
				a++;
				join = " ";
				if (lastPos < s.length) out.add(s.substr(lastPos));
			}
		}
		while (a < args.length) {
			var v = args[a++];
			out.add(join);
			out.add(Std.isOfType(v, String) ? v : inspect(v));
			join = " ";
		}
		return out.toString();
	}

	// (an object whose toString is not a built-in one prints through it for %s)
	static function userToString(o:Dynamic):Bool {
		var f = get(o, "toString");
		return Std.isOfType(f, JsFunction) && (f : JsFunction).native == null;
	}

	static function number(n:Float):String return n == 0 && 1 / n < 0 ? "-0" : Seed.numberText(n);

	function formatValue(v:Dynamic, recurseTimes:Int):String {
		if (!isObject(v)) return primitive(v);
		if (seen.indexOf(v) >= 0) {
			var i = circular.indexOf(v);
			if (i < 0) {
				circular.push(v);
				i = circular.length - 1;
			}
			return "[Circular *" + (i + 1) + "]";
		}
		return formatRaw(v, recurseTimes);
	}

	function primitive(v:Dynamic):String {
		if (Std.isOfType(v, String)) return quote(v);
		if (isNumber(v)) return number(v);
		if (Std.isOfType(v, Symbols.JsSymbol)) return Symbols.text(v);
		return Seed.text(v);
	}

	public static function quote(s:String):String {
		var q = 39;
		if (s.indexOf("'") >= 0) {
			if (s.indexOf('"') < 0) q = 34; else if (s.indexOf("`") < 0 && s.indexOf("${") < 0) q = 96;
		}
		var b = new StringBuf();
		b.addChar(q);
		for (i in 0...s.length) {
			var c = s.charCodeAt(i);
			if (c == q || c == 92) {
				b.addChar(92);
				b.addChar(c);
				continue;
			}
			switch (c) {
				case 8: b.add("\\b");
				case 9: b.add("\\t");
				case 10: b.add("\\n");
				case 12: b.add("\\f");
				case 13: b.add("\\r");
				case _:
					var lone = c >= 0xd800 && c <= 0xdbff && !(i + 1 < s.length && s.charCodeAt(i + 1) >= 0xdc00 && s.charCodeAt(i + 1) <= 0xdfff)
						|| c >= 0xdc00 && c <= 0xdfff && !(i > 0 && s.charCodeAt(i - 1) >= 0xd800 && s.charCodeAt(i - 1) <= 0xdbff);
					if (c < 32 || c >= 0x7f && c <= 0x9f) b.add("\\x" + StringTools.hex(c, 2));
					else if (lone) b.add("\\u" + StringTools.hex(c, 4).toLowerCase());
					else b.addChar(c);
			}
		}
		b.addChar(q);
		return b.toString();
	}

	static function constructorName(o:JsObject):Null<String> {
		var obj = o;
		while (obj != null) {
			if (obj.hasOwn("constructor")) {
				var c = obj.slots.get("constructor");
				if (Std.isOfType(c, JsFunction) && (c : JsFunction).name != "") return (c : JsFunction).name;
			}
			obj = obj.proto;
		}
		return null;
	}

	static function prefix(constructor:Null<String>, tag:String, fallback:String, size = ""):String {
		if (constructor == null) return tag != "" && fallback != tag ? "[" + fallback + size + ": null prototype] [" + tag + "] " : "[" + fallback + size + ": null prototype] ";
		if (tag != "" && constructor != tag) return constructor + size + " [" + tag + "] ";
		return constructor + size + " ";
	}

	function propertyKeys(o:JsObject, skipIndices:Bool):Array<String> {
		var out:Array<String> = [];
		for (k in Builtins.ownPropertyKeys(o)) {
			if (!showHidden && o.attr(k) & Attr.HIDDEN != 0 || !o.hasOwn(k) && !(showHidden && Std.isOfType(o, JsArray) && k == "length")) continue;
			if (Symbols.isSymbolKey(k) && Symbols.fromKey(k) == null) continue;
			if (skipIndices && index(k) >= 0) continue;
			out.push(k);
		}
		return out;
	}

	function formatRaw(value:JsObject, recurseTimes:Int):String {
		var constructor = constructorName(value);
		var tagValue = getKey(value, Symbols.toStringTag, value);
		var tag = Std.isOfType(tagValue, String) && tagValue != "" && tagValue != constructor ? (tagValue : String) : "";
		var base = "";
		var braces = ["{", "}"];
		var extrasType = 0;
		var keys:Array<String>;
		var formatter:Int->Array<String> = _ -> [];
		if (Std.isOfType(value, JsArray)) {
			var a:JsArray = cast value;
			keys = propertyKeys(value, true);
			var p = constructor != "Array" || tag != "" ? prefix(constructor, tag, "Array", "(" + Seed.numberText(a.length) + ")") : "";
			braces = [p + "[", "]"];
			if (a.length == 0 && keys.length == 0) return braces[0] + "]";
			extrasType = ARRAY_EXTRAS;
			formatter = r -> formatArray(a, r);
		}
		else if (Std.isOfType(value, JsMap)) {
			var m:JsMap = cast value;
			keys = propertyKeys(value, false);
			var size = 0;
			for (x in m.active) if (x) size++;
			var p = prefix(constructor, tag, m.isSet ? "Set" : "Map", "(" + size + ")");
			if (size == 0 && keys.length == 0) return p + "{}";
			braces = [p + "{", "}"];
			formatter = r -> formatMap(m, r);
		}
		else {
			keys = propertyKeys(value, false);
			if (Std.isOfType(value, JsFunction)) {
				base = functionBase(cast value, constructor, tag);
				if (keys.length == 0) return base;
			}
			else if (Std.isOfType(value, JsError)) {
				base = Builtins.errorText(value);
				if (keys.length == 0) return base;
			}
			else if (value.hasOwn("\x00@primitive") && value != Builtins.StringProto && value != Builtins.NumberProto && value != Builtins.BooleanProto) {
				var p = value.slots.get("\x00@primitive");
				var type = Std.isOfType(p, String) ? "String" : Std.isOfType(p, Bool) ? "Boolean" : Std.isOfType(p, Symbols.JsSymbol) ? "Symbol" : "Number";
				base = "[" + type + (constructor == null ? " (null prototype)" : constructor != type ? " (" + constructor + ")" : "") + ": " + primitive(p) + "]";
				if (Std.isOfType(p, String)) keys = [for (k in keys) if (index(k) < 0 && k != "length") k];
				if (keys.length == 0) return base;
			}
			else if (Std.isOfType(value, Dates.JsDate)) {
				var t = (cast value : Dates.JsDate).time;
				base = Math.isNaN(t) ? "Invalid Date" : Dates.iso(t);
				if (keys.length == 0) return base;
			}
			else if (Regex.isRegExp(value)) {
				base = Seed.text(callMethod(value, "toString", []));
				if (keys.length == 0) return base;
			}
			else if (constructor == "Object") {
				if (tag != "") braces[0] = prefix(constructor, tag, "Object") + "{";
				if (keys.length == 0) return braces[0] + "}";
			}
			else {
				if (keys.length == 0) return prefix(constructor, tag, "Object") + "{}";
				braces[0] = prefix(constructor, tag, "Object") + "{";
			}
		}
		if (recurseTimes > depth) {
			var name = Std.isOfType(value, JsArray) ? "Array" : constructor == null ? "Object" : constructor;
			return "[" + name + "]";
		}
		recurseTimes++;
		seen.push(value);
		currentDepth = recurseTimes;
		var output = formatter(recurseTimes);
		for (k in keys) output.push(formatProperty(value, recurseTimes, k, extrasType == ARRAY_EXTRAS ? ARRAY_EXTRAS : 0));
		seen.pop();
		var ref = circular.indexOf(value);
		if (ref >= 0) {
			var reference = "<ref *" + (ref + 1) + ">";
			base = base == "" ? reference : reference + " " + base;
		}
		return reduceToSingleString(output, base, braces, extrasType, recurseTimes, value);
	}

	function functionBase(f:JsFunction, constructor:Null<String>, tag:String):String {
		if (f.kind >= JsFunction.BASE) {
			var name = f.name == "" ? "(anonymous)" : f.name;
			var b = "class " + name;
			if (constructor != "Function" && constructor != null) b += " [" + constructor + "]";
			if (tag != "" && constructor != tag) b += " [" + tag + "]";
			if (constructor != null) {
				var parent = f.proto;
				if (Std.isOfType(parent, JsFunction) && (cast parent : JsFunction).name != "") b += " extends " + (cast parent : JsFunction).name;
			}
			else b += " extends [null prototype]";
			return "[" + b + "]";
		}
		var type = "Function";
		var b = "[" + type;
		if (constructor == null) b += " (null prototype)";
		b += f.name == "" ? " (anonymous)" : ": " + f.name;
		b += "]";
		if (constructor != type && constructor != null) b += " " + constructor;
		if (tag != "" && constructor != tag) b += " [" + tag + "]";
		return b;
	}

	function formatProperty(o:JsObject, recurseTimes:Int, k:String, type:Int):String {
		var str:String;
		var raw:Dynamic = o.hasOwn(k) ? o.slots.get(k) : get(o, k);
		if (Std.isOfType(raw, Accessor)) {
			var acc:Accessor = raw;
			str = acc.getter != null ? (acc.setter != null ? "[Getter/Setter]" : "[Getter]") : acc.setter != null ? "[Setter]" : "undefined";
		}
		else {
			indentationLvl += 2;
			str = formatValue(raw, recurseTimes);
			indentationLvl -= 2;
		}
		if (type == ARRAY) return str;
		var name:String;
		if (Symbols.isSymbolKey(k)) name = Symbols.text(Symbols.fromKey(k));
		else if (showHidden && (o.attr(k) & Attr.HIDDEN != 0 || !o.hasOwn(k))) name = "[" + k + "]";
		else if (k == "__proto__") name = "['__proto__']";
		else if (identifier(k)) name = k;
		else name = quote(k);
		return name + ": " + str;
	}

	static function identifier(k:String):Bool {
		if (k == "") return false;
		for (i in 0...k.length) {
			var c = k.charCodeAt(i);
			var letter = c >= 65 && c <= 90 || c >= 97 && c <= 122 || c == 95;
			if (!(letter || i > 0 && c >= 48 && c <= 57)) return false;
		}
		return true;
	}

	function formatArray(a:JsArray, recurseTimes:Int):Array<String> {
		var output:Array<String> = [];
		var length = a.length;
		var limit = Math.min(maxArrayLength, length);
		var i:Float = 0;
		var index:Float = 0;
		while (i < length && output.length < limit) {
			if (!hasOwnKey(a, Seed.numberText(i))) {
				// (a run of holes)
				var next = i;
				while (next < length && !hasOwnKey(a, Seed.numberText(next))) next++;
				var empty = next - i;
				output.push("<" + Seed.numberText(empty) + " empty item" + (empty > 1 ? "s" : "") + ">");
				i = next;
				index = next;
				continue;
			}
			output.push(formatProperty(a, recurseTimes, Seed.numberText(i), ARRAY));
			i++;
			index = i;
		}
		var remaining = length - index;
		if (remaining > 0) output.push("... " + Seed.numberText(remaining) + " more item" + (remaining > 1 ? "s" : ""));
		return output;
	}

	function formatMap(m:JsMap, recurseTimes:Int):Array<String> {
		var output:Array<String> = [];
		var count = 0;
		var total = 0;
		for (x in m.active) if (x) total++;
		indentationLvl += 2;
		for (i in 0...m.keys.length) {
			if (!m.active[i]) continue;
			if (count >= maxArrayLength) break;
			output.push(m.isSet ? formatValue(m.keys[i], recurseTimes) : formatValue(m.keys[i], recurseTimes) + " => " + formatValue(m.values[i], recurseTimes));
			count++;
		}
		indentationLvl -= 2;
		if (total > count) output.push("... " + (total - count) + " more item" + (total - count > 1 ? "s" : ""));
		return output;
	}

	function reduceToSingleString(output:Array<String>, base:String, braces:Array<String>, extrasType:Int, recurseTimes:Int, value:Dynamic):String {
		var entries = output.length;
		if (extrasType == ARRAY_EXTRAS && entries > 6) output = groupArrayElements(output, value);
		if (currentDepth - recurseTimes < compact && entries == output.length) {
			var start = output.length + indentationLvl + braces[0].length + base.length + 10;
			if (isBelowBreakLength(output, start, base)) {
				var joined = output.join(", ");
				if (joined.indexOf("\n") < 0) return (base != "" ? base + " " : "") + braces[0] + " " + joined + " " + braces[1];
			}
		}
		var indentation = "\n" + StringTools.lpad("", " ", indentationLvl);
		return (base != "" ? base + " " : "") + braces[0] + indentation + "  " + output.join("," + indentation + "  ") + indentation + braces[1];
	}

	function isBelowBreakLength(output:Array<String>, start:Int, base:String):Bool {
		var total = output.length + start;
		if (total + output.length > breakLength) return false;
		for (o in output) {
			total += o.length;
			if (total > breakLength) return false;
		}
		return base == "" || base.indexOf("\n") < 0;
	}

	function groupArrayElements(output:Array<String>, value:Dynamic):Array<String> {
		var totalLength = 0;
		var maxLength = 0;
		var outputLength = output.length;
		if (Std.isOfType(value, JsArray) && (value : JsArray).length > maxArrayLength && StringTools.startsWith(output[output.length - 1], "... ")) outputLength--;
		var separatorSpace = 2;
		var dataLen = [];
		for (i in 0...outputLength) {
			var len = output[i].length;
			dataLen.push(len);
			totalLength += len + separatorSpace;
			if (maxLength < len) maxLength = len;
		}
		var actualMax = maxLength + separatorSpace;
		if (actualMax * 3 + indentationLvl < breakLength && (totalLength / actualMax > 5 || maxLength <= 6)) {
			var averageBias = Math.sqrt(actualMax - totalLength / output.length);
			var biasedMax = Math.max(actualMax - 3 - averageBias, 1);
			var columns = Std.int(Math.min(Math.min(Math.round(Math.sqrt(2.5 * biasedMax * outputLength) / biasedMax), Math.floor((breakLength - indentationLvl) / actualMax)), Math.min(compact * 4, 15)));
			if (columns <= 1) return output;
			var tmp = [];
			var maxLineLength = [];
			for (i in 0...columns) {
				var lineLength = 0;
				var j = i;
				while (j < output.length) {
					if (j < dataLen.length && dataLen[j] > lineLength) lineLength = dataLen[j];
					j += columns;
				}
				maxLineLength.push(lineLength + separatorSpace);
			}
			var padStart = true;
			if (Std.isOfType(value, JsArray)) for (i in 0...output.length) {
				var v = get(value, i);
				if (!isNumber(v)) {
					padStart = false;
					break;
				}
			}
			var i = 0;
			while (i < outputLength) {
				var max = Std.int(Math.min(i + columns, outputLength));
				var str = new StringBuf();
				var j = i;
				while (j < max - 1) {
					var cell = output[j] + ", ";
					str.add(padStart ? StringTools.lpad(cell, " ", maxLineLength[j - i]) : StringTools.rpad(cell, " ", maxLineLength[j - i]));
					j++;
				}
				if (padStart) str.add(StringTools.lpad(output[j], " ", maxLineLength[j - i] - separatorSpace)); else str.add(output[j]);
				tmp.push(str.toString());
				i += columns;
			}
			if (outputLength < output.length) tmp.push(output[outputLength]);
			output = tmp;
		}
		return output;
	}
}
