// Asset: a path in another case than the file on disk (Android and the
// web tell them apart) is a compile error
class Case {
	static function main()
		helder.asset.Asset.bytes("files/Kept.txt");
}
