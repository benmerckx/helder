import hxmc.os.*;

// hxmc.os.Clipboard between two windows of one process (make
// ui-draw-check, X11 under Xvfb): the text one writes, the other reads
// through the selection's protocol (SelectionRequest answered,
// SelectionNotify read); the writer reads its own at once; ownership moves
// with the next write (SelectionClear); a text over 256 KB goes in parts
// (INCR, on X11).
//   ClipboardTest
class ClipboardTest {
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('ClipboardTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var a = new Window("ClipboardTest A", 64, 64);
		var b = new Window("ClipboardTest B", 64, 64);
		var text = "héllo ✓ 𝄞 clipboard";
		var steps:Array<Void->Void> = [];
		var waiting = false;
		function next()
			waiting = false;
		steps.push(() -> {
			Clipboard.write(a, text);
			Clipboard.read(a, t -> {
				check("the writer reads its own text at once", t == text, t);
				next();
			});
		});
		steps.push(() -> Clipboard.read(b, t -> {
			check("another window reads it through the selection", t == text, t);
			next();
		}));
		steps.push(() -> {
			Clipboard.write(b, "second");
			Clipboard.read(a, t -> {
				check("ownership moved: the first window reads the second's", t == "second", t);
				next();
			});
		});
		// a text of a megabyte or so: sent in parts (INCR) between the windows
		var big = [for (i in 0...40000) "line " + i + " héllo ✓\n"].join("");
		steps.push(() -> {
			Clipboard.write(a, big);
			Clipboard.read(b, t -> {
				check("a large text in parts (INCR)", t == big, t == null ? "null" : t.length + " of " + big.length);
				next();
			});
		});
		var start = haxe.Timer.stamp();
		App.run(() -> {
			if (!waiting) {
				if (steps.length == 0) {
					a.close();
					b.close();
					return;
				}
				waiting = true;
				steps.shift()();
			}
			if (haxe.Timer.stamp() - start > 10) {
				check("answered within 10 s", false);
				a.close();
				b.close();
			}
			App.wait(0.01);
		}, e -> {});
		Sys.println('ClipboardTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 && checks == 4 ? 0 : 1);
	}
}
