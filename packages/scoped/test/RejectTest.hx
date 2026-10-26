import sys.FileSystem;
import sys.io.Process;

// Each program in test/reject must fail to compile with the checker on, with
// the message its first line names (`// expect: ...`).
//   haxe -cp packages/scoped/test --run RejectTest [compiler]
// (compiler: the command that compiles them, `haxe` by default; make scoped-check
// gives hxmc's port)
class RejectTest {
	static function main() {
		var dir = "packages/scoped/test/reject";
		var haxe = Sys.args().length > 0 ? Sys.args()[0] : "haxe";
		var failures = 0, n = 0;
		for (file in FileSystem.readDirectory(dir)) {
			if (!StringTools.endsWith(file, ".hx"))
				continue;
			n++;
			var src = sys.io.File.getContent('$dir/$file');
			var expect = StringTools.trim(src.split("\n")[0].substr("// expect:".length));
			var p = new Process(haxe, [
				"-cp", "packages/scoped/src", "-cp", dir, "-main", file.substr(0, file.length - 3), "--macro", "hxmc.scoped.Check.enable()",
				"--no-output", "--interp"
			]);
			var err = p.stderr.readAll().toString();
			var code = p.exitCode();
			p.close();
			if (code == 0 || err.indexOf(expect) < 0) {
				failures++;
				Sys.println('FAIL $file: expected "$expect", got (exit $code):\n$err');
			}
		}
		Sys.println(failures == 0 ? 'ok $n' : '$failures of $n failed');
		if (failures != 0)
			Sys.exit(1);
	}
}
