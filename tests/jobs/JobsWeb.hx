import helder.async.Async;
import helder.async.Async.TimeoutException;
import helder.jobs.*;
import helder.os.App;
import helder.os.Window;
import hxmc.unsafe.*;

// helder.jobs in a browser (tests/jobs/browser.mjs: headless Chromium), on
// App.run's loop: jobs on Web Workers instantiating this module (a GC-free
// one, a GC one, a channel, an error, a cancelled one's worker ended and
// the next job on a new one), then the canvas hidden: no frames, and a
// timer and a job still complete (as in a hidden tab).
class JobsWeb {
	static var failed = 0;

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println('JobsWeb: ${ok ? "ok" : "FAIL"}: $what' + (detail == "" ? "" : ' ($detail)'));
		if (!ok) failed++;
	}

	@:hxmc.unsafe @:hxmc.callback static function invert(job:Job):Int {
		var n = job.input.length, src = job.input.ptr, out = job.output(n);
		if (out.isNull()) return -1;
		for (i in 0...n)
			Mem.setI8(out, i, 255 - Mem.getU8(src, i));
		return 0;
	}

	// (a GC job: where it ran, and some garbage of its own)
	static function where(n:Int):{worker:Bool, sum:Int} {
		var a = [for (i in 0...n) Std.string(i)];
		return {worker: Jobs.onWorker(), sum: a.length};
	}

	static function count(ch:Channel<Int>):Void {
		for (i in 0...3) ch.send(i);
		ch.close();
	}

	static function boom(x:Int):Int
		throw "boom";

	// (a long one: cancelled)
	static function forever(x:Int):Int {
		var s = 0;
		while (true) s = (s + 1) & 0xFFFF;
		return s;
	}

	static function main() {
		var window = new Window("JobsWeb", 64, 64);
		var frames = 0;
		Async.launch(_ -> {
			var b = IoBuffer.alloc(3);
			b.set(1, 5);
			var out = Jobs.run(invert, b);
			check("a GC-free job", out.length == 3 && out.get(0) == 255 && out.get(1) == 250);
			out.free();
			var w = Jobs.run(where, 100000);
			check("a GC job on a worker", w.worker && w.sum == 100000);
			var ch = new Channel<Int>(), got = [];
			Async.scope(task -> {
				task.async(_ -> Jobs.run(count, ch));
				var v;
				while ((v = ch.receive()) != null) got.push(v);
			});
			check("a channel from a worker", got.join(",") == "0,1,2", got.join(","));
			var e = try {
				Jobs.run(boom, 1);
				"";
			} catch (e:JobError) e.message;
			check("a job's error", e == "boom", e);
			var a = haxe.Timer.stamp(), fa = frames;
			Async.delay(0.1);
			check("frames and a timer", frames - fa >= 2 && haxe.Timer.stamp() - a < 0.5, '${frames - fa} frames in ${haxe.Timer.stamp() - a} s');
			var t0 = haxe.Timer.stamp();
			var timedOut = try {
				Async.timeout(0.1, _ -> Jobs.run(forever, 0));
				"no";
			} catch (e:TimeoutException) "yes" catch (e:Dynamic) Std.string(e);
			check("a running job cancelled", timedOut == "yes" && haxe.Timer.stamp() - t0 < 0.5, timedOut);
			check("the next job, on a new worker", Jobs.run(where, 10).worker);
			// (the canvas hidden: frames stop; the loop goes on)
			Sys.println("JobsWeb: hide");
			Async.delay(0.3);
			var f0 = frames;
			Async.delay(0.2);
			var r = Jobs.run(where, 10);
			Async.delay(0.2);
			check("without frames: timers and jobs", r.worker && frames == f0, '${frames - f0} frames while hidden');
			Sys.println('JobsWeb: done ${failed}');
			App.quit();
		});
		App.run(() -> frames++, e -> switch e.kind {
			case Close: window.close();
			case _:
		});
	}
}
