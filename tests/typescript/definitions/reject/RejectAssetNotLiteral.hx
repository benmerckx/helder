// an asset's path is a literal (in TypeScript: asset-not-literal.ts).
// expect: Asset.bytes: name is not static
class RejectAssetNotLiteral {
	static function main() {
		var name = "files/note.txt";
		trace(helder.asset.Asset.bytes(name));
	}
}
