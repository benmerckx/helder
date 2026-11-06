// fibonacci.ts in Haxe (bench.mjs: TypeScript against Haxe)
class Fibonacci {
	static function fibonacci(n:Int):Int
		return n < 2 ? n : fibonacci(n - 1) + fibonacci(n - 2);

	static function main()
		Sys.println(fibonacci(32));
}
