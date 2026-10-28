// Asset: a file that is not there is a compile error at the call
class Missing {
	static function main()
		helder.asset.Asset.bytes("files/nothere.txt");
}
