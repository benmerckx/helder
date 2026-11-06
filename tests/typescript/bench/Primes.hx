// primes.ts in Haxe (bench.mjs: TypeScript against Haxe)
class Primes {
	static function primes(n:Int):Int {
		var count = 0;
		for (candidate in 2...n) {
			var prime = true;
			var divisor = 2;
			while (divisor * divisor <= candidate) {
				if (candidate % divisor == 0) {
					prime = false;
					break;
				}
				divisor++;
			}
			if (prime) count = count + 1;
		}
		return count;
	}

	static function main()
		Sys.println(primes(50000));
}
