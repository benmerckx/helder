package helder.image;

// Work split in strips over threads: f(from, to) for count rows in
// `threads` parts at once, the caller's thread one of them, back when all
// are done (a part's exception thrown again here). One thread, or a target
// without threads (Eval but threaded, the web): f(0, count) as it is.
class Strips {
	public static function run(threads:Int, count:Int, f:(from:Int, to:Int) -> Void) {
		#if target.threaded
		var n = Std.int(Math.max(1, Math.min(threads, count)));
		if (n > 1) {
			var done = new sys.thread.Lock(), failure:Null<Dynamic> = null;
			for (k in 1...n) {
				var from = Std.int(count * k / n), to = Std.int(count * (k + 1) / n);
				sys.thread.Thread.create(() -> {
					try f(from, to) catch (e:Dynamic) failure = e;
					done.release();
				});
			}
			try f(0, Std.int(count / n)) catch (e:Dynamic) failure = e;
			for (k in 1...n)
				done.wait();
			if (failure != null) throw failure;
			return;
		}
		#end
		f(0, count);
	}
}
