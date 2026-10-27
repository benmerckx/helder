// expect: a scoped value in an anonymous structure
import helder.scoped.*;

class InAnon {
	static function main() {
		var o = {name: Str.of("x")};
	}
}
