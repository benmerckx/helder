// strings.ts in Haxe (bench.mjs: TypeScript against Haxe)
class Strings {
	static function words(n:Int):String {
		var s = new StringBuf();
		for (i in 0...n) s.add(i % 7 == 0 ? "lorem " : "ipsum ");
		return s.toString();
	}

	static function main() {
		var text = words(300000);
		var count = 0, letters = 0;
		for (w in text.split(" ")) if (w.length > 0) {
			count++;
			letters += w.length;
		}
		// (in the order first seen, as a JavaScript Map's)
		var counts = new Map<String, Int>(), order = [];
		for (w in text.split(" ")) {
			if (!counts.exists(w)) order.push(w);
			counts.set(w, (counts.get(w) ?? 0) + 1);
		}
		var codes = 0;
		for (i in 0...text.length) codes += StringTools.fastCodeAt(text, i);
		Sys.println('$count $letters $codes ' + [for (k in order) k + "=" + counts.get(k)].join(","));
	}
}
