import sys.FileSystem;
import sys.io.File;

using StringTools;

// The demos lane's check (bun run test demos; tests/Run.hx ran each demo
// headless at half scale into <dir> first): each still against its golden
// here (Linux: llvmpipe; the demos' own Inter, so no system font is
// involved), within a tolerance: at most 2% of the pixels off by more than
// 8 levels in a channel (shaders' noise and blurs differ by a level or two
// between Mesa's versions). A still without a golden fails; BLESS=1 writes
// them.
//   Check <dir> [--bless]
class Check {
	static var failed = 0;
	static var checks = 0;
	static final here = "tests/demos";

	static function main() {
		var args = Sys.args();
		var dir = args[0], bless = args[1] == "--bless";
		var shots = [for (f in FileSystem.readDirectory(dir)) if (f.endsWith(".png")) f];
		shots.sort(Reflect.compare);
		for (f in shots)
			image(f, '$dir/$f', bless);
		if (shots.length < 16) {
			failed++;
			Sys.println('demos: FAIL: ${shots.length} stills, not all of them');
		}
		Sys.println('demos: $checks stills' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function image(golden:String, got:String, bless:Bool) {
		checks++;
		if (bless) {
			File.saveBytes('$here/$golden', File.getBytes(got));
			Sys.println('demos: blessed $here/$golden');
			return;
		}
		if (!FileSystem.exists('$here/$golden')) {
			failed++;
			Sys.println('demos: FAIL: $golden has no golden (BLESS=1 bun run test demos)');
			return;
		}
		var a = helder.image.PngDecoder.decode(File.getBytes(got)), b = helder.image.PngDecoder.decode(File.getBytes('$here/$golden'));
		if (a.width != b.width || a.height != b.height) {
			failed++;
			Sys.println('demos: FAIL: $got is ${a.width}x${a.height}, its golden ${b.width}x${b.height}');
			return;
		}
		var off = 0, max = 0, n = a.width * a.height;
		for (p in 0...n) {
			var d = 0;
			for (k in 0...3) {
				var v = a.rgba.get(4 * p + k) - b.rgba.get(4 * p + k);
				if (v < 0) v = -v;
				if (v > d) d = v;
			}
			if (d > 8) off++;
			if (d > max) max = d;
		}
		var ok = off <= 0.02 * n;
		if (!ok) failed++;
		Sys.println('demos: ${ok ? "" : "FAIL: "}$golden ' + (off == 0 && max == 0 ? "exact" : '$off pixels off, at most $max'));
	}
}
