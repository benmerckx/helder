// expect: a scoped value inside a GC type
import hxmc.scoped.*;

class InArray {
	static function main() {
		var all:Array<Str> = [];
		all.push(Str.of("x"));
	}
}
