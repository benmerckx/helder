// title: JavaScript calls wasm
// summary: A JavaScript island calling a wasm32-wasi module through typed exports: strings, numbers and bytes in bulk
// tags: web, javascript, wasm, exports
// demo: module
import haxe.io.Bytes;

// A wasm32-wasi module JavaScript calls (LabExports): main names its exports
// and returns; the module stays, its exports called after main returned.
//   hxmc -cp packages/web/src -cp packages/web/examples -main Lab \
//     -D hxmc.target=wasm32-wasi --custom-target hxmc=lab.wasm
class Lab {
	static function main() {
		LabExports.register();
	}

	public static function sum(a:Int, b:Int):Int
		return a + b;

	public static function invert(data:Bytes):Bytes {
		var out = Bytes.alloc(data.length);
		for (i in 0...data.length)
			out.set(i, 255 - data.get(i));
		return out;
	}
}
