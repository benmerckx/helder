// Asset: the path is a literal (a definition's argument is static), not a value made at run time
class NotLiteral {
	static function main() {
		var name = "files/kept.txt";
		helder.asset.Asset.bytes(name);
	}
}
