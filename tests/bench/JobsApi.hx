import haxe.io.Bytes;
import helder.async.Async;
import helder.image.ImageJobs;
import helder.image.PngDecoder;
import helder.jobs.Job;
import helder.jobs.Jobs;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.Mem;

// Jobs.hx's measurement through helder.jobs' API (`bun run test
// jobs-bench`): JobsFrame's frames at 60 fps, as a task on helder.async's
// loop (its timers and waits, as App.run drives them), while the 4K PNG is
// decoded from frame 60:
//
//   inline  ImageJobs.pixels with Jobs.workers = 0: on the loop, between frames
//   job     ImageJobs.pixels: a GC-free job on the pool (natively) or a worker (wasm)
//   gc      PngDecoder.decode as a GC job (Jobs.run), its pixels copied back
//   none    the frames alone
//
// probe: the main thread collects at the end of every frame until the
// pixels are back (Jobs.hx's). A frame's time is its work plus how late it
// started (what ran on the loop before it: the inline decode, the pixels'
// arrival, read as an upload would, then freed). One line:
//
//   api <variant> <frames> <median ms> <p99> <max> <longest pause ms> <decode ms>
//
// overhead: an empty GC-free job's and an empty GC job's round trip, from
// the awaiting task (2000 one after the other, after 100 to warm up):
//
//   overhead <free µs> <gc µs> <inline µs>
//
//   JobsApi <DejaVuSans.ttf> <photo.png> <variant> [probe] | overhead
class JobsApi {
	static inline var WARM = 60;
	static inline var WINDOW = 90;
	static inline var FRAME = 1 / 60;

	@:hxmc.unsafe @:hxmc.callback static function empty(job:Job):Int
		return 0;

	static function emptyGc(x:Int):Int
		return x;

	static function gcDecode(png:Bytes):Bytes
		return PngDecoder.decode(png).rgba;

	static function main() {
		var args = Sys.args();
		JobsFrame.garbageKb = Std.parseInt(Sys.getEnv("GARBAGE_KB") ?? "") ?? JobsFrame.garbageKb;
		#if (hxmc.target == "wasm32-wasi")
		Async.main(_ -> {
			run(args);
			Sys.stdout().flush();
			Sys.exit(0);
		});
		#else
		Async.run(_ -> run(args));
		#end
	}

	@:coroutine static function run(args:Array<String>) {
		if (args[0] == "overhead") overhead() else frames(sys.io.File.getBytes(args[0]), sys.io.File.getBytes(args[1]), args[2], args[3] == "probe");
	}

	@:coroutine static function overhead() {
		var us = [];
		for (k in 0...3) {
			if (k == 2) Jobs.workers = 0;
			for (i in 0...2100) {
				if (i == 100) us.push(haxe.Timer.stamp());
				if (k == 1) Jobs.run(emptyGc, i) else Jobs.run(empty).free();
			}
			us[k] = (haxe.Timer.stamp() - us[k]) / 2000 * 1e6;
		}
		Sys.println('overhead ${fixed(us[0])} ${fixed(us[1])} ${fixed(us[2])}');
	}

	@:coroutine static function frames(font:Bytes, png:Bytes, variant:String, probe:Bool) {
		JobsFrame.setup(font);
		var times = [], pauses = [], decode = 0.0, back = variant == "none", k = 0;
		var next = haxe.Timer.stamp();
		Async.scope(task -> {
			while (k < WARM + WINDOW || !back) {
				var s0 = hxmc.GcStats.totalPause(), t0 = haxe.Timer.stamp(), late = t0 - next > 0 ? t0 - next : 0;
				JobsFrame.frame();
				if (k == WARM && variant != "none") {
					if (variant == "inline") Jobs.workers = 0;
					var file = variant == "gc" ? null : IoBuffer.ofBytes(png);
					task.async(_ -> {
						var d0 = haxe.Timer.stamp();
						if (variant == "gc") {
							var px = Jobs.run(gcDecode, png);
							decode = (haxe.Timer.stamp() - d0) * 1000;
							JobsFrame.check += sample(i -> px.get(i), px.length);
						} else {
							var p = ImageJobs.pixels(file);
							decode = (haxe.Timer.stamp() - d0) * 1000;
							var px = p.rgba, ptr = px.ptr;
							JobsFrame.check += sample(i -> Mem.getU8(ptr, i), px.length);
							px.free();
						}
						back = true;
					});
				}
				if (probe && k >= WARM && !back) hxmc.NativeGc.collect(false);
				var t = haxe.Timer.stamp() - t0 + late;
				if (k >= WARM) {
					times.push(t * 1000);
					pauses.push((hxmc.GcStats.totalPause() - s0) * 1000);
				}
				k++;
				next += FRAME;
				var now = haxe.Timer.stamp();
				if (next < now) next = now;
				// (between frames: the loop's wait, where the job's reply lands)
				Async.delay(next - now);
			}
		});
		var sorted = times.copy();
		sorted.sort(Reflect.compare);
		pauses.sort(Reflect.compare);
		inline function at(q:Float)
			return sorted[Std.int(Math.min(sorted.length - 1, Math.ceil(q * sorted.length) - 1))];
		Sys.println(["api", variant, Std.string(times.length), fixed(at(0.5)), fixed(at(0.99)), fixed(sorted[sorted.length - 1]),
			fixed(pauses[pauses.length - 1]), fixed(decode), Std.string(Math.round(JobsFrame.check))].join(" "));
	}

	static inline function sample(get:Int->Int, n:Int):Float {
		var s = 0, i = 0;
		while (i < n) {
			s += get(i);
			i += 4099;
		}
		return s;
	}

	static function fixed(v:Float):String
		return Std.string(Math.round(v * 1000) / 1000);
}
