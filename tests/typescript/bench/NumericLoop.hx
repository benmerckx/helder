// numeric-loop.ts in Haxe (bench.mjs: TypeScript against Haxe)
class NumericLoop {
	static function sum(n:Int):Int {
		var s = 0;
		for (i in 0...n) s = s + (i % 97);
		return s;
	}

	static function main()
		Sys.println(sum(10000000));
}
