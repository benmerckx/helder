// expect: a scoped value captured by a closure
import hxmc.scoped.*;

class Captured {
	static function main() {
		var s = Scope.slice(Int, 4);
		haxe.Timer.delay(() -> s[0] = 1, 10);
	}
}
