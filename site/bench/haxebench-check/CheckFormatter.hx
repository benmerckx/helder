import formatter.Formatter;
import formatter.config.Config;
import haxe.crypto.Sha256;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import tokentree.TokenTreeBuilder.TokenTreeEntryPoint;

// BMFormatterNoIOCode's formatting, once, files in sorted order, the outputs hashed
class CheckFormatter {
	static function main() {
		var files = [];
		function walk(path:String) {
			var names = FileSystem.readDirectory(path);
			names.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
			for (f in names) {
				var fileName = Path.join([path, f]);
				if (FileSystem.isDirectory(fileName))
					walk(fileName)
				else
					files.push(fileName);
			}
		}
		walk("../data");
		var config = new Config();
		var config2 = new Config();
		config2.lineEnds.leftCurly = Both;
		var all = new StringBuf(), ok = 0, failed = 0, chars = 0;
		for (f in files) {
			var src = File.getContent(f);
			for (c in [config, config2]) {
				switch (Formatter.format(Code(src), c, null, TokenTreeEntryPoint.TYPE_LEVEL)) {
					case Success(code):
						ok++;
						chars += code.length;
						all.add(code);
					case Failure(e):
						failed++;
						all.add("FAIL " + f + ": " + e);
					case Disabled:
						all.add("DISABLED " + f);
				}
			}
		}
		Sys.println('${files.length} files, $ok formatted, $failed failed, $chars chars, sha256 ${Sha256.encode(all.toString())}');
	}
}
