// keep's initial value takes no arguments (in TypeScript: keep-arguments.ts).
// expect: keep: the initial value is made by a function of no arguments (() => value), not of 1
import helder.dev.Keep;

class RejectKeepArguments {
	static function main() {
		trace(keep("n", (?x:Int) -> x ?? 0));
	}
}
