package helder.jobs;

#if (hxmc.target != "wasm32-wasi")
import sys.thread.Deque;
import sys.thread.Thread;

// The native pool: Jobs.size() threads, started at the first job, waiting
// for runs on one queue (in a safe region while they wait). A run's end is
// posted to its loop, which a post wakes (helder.async.Loop: its wake pipe).
class Pool {
	static var queue:Null<Deque<Run>>;
	static var threads = 0;

	// r queued: false without threads (Jobs.workers = 0)
	public static function submit(r:Run):Bool {
		if (queue == null) {
			threads = Jobs.size();
			if (threads <= 0) return false;
			var q = new Deque<Run>();
			queue = q;
			for (_ in 0...threads)
				Thread.create(() -> work(q));
		}
		if (threads <= 0) return false;
		queue.add(r);
		return true;
	}

	static function work(q:Deque<Run>) {
		while (true) {
			var r = q.pop(true);
			if (r == null) continue;
			r.execute();
			r.loop.post(r.finish);
		}
	}
}

// the cores this process may run on (at least one)
class Cores {
	public static function count():Int {
		var n = hxmc.unsafe.Mem.os() == 2 ? CoresWin.GetActiveProcessorCount(0xFFFF) : CoresPosix.sysconf(hxmc.unsafe.Mem.os() == 1 ? 58 : 84).toInt();
		return n > 0 ? n : 1;
	}
}

// (_SC_NPROCESSORS_ONLN: Linux's 84, macOS's 58)
@:hxmc.c @:hxmc.fast extern class CoresPosix {
	static function sysconf(name:Int):hxmc.I64;
}

// (ALL_PROCESSOR_GROUPS)
@:hxmc.c @:hxmc.fast @:hxmc.lib("kernel32") extern class CoresWin {
	static function GetActiveProcessorCount(group:Int):Int;
}
#end
