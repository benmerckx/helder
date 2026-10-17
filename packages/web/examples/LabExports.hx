import haxe.io.Bytes;

// What lab.wasm (Lab.hx) exports to JavaScript (hxmc.web.Exports): compiled
// into the module, where each function runs, and into the JavaScript
// islands, where each calls the module (LabExports.module)
class LabExports implements hxmc.web.Exports {
	public static function sum(a:Int, b:Int):Int
		return Lab.sum(a, b);

	// each byte inverted (255 - b): bytes in bulk, both ways
	public static function invert(data:Bytes):Bytes
		return Lab.invert(data);

	public static function greet(name:String):String
		return 'Hello, $name, from WebAssembly';

	public static function half(x:Float):Float
		return x / 2;

	public static function even(n:Int):Bool
		return n % 2 == 0;
}
