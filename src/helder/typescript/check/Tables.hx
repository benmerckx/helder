package helder.typescript.check;

import haxe.ds.Vector;
import sys.io.File;
import helder.typescript.check.Syntax;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;

// What the installed typescript package numbers differently from the
// version Kind.hx and Syntax.hx were generated from: its SyntaxKind values
// and each kind's child properties, read from its sources by name. The
// binary AST's layout itself must be the one this reader knows.
class Tables {
	public final version:String;
	// (the installed numbering's kinds as Kind's, and back)
	final kinds:Vector<Int>;
	final raws:Vector<Int>;
	// (a kind's child property's position in its encoding, by Kind and accessor number)
	final orders:Vector<Int>;

	static inline var PROPERTIES = 128;
	static var loaded:Map<String, Tables> = [];

	public static function load(dir:String):Tables {
		var t = loaded.get(dir);
		if (t == null) {
			t = new Tables(dir);
			loaded.set(dir, t);
		}
		return t;
	}

	function new(dir:String) {
		var pkg:Dynamic = haxe.Json.parse(File.getContent(dir + "/package.json"));
		version = pkg.version;
		var protocol = File.getContent(dir + "/dist/api/node/protocol.js");
		var constant = ~/export const ([A-Z_0-9]+) = (0x[0-9A-Fa-f]+|[0-9]+);/;
		var expected = [
			"PROTOCOL_VERSION" => Protocol.PROTOCOL_VERSION, "NODE_LEN" => Protocol.NODE_LEN, "HEADER_SIZE" => Protocol.HEADER_SIZE,
			"HEADER_OFFSET_NODES" => Protocol.HEADER_OFFSET_NODES, "NODE_OFFSET_DATA" => Protocol.NODE_OFFSET_DATA
		];
		var text = protocol;
		while (constant.match(text)) {
			var name = constant.matched(1), value = Std.parseInt(constant.matched(2));
			if (expected.exists(name) && expected.get(name) != value)
				throw 'TSHX003: typescript@$version speaks tsgo protocol $name=$value; this compiler reads ${expected.get(name)} (typescript ${Protocol.PROTOCOL_VERSION})';
			text = constant.matchedRight();
		}
		var byName = new Map<String, Int>();
		for (i in 0...Kind.names.length) if (Kind.names[i] != "" && !byName.exists(Kind.names[i])) byName.set(Kind.names[i], i);
		var installed = new Map<String, Int>(), max = 0;
		var entry = ~/SyntaxKind\["([A-Za-z0-9_]+)"\] = ([0-9]+)/;
		text = File.getContent(dir + "/dist/enums/syntaxKind.enum.js");
		while (entry.match(text)) {
			var name = entry.matched(1), value = Std.parseInt(entry.matched(2));
			if (!~/^(First|Last|Count)/.match(name) && !installed.exists(name)) {
				installed.set(name, value);
				if (value > max) max = value;
			}
			text = entry.matchedRight();
		}
		if (!installed.exists("Identifier")) throw 'TSHX003: typescript@$version: no SyntaxKind table in dist/enums/syntaxKind.enum.js';
		kinds = new Vector(max + 1);
		for (i in 0...kinds.length) kinds[i] = cast KindUnknown;
		raws = new Vector(Kind.names.length);
		for (i in 0...raws.length) raws[i] = -1;
		for (name => value in installed) {
			var ours = byName.get(name);
			if (ours == null) continue;
			kinds[value] = ours;
			raws[ours] = value;
		}
		orders = new Vector(Kind.names.length * PROPERTIES);
		for (i in 0...orders.length) orders[i] = -1;
		var property = new Map<String, Int>();
		for (i in 0...Protocol.properties.length) property.set(Protocol.properties[i], i);
		var row = ~/\[SyntaxKind\.([A-Za-z0-9_]+)\]: \[([^\]]*)\]/;
		text = File.getContent(dir + "/dist/api/node/protocol.generated.js");
		while (row.match(text)) {
			var ours = byName.get(row.matched(1));
			if (ours != null) {
				var names = [for (n in row.matched(2).split(",")) StringTools.trim(n)].filter(n -> n != "");
				for (j in 0...names.length) {
					var p = property.get(names[j].substr(1, names[j].length - 2));
					if (p != null) orders[ours * PROPERTIES + p] = j;
				}
			}
			text = row.matchedRight();
		}
	}

	// the kind an installed number stands for (KindUnknown for syntax newer than Kind.hx)
	public inline function kind(raw:Int):Kind
		return raw == Protocol.KIND_NODE_LIST ? cast raw : raw >= 0 && raw < kinds.length ? cast kinds[raw] : KindUnknown;

	// the installed number of a kind
	public inline function raw(kind:Kind):Int
		return raws[kind];

	// the position of a child property among a kind's possible children, or -1
	public inline function order(kind:Kind, property:Int):Int
		return (kind : Int) < 0 || (kind : Int) >= Kind.names.length ? -1 : orders[(kind : Int) * PROPERTIES + property];
}
