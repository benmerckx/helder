import helder.async.*;
import sys.FileSystem;
import sys.io.File;

// The watchers' cost per tick on a large tree (10k files in 100
// directories, bin/async/watch-tree): PollWatcher scans all of it each
// tick, SampledWatcher checks 16 recent paths and a slice of the rest
// (max(64, n / 20)). CPU milliseconds per tick, nothing changing.
//   WatchBench [files]
class WatchBench {
	static function main() {
		var n = Std.parseInt(Sys.args()[0] ?? "") ?? 10000;
		var root = "bin/async/watch-tree";
		if (!FileSystem.exists(root)) FileSystem.createDirectory(root);
		var dirs = [for (d in 0...100) '$root/d$d'], files = [];
		for (d in dirs) if (!FileSystem.exists(d)) FileSystem.createDirectory(d);
		for (i in 0...n) {
			var f = '${dirs[i % 100]}/f$i.hx';
			if (!FileSystem.exists(f)) File.saveContent(f, "class F" + i + " {}\n");
			files.push(f);
		}
		var poll = new PollWatcher([root]);
		var t0 = Sys.cpuTime();
		for (_ in 0...5) @:privateAccess poll.scan();
		var scan = (Sys.cpuTime() - t0) / 5 * 1000;
		var sampled = new SampledWatcher();
		sampled.watch(files, dirs);
		var t1 = Sys.cpuTime();
		for (_ in 0...40) sampled.tick();
		var tick = (Sys.cpuTime() - t1) / 40 * 1000;
		Sys.println('watch $n files: PollWatcher ${Math.round(scan * 10) / 10} ms a tick, SampledWatcher ${Math.round(tick * 100) / 100} ms a tick');
	}
}
