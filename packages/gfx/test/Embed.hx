// A file's bytes built into the program (a macro: the file is read when compiling)
class Embed {
	public static macro function file(path:String):haxe.macro.Expr {
		var b = sys.io.File.getBytes(path);
		return macro haxe.crypto.Base64.decode($v{haxe.crypto.Base64.encode(b)});
	}
}
