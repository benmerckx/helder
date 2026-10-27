// expect: a scoped value inside a GC type
import helder.scoped.*;

class InArray {
	static function main() {
		var all:Array<Str> = [];
		all.push(Str.of("x"));
	}
}
