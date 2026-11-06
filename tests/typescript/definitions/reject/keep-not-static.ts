// keep's key is static (in Haxe: RejectKeepNotStatic.hx).
// expect: keep: key is not static
import {keep} from "helder/dev";

export function f() {
	const key = "n";
	return keep(key, () => 0);
}
