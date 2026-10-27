package async;

import helder.async.*;
import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

// SampledWatcher (esbuild's polling): a recent file seen at the next tick,
// any other within a pass (20 ticks), a new file through its directory's
// listing, an edit within the same second and the same size through the
// content. Driven by tick() (what next() does every 0.1 s), then next().
function tests() {
	final root = "bin/async/sampled";

	// n files under root (a, b, c, ... in two directories), all watched
	function tree(n:Int):{w:SampledWatcher, files:Array<String>} {
		rmrf(root);
		for (d in ["", "/sub"]) FileSystem.createDirectory(root + d);
		var files = [for (i in 0...n) '$root${i % 2 == 0 ? "" : "/sub"}/f$i.txt'];
		for (f in files) File.saveContent(f, "x");
		var w = new SampledWatcher();
		w.watch(files, [root, '$root/sub']);
		return {w: w, files: files};
	}

	// the ticks until tick() reports path (null: not within max)
	function ticks(w:SampledWatcher, path:String, max:Int):Null<Int> {
		for (i in 1...max + 1) {
			var p = w.tick();
			if (p == path) return i;
		}
		return null;
	}

	describe("SampledWatcher", () -> {
		test("a cold file within a pass, then hot: the next tick", () -> {
			var t = tree(2000);
			var f = t.files[1234];
			File.saveContent(f, "y");
			var n = ticks(t.w, f, 21);
			require(n != null, "seen within a pass of 20 ticks");
			// (reported: its state taken again, and it is recent now)
			t.w.watch(t.files, [root, '$root/sub']);
			File.saveContent(f, "z");
			equals(t.w.tick(), f);
		});
		test("a new file: its directory's listing", () -> {
			var t = tree(100);
			File.saveContent('$root/sub/new.txt', "new");
			notEquals(ticks(t.w, '$root/sub', 21), null);
		});
		test("a removed file", () -> {
			var t = tree(100);
			FileSystem.deleteFile(t.files[7]);
			// (the file, or its directory's listing, whichever is checked first)
			var p = null;
			for (_ in 0...21) if ((p = t.w.tick()) != null) break;
			require(p == t.files[7] || p == '$root/sub', 'reported: $p');
		});
		test("the same second, the same size: the content", () -> {
			var t = tree(10);
			File.saveContent(t.files[3], "q");
			notEquals(ticks(t.w, t.files[3], 21), null);
		});
		test("nothing changed: nothing reported", () -> {
			var t = tree(300);
			for (_ in 0...25) equals(t.w.tick(), null);
		});
		test("next(): a batch", async(() -> {
			var t = tree(50);
			Async.scope(task -> {
				task.async(_ -> {
					Async.delay(0.05);
					File.saveContent(t.files[0], "edited");
				});
				equals(Async.timeout(5, _ -> t.w.next()), [t.files[0]]);
				null;
			});
		}));
	});
}

private function rmrf(path:String) {
	if (!FileSystem.exists(path)) return;
	if (FileSystem.isDirectory(path)) {
		for (f in FileSystem.readDirectory(path)) rmrf('$path/$f');
		FileSystem.deleteDirectory(path);
	} else FileSystem.deleteFile(path);
}
