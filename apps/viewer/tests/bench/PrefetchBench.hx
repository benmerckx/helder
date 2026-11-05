import helder.async.Async;
import helder.jobs.Jobs;
import viewer.Decode;

// The UI's frames while files decode as jobs (the viewer's prefetch): a
// main loop of 60 "frames" a second, each allocating what a ui frame does
// (some small objects: a collection now and then), its times measured
// while Decode's job runs on each file given, twice. A GC job holds every
// collection until its next safepoint, so a frame that needs one waits:
// the longest frames say how long.
//
//   PrefetchBench file...
class PrefetchBench {
	static function main() {
		var files = Sys.args();
		var times:Array<Float> = [];
		var busy = true;
		var keep:Array<Array<Int>> = [];
		Async.run(task -> {
		var frames = task.async(_ -> {
			while (busy) {
				var t = haxe.Timer.stamp();
				// (a frame's garbage: 2000 small arrays, a few kept a while)
				for (i in 0...20000) {
					var a = [i, i + 1, i + 2];
					if (i % 100 == 0) keep.push(a);
				}
				if (keep.length > 40000) keep = [];
				times.push(haxe.Timer.stamp() - t);
				Async.delay(1 / 60);
			}
		});
			for (round in 0...2)
				for (f in files) {
					var t = haxe.Timer.stamp();
					var d = Decode.job(f);
					Decode.release(d);
					Sys.println('decoded $f: ${d.width}x${d.height} ${d.error ?? ""} in ${Math.round((haxe.Timer.stamp() - t) * 1000)} ms');
				}
			busy = false;
		});
		times.sort(Reflect.compare);
		var ms = (v:Float) -> Std.string(Math.round(v * 10000) / 10);
		Sys.println('frames: ${times.length}, p50 ${ms(times[times.length >> 1])} ms, p99 ${ms(times[Std.int(times.length * 0.99)])} ms, max ${ms(times[times.length - 1])} ms');
	}
}
