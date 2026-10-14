import haxe.crypto.BCrypt;

// BMBCryptCode with fixed salts (the case's are random), printed
class CheckBcrypt {
	static function main() {
		var salts = ["$2b$06$abcdefghijklmnopqrstuu", "$2b$07$ABCDEFGHIJKLMNOPQRSTUu", "$2a$06$0123456789./abcdefghiu", "$2b$04$zyxwvutsrqponmlkjihgfe"];
		for (index in 0...8) {
			var text = Data.DATA[index];
			var hash = BCrypt.encode(text, salts[index % salts.length]);
			Sys.println(hash + " " + BCrypt.verify(text, hash) + " " + BCrypt.verify(text + "x", hash));
		}
		var salt = BCrypt.generateSalt(4);
		Sys.println("random salt: " + BCrypt.verify(Data.DATA[0], BCrypt.encode(Data.DATA[0], salt)));
	}
}
