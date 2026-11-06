// generics.ts in Haxe (bench.mjs: TypeScript against Haxe): type parameters instantiated with Float
class Generics {
	static function fill<T>(n:Int, v:T):Array<T> {
		var out = [];
		for (i in 0...n) out.push(v);
		return out;
	}

	static function swap<T>(xs:Array<T>, i:Int, j:Int):Void {
		var t = xs[i];
		xs[i] = xs[j];
		xs[j] = t;
	}

	static function reverse<T>(xs:Array<T>):Void {
		var n = xs.length;
		for (i in 0...n >> 1) swap(xs, i, n - 1 - i);
	}

	static function count<T>(xs:Array<T>, v:T):Int {
		var c = 0;
		for (x in xs) if (x == v) c++;
		return c;
	}

	static function last<T>(xs:Array<T>):T
		return xs[xs.length - 1];

	static function main() {
		var xs:Array<Float> = fill(1000, 0.0);
		for (i in 0...xs.length) xs[i] = i % 10;
		var total = 0.0;
		for (round in 0...5000) {
			reverse(xs);
			total += count(xs, round % 10) + last(xs);
		}
		Sys.println(total + " " + xs[0] + " " + xs[999]);
	}
}
