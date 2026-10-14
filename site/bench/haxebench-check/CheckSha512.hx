import haxe.crypto.Sha512;

// BMSHA512Code with the hashes printed
class CheckSha512 {
	static function main() {
		var allHash = new StringBuf();
		for (index in 0...10)
			for (text in Data.DATA)
				allHash.add(Sha512.encode(text));
		Sys.println(Sha512.encode(Data.DATA[0]));
		Sys.println(Sha512.encode(Data.DATA.join("")));
		Sys.println(Sha512.encode(allHash.toString()));
	}
}
