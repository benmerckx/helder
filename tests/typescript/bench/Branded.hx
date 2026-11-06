// branded.ts in Haxe (bench.mjs: TypeScript against Haxe): units as abstracts over Float
abstract Meters(Float) to Float {
	public inline function new(v:Float)
		this = v;
}

abstract Seconds(Float) to Float {
	public inline function new(v:Float)
		this = v;
}

class Branded {
	static function speed(d:Meters, t:Seconds):Float
		return (d : Float) / (t : Float);

	static function larger(a:Float, b:Float):Float
		return a > b ? a : b;

	static function total(xs:Array<Meters>):Float {
		var s = 0.0;
		for (x in xs) s += x;
		return s;
	}

	static function main() {
		var distances:Array<Meters> = [];
		for (i in 0...1000) distances.push(new Meters(i % 13 + 1));
		var best = 0.0, sum = 0.0;
		for (round in 0...5000) {
			for (i in 0...distances.length) {
				var v = speed(distances[i], new Seconds(round % 7 + 1));
				best = larger(best, v);
			}
			sum += total(distances);
		}
		Sys.println(best + " " + sum);
	}
}
