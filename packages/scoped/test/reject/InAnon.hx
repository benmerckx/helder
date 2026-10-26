// expect: a scoped value in an anonymous structure
import hxmc.scoped.*;

class InAnon {
	static function main() {
		var o = {name: Str.of("x")};
	}
}
