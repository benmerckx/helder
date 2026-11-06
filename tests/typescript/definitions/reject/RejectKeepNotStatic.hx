// keep's key is static (in TypeScript: keep-not-static.ts).
// expect: keep: key is not static
import helder.dev.Keep;

class RejectKeepNotStatic {
	static function main() {
		var key = "n";
		trace(keep(key, () -> 0));
	}
}
