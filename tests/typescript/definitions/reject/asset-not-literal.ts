// an asset's path is a literal (in Haxe: RejectAssetNotLiteral.hx).
// expect: Asset.bytes: name is not static
import {bytes, image} from "helder/asset";

export function f() {
	const name = "files/note.txt";
	return bytes(name);
}
