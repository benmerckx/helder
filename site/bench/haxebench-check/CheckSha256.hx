import haxe.crypto.Sha256;

// BMSHA256Code with the hashes printed
class CheckSha256 {
	static function main() {
		var allHash = new StringBuf();
		for (index in 0...100)
			for (text in Data.DATA)
				allHash.add(Sha256.encode(text));
		Sys.println(Sha256.encode(Data.DATA[0]));
		Sys.println(Sha256.encode(Data.DATA.join("")));
		Sys.println(Sha256.encode(allHash.toString()));
	}
}
