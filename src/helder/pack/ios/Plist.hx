package helder.pack.ios;

import haxe.io.Bytes;

// Property lists in Apple's XML form (Info.plist, CodeResources,
// entitlements), written with their dictionaries' keys sorted as
// CoreFoundation writes them, so the same values give the same bytes; and
// read back (the checks: tests/pack).
// Ported from hxmc (hxmc.ios.Plist), MIT.
enum PValue {
	PString(s:String);
	PBool(b:Bool);
	PInt(i:Int);
	PData(b:Bytes);
	PArray(a:Array<PValue>);
	PDict(d:Map<String, PValue>);
}

class Plist {
	public static function xml(v:PValue):Bytes {
		var b = new StringBuf();
		b.add('<?xml version="1.0" encoding="UTF-8"?>\n');
		b.add('<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n');
		b.add('<plist version="1.0">\n');
		value(b, v, 0);
		b.add('</plist>\n');
		return Bytes.ofString(b.toString());
	}

	static function value(b:StringBuf, v:PValue, depth:Int) {
		var tab = StringTools.lpad("", "\t", depth);
		switch v {
			case PString(s):
				b.add(tab + "<string>" + StringTools.htmlEscape(s) + "</string>\n");
			case PBool(x):
				b.add(tab + (x ? "<true/>" : "<false/>") + "\n");
			case PInt(i):
				b.add(tab + "<integer>" + i + "</integer>\n");
			case PData(d):
				b.add(tab + "<data>\n" + tab + haxe.crypto.Base64.encode(d) + "\n" + tab + "</data>\n");
			case PArray(a):
				if (a.length == 0) {
					b.add(tab + "<array/>\n");
					return;
				}
				b.add(tab + "<array>\n");
				for (x in a)
					value(b, x, depth + 1);
				b.add(tab + "</array>\n");
			case PDict(d):
				var keys = [for (k in d.keys()) k];
				if (keys.length == 0) {
					b.add(tab + "<dict/>\n");
					return;
				}
				keys.sort((x, y) -> x < y ? -1 : x > y ? 1 : 0);
				b.add(tab + "<dict>\n");
				for (k in keys) {
					b.add(tab + "\t<key>" + StringTools.htmlEscape(k) + "</key>\n");
					value(b, d.get(k), depth + 1);
				}
				b.add(tab + "</dict>\n");
		}
	}

	// an XML property list read back
	public static function parse(text:String):PValue {
		var root = Xml.parse(text).firstElement();
		if (root == null || root.nodeName != "plist") throw "not a property list";
		var e = root.firstElement();
		if (e == null) throw "an empty property list";
		return read(e);
	}

	static function read(e:Xml):PValue {
		function text(e:Xml):String {
			var s = new StringBuf();
			for (c in e)
				if (c.nodeType == PCData || c.nodeType == CData) s.add(c.nodeValue);
			return s.toString();
		}
		return switch e.nodeName {
			case "string": PString(StringTools.htmlUnescape(text(e)));
			case "true": PBool(true);
			case "false": PBool(false);
			case "integer": PInt(Std.parseInt(StringTools.trim(text(e))));
			case "data": PData(haxe.crypto.Base64.decode(~/\s+/g.replace(text(e), "")));
			case "array": PArray([for (c in e.elements()) read(c)]);
			case "dict":
				var d = new Map<String, PValue>(), key:Null<String> = null;
				for (c in e.elements())
					if (c.nodeName == "key") key = StringTools.htmlUnescape(text(c)) else {
						if (key == null) throw "a dictionary's value without a key";
						d.set(key, read(c));
						key = null;
					}
				PDict(d);
			case n: throw "unknown property list element " + n;
		}
	}
}
