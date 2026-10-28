package helder.typescript.lower;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Project;

// Which of the runtime's optional built-ins a program installs
// (helder.typescript.js.Builtins.install*): those whose global it names,
// whose methods it may call (by name: any receiver), whose syntax it has.
// What it does not install, nothing reaches, and hxmc leaves the code out.
// A program the names do not describe (globalThis, a method called by a
// computed name) installs them all.
class Features {
	// the installers' names (Seed.libInstall<name>), by what makes a program need them
	static final byName:Map<String, Array<String>> = {
		var m = new Map<String, Array<String>>();
		function add(group:String, names:Array<String>) for (n in names) m.set(n, (m.get(n) ?? []).concat([group]));
		add("RegExp", ["RegExp", "match", "matchAll", "search"]);
		add("Normalize", ["normalize"]);
		add("Date", ["Date"]);
		add("Buffers", ["ArrayBuffer", "DataView", "SharedArrayBuffer"]);
		add("Json", ["JSON", "rawJSON", "isRawJSON"]);
		add("IteratorHelpers", ["Iterator", "take", "drop", "toArray", "flatMap", "map", "filter", "reduce", "forEach", "some", "every", "find"]);
		add("Promise", ["Promise", "then", "setTimeout", "setInterval", "setImmediate", "clearTimeout", "clearInterval", "clearImmediate", "queueMicrotask"]);
		add("FromAsync", ["fromAsync"]);
		add("SetMethods", ["union", "intersection", "difference", "symmetricDifference", "isSubsetOf", "isSupersetOf", "isDisjointFrom"]);
		add("Uri", ["encodeURI", "decodeURI", "encodeURIComponent", "decodeURIComponent"]);
		add("StructuredClone", ["structuredClone"]);
		add("All", ["globalThis"]);
		m;
	};

	public static function of(project:Project):Array<String> {
		var groups = new Map<String, Bool>();
		for (sf in project.files) for (i in 1...sf.count) switch sf.kindAt(i) {
			case KindIdentifier:
				var g = byName.get(sf.node(i).text);
				if (g != null) for (x in g) groups.set(x, true);
			case KindRegularExpressionLiteral:
				groups.set("RegExp", true);
			case KindAwaitExpression | KindAsyncKeyword | KindAwaitKeyword:
				groups.set("Promise", true);
			case KindCallExpression:
				var callee = sf.node(i).expression();
				if (callee != null && callee.kind == KindElementAccessExpression) {
					var key = callee.argumentExpression();
					if (key != null && key.kind == KindStringLiteral) {
						var g = byName.get(key.text);
						if (g != null) for (x in g) groups.set(x, true);
					} else if (key != null && key.kind != KindNumericLiteral) groups.set("All", true);
				}
			case _:
		}
		if (groups.exists("All")) return ["All"];
		var out = [for (g in groups.keys()) g];
		out.sort(Reflect.compare);
		return out;
	}
}
