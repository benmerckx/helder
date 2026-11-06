// keep's key is not empty (in TypeScript: keep-empty-key.ts).
// expect: keep: the key is empty
import helder.dev.Keep;

class RejectKeepEmptyKey {
	static function main() {
		trace(keep("", () -> 0));
	}
}
